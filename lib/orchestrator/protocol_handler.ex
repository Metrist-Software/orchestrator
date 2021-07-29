defmodule Orchestrator.ProtocolHandler do
  @moduledoc """
  Protocol implementation. This works in concert with the invoker process to handle
  message back and forth.
  """

  use GenServer
  require Logger
  @major 1
  @minor 1

  defmodule State do
    @type t() :: %__MODULE__{
      monitor_logical_name: String.t(),
      steps: [String.t()],
      io_handler: pid,
      current_step: String.t(),
      step_start_time: integer()
    }
    defstruct [:monitor_logical_name, :steps, :io_handler, :current_step, :step_start_time]
  end

  def start_link(monitor_logical_name, steps, io_handler) do
    # We only need the step name for now, this simplifies the code a bit.
    steps = Enum.map(steps, &(&1.check_logical_name))
    GenServer.start_link(__MODULE__, {monitor_logical_name, steps, io_handler})
  end

  def handle_message(pid, monitor_logical_name, message) do
    message = String.trim(message)
    case Integer.parse(message) do
      {len, rest} ->
        message = String.slice(rest, 1, len)
        GenServer.cast(pid, {:message, message})
        # If there's more, process more.
        handle_message(pid, monitor_logical_name, String.slice(rest, 1 + len, 100_000))
      :error ->
        if String.length(message) > 0 do
          Logger.debug("#{monitor_logical_name}: stdout: #{message}")
        end
    end
  end

  # We keep this code synchronous to the caller so we know the whole thing is done
  # as when the protocol handler genserver is started.
  def handle_handshake(port, config) do
    matches = expect(port, ~r/Started ([0-9]+)\.([0-9]+)/)
    {major, _} = Integer.parse(Enum.at(matches, 1))
    {minor, _} = Integer.parse(Enum.at(matches, 2))
    assert_compatible(config.monitor_logical_name, major, minor)
    write(port, "Version #{@major}.#{@minor}")
    expect(port, ~r/Ready/)
    json = Jason.encode!(config.extra_config || %{})
    write(port, "Config #{json}")
    :ok
  end

  @impl true
  def init({monitor_logical_name, steps, io_handler}) do
    {:ok, %State{monitor_logical_name: monitor_logical_name, steps: steps, io_handler: io_handler}}
  end

  @impl true
  def handle_cast({:message, "Configured"}, state) do
    Logger.info("Monitor #{state.monitor_logical_name} fully configured, start stepping")
    start_step()
    {:noreply, state}
  end
  @impl true
  def handle_cast({:message, <<"Log Debug ", rest::binary>>}, state) do
    do_log(:debug, rest, state)
  end
  @impl true
  def handle_cast({:message, <<"Log Info ", rest::binary>>}, state) do
    do_log(:info, rest, state)
  end
  @impl true
  def handle_cast({:message, <<"Log Warning ", rest::binary>>}, state) do
    do_log(:warning, rest, state)
  end
  @impl true
  def handle_cast({:message, <<"Log Error ", rest::binary>>}, state) do
    do_log(:error, rest, state)
  end
  def handle_cast({:message, msg = <<"Step Time ", rest::binary>>}, state) do
    when_current_step(msg, state, fn ->
      {time, _} = Float.parse(rest)
      Orchestrator.APIClient.write_telemetry(state.monitor_logical_name, state.current_step, time)
      start_step()
      {:noreply, %State{state | current_step: nil, step_start_time: nil}}
    end)
  end
  def handle_cast({:message, msg = "Step OK"}, state) do
    when_current_step(msg, state, fn ->
      time_taken = :erlang.monotonic_time(:millisecond) - state.step_start_time
      Orchestrator.APIClient.write_telemetry(state.monitor_logical_name, state.current_step, time_taken / 1)
      start_step()
      {:noreply, %State{state | current_step: nil, step_start_time: nil}}
    end)
  end
  def handle_cast({:message, msg = <<"Step Error", rest::binary>>}, state) do
    when_current_step(msg, state, fn ->
      Logger.error("#{state.monitor_logical_name}: step error #{state.current_step}: #{rest}")
      Orchestrator.APIClient.write_error(state.monitor_logical_name, state.current_step, rest)
      # When a step errors, we are going to assume that subsequent steps will error as well.
      send_exit(state)
      {:stop, :normal, %State{state | current_step: nil, step_start_time: nil}}
    end)
  end
  def handle_cast({:message, <<"Exit", _::binary>>}, state) do
    Logger.info("Monitor completed shutdown")
    {:stop, :normal, state}
  end
  def handle_cast({:message, other}, state) do
    Logger.error("Unexpected message: [#{inspect other}] received, exiting")
    send_exit(state)
    {:stop, :normal, state}
  end

  defp when_current_step(msg, state, function) do
    if is_nil(state.current_step) do
      Logger.error("Received '#{msg}' with no step in progress, exiting")
      send_exit(state)
      {:stop, :normal, state}
    else
      function.()
    end
  end

  @impl true
  def handle_info(:start_step, state) when length(state.steps) > 0 do
    [step | steps] = state.steps
    Logger.info("#{state.monitor_logical_name}: Starting step #{step}")
    send_msg("Run Step #{step}", state)
    {:noreply, %State{state | steps: steps, current_step: step, step_start_time: :erlang.monotonic_time(:millisecond)}}
  end
  def handle_info(:start_step, state) do
    Logger.info("#{state.monitor_logical_name}: All steps done, asking monitor to exit")
    send_exit(state)
    {:noreply, state}
  end

  defp send_exit(state) do
    do_cleanup = if Orchestrator.Application.do_cleanup?(), do: "1", else: "0"
    send_msg("Exit #{do_cleanup}", state)
  end

  defp send_msg(msg, state) do
    send state.io_handler, {:write, msg}
  end

  defp start_step() do
    send self(), :start_step
  end
  defp do_log(level, message, state) do
    message = String.trim(message)
    if String.length(message) > 0 do
      Logger.log(level, "#{state.monitor_logical_name} received log: #{message}")
    end
    {:noreply, state}
  end

  defp assert_compatible(monitor_logical_name, major, _minor) when major != @major,
    do: raise("#{monitor_logical_name}: Incompatible major version, got #{major}, want #{@major}")
  defp assert_compatible(monitor_logical_name, _major, minor) when minor > @minor,
    do: raise("#{monitor_logical_name}: Incompatible minor version, got #{minor}, want >= #{@minor}")
  defp assert_compatible(_monitor_logical_name, _major, _minor), do: :ok

  # Technically the protocol is not dependent on using a Port and this stuff should move elsewhere. However,
  # for now it is convenient to keep things together that are protocol-related.

  defp expect(port, regex) do
    msg = read(port)
    Regex.run(regex, msg)
  end

  defp read(port) do
    receive do
      {^port, {:data, data}} ->
        Logger.debug("Received data: #{inspect data}")
        case Integer.parse(data) do
          {len, rest} ->
            # This should not happen, but if it does, we can always make a more complex read function. For now, good enough.
            # Note that technically, we can have other stuff interfering here, or multiple messages in one go, but at this
            # part in the protocol (we only get called from the handshake) we should not be too worried about that.
            if len + 1 != String.length(rest), do: raise "Unexpected message, expected #{len} bytes, got \"#{rest}\""
            String.trim_leading(rest)
          :error ->
            Logger.info("Ignoring monitor output: #{data}")
            read(port)
        end
    after
      60_000->
        raise "Nothing read during handshake"
    end
  end

  def write(port, msg) do
    len =
      msg
      |> String.length()
      |> Integer.to_string()
      |> String.pad_leading(5, "0")
    msg = len <> " " <> msg
    Port.command(port, msg)
    Logger.debug("Sent message: #{inspect msg}")
  end

end
