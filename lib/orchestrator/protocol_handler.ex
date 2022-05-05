defmodule Orchestrator.ProtocolHandler do
  @moduledoc """
  Protocol implementation. This works in concert with the invoker process to handle
  message back and forth.
  """

  use GenServer
  require Logger
  @major 1
  @minor 1
  @max_monitor_runtime 15 * 60 * 1_000
  @exit_timeout 5 * 60 * 1_000

  # Tag to represent a step error from one of CANARY's monitors for log filtering
  @monitor_error_tag "METRIST_MONITOR_ERROR"


  defmodule State do
    @type t() :: %__MODULE__{
      monitor_logical_name: String.t(),
      steps: [String.t()],
      io_handler: pid,
      telemetry_report_fun: function(),
      error_report_fun: function(),
      current_step: String.t(),
      step_start_time: integer(),
      step_timeout_timer: reference(),
      webhook_waiting_for: String.t()
    }
    defstruct [:monitor_logical_name, :steps, :io_handler, :telemetry_report_fun, :error_report_fun,
               :current_step, :step_start_time, :step_timeout_timer, :webhook_waiting_for]
  end

  def run_protocol(config, port, opts \\ []) do
    Orchestrator.Application.set_monitor_metadata(config)
    error_report_fun = Keyword.get(opts, :error_report_fun, &Orchestrator.APIClient.write_error/4)
    telemetry_report_fun = Keyword.get(opts, :telemetry_report_fun, &Orchestrator.APIClient.write_telemetry/4)
    os_pid = Keyword.get(Port.info(port), :os_pid)

    ref = Port.monitor(port)
    :ok = handle_handshake(port, config)
    {:ok, pid} =
      GenServer.start_link(__MODULE__, {config.monitor_logical_name,
                                        config.steps,
                                        self(),
                                        telemetry_report_fun,
                                        error_report_fun,
                                        os_pid})
    result = wait_for_complete(port, ref, config.monitor_logical_name, pid)
    # Don't trust anything to exit voluntarily
    kill_or_close(port)
    Logger.info("Monitor is complete")
    result
  end

  defp wait_for_complete(port, ref, monitor_logical_name, protocol_handler, previous_partial_message \\ "") do
    receive do
      {:DOWN, ^ref, :port, ^port, reason} ->
        Logger.info(
          "Received DOWN message, reason: #{inspect(reason)}, completing invocation."
        )
        :ok

      {^port, {:data, data}} ->
        case handle_message(protocol_handler, monitor_logical_name, previous_partial_message <> data) do
          {:incomplete, message} ->
            # append to returned partial message as this partial piece was not complete
            wait_for_complete(port, ref, monitor_logical_name, protocol_handler, message)
          {:ok, _} ->
            # call wait_for_complete normally
            wait_for_complete(port, ref, monitor_logical_name, protocol_handler)
          {:error, message} ->
            Logger.warn("Skipping unparsable message: #{message}")
            # call wait_for_complete normally but skip the bad message
            wait_for_complete(port, ref, monitor_logical_name, protocol_handler)
        end

      {:write, message} ->
        Orchestrator.ProtocolHandler.write(port, message)
        wait_for_complete(port, ref, monitor_logical_name, protocol_handler)

      :force_exit ->
        Logger.error("Monitor did not complete after receiving Exit command in #{@exit_timeout}ms, killing it")
        {:error, :timeout}

      msg ->
        Logger.debug("Ignoring message #{inspect(msg)}")
        wait_for_complete(port, ref, monitor_logical_name, protocol_handler)
    after
      @max_monitor_runtime ->
        Logger.error("Monitor did not complete in time, killing it")
        {:error, :timeout}
    end
  end

  def handle_message(pid, monitor_logical_name, message) do
    case Integer.parse(message) do
      {len, rest} ->
        message_body = String.slice(rest, 1, len)
        if (len > String.length(message_body)) do
          # Incomplete message
          # Send message back if we can't process it
          # so that future data can be appended
          {:incomplete, message}
        else
          GenServer.cast(pid, {:message, message_body})
          # If there's more, try to process more (but it may be incomplete)
          handle_message(pid, monitor_logical_name, String.slice(rest, 1 + len, 100_000))
        end
      :error ->
        if String.length(message) > 0 do
          {:error, message}
        else
          # This is actually the catch all. Odd but this
          # is the success exit condition as there will either be an
          # incomplete message left or nothing and nohting will trigger
          # an :error trying to parse
          {:ok, nil}
        end
    end
  end

  defp handle_handshake(port, config) do
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

  # Server side of protocol handling.

  @impl true
  def init({monitor_logical_name, steps, io_handler, telemetry_report_fun, error_report_fun, os_pid}) do
    Orchestrator.Application.set_monitor_metadata(monitor_logical_name, steps)
    Logger.metadata(os_pid: os_pid)
    {:ok, %State{monitor_logical_name: monitor_logical_name, steps: steps, io_handler: io_handler, telemetry_report_fun: telemetry_report_fun, error_report_fun: error_report_fun}}
  end

  @impl true
  def handle_cast({:message, "Configured"}, state) do
    Logger.info("Monitor fully configured, start stepping")
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
      state = cancel_timer(state)

      {time, metadata} =
        case String.split(rest) do
          [just_the_timing] ->
            {time, _} = Float.parse(just_the_timing)
            {time, %{}}
          [metadata, timing] ->
            {time, _} = Float.parse(timing)
            metadata = parse_metadata(metadata)
            {time, metadata}
        end

      state.telemetry_report_fun.(state.monitor_logical_name, state.current_step.check_logical_name, time, metadata)
      start_step()
      {:noreply, %State{state | current_step: nil, step_start_time: nil}}
    end)
  end
  def handle_cast({:message, msg = <<"Step OK", rest::binary>>}, state) do
    when_current_step(msg, state, fn ->
      state = cancel_timer(state)
      time_taken = :erlang.monotonic_time(:millisecond) - state.step_start_time
      metadata = parse_metadata(rest)
      state.telemetry_report_fun.(state.monitor_logical_name, state.current_step.check_logical_name, time_taken / 1, metadata)
      start_step()
      {:noreply, %State{state | current_step: nil, step_start_time: nil}}
    end)
  end
  def handle_cast({:message, msg = <<"Step Error", rest::binary>>}, state) do
    when_current_step(msg, state, fn ->
      state = cancel_timer(state)
      Logger.error("#{state.monitor_logical_name}: step error #{state.current_step.check_logical_name}: #{rest} - #{@monitor_error_tag}")
      rest = String.trim(rest)
      {error_msg, metadata} =
        case String.split(rest, " ", parts: 2) do
          [just_one_word] ->
            {just_one_word, %{}}
          [maybe_meta, error_msg] ->
            case parse_metadata(maybe_meta) do
              m when m == %{} ->
                {rest, %{}}
              meta ->
                {error_msg, meta}
            end
        end
      error_msg = String.trim(error_msg)

      state.error_report_fun.(state.monitor_logical_name, state.current_step.check_logical_name, error_msg, metadata)
      # When a step errors, we are going to assume that subsequent steps will error as well.
      send_exit(state)
      {:stop, :normal, %State{state | current_step: nil, step_start_time: nil}}
      end)
  end
  def handle_cast({:message, <<"Exit", _::binary>>}, state) do
    Logger.info("Monitor completed shutdown")
    {:stop, :normal, state}
  end
  def handle_cast({:message, <<"Wait For Webhook", rest::binary>>}, state) do
    Logger.info("Monitor requested wait for #{rest}")
    start_webhook_wait()
    {:noreply, %State{state | webhook_waiting_for: String.trim(rest)}}
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

  defp cancel_timer(state) do
    case state.step_timeout_timer do
      nil ->
        state
      timer ->
        Process.cancel_timer(timer)
        %State{state | step_timeout_timer: nil}
    end
  end

  @impl true
  def handle_info(:start_step, state) when length(state.steps) > 0 do
    [step | remaining_steps] = state.steps
    Logger.info("#{state.monitor_logical_name}: Starting step #{inspect step}")

    send_msg("Run Step #{step.check_logical_name}", state)
    timer = Process.send_after(self(), :step_timeout, round(step.timeout_secs * 1_000))

    {:noreply, %State{state |
                      steps: remaining_steps,
                      current_step: step,
                      step_start_time: :erlang.monotonic_time(:millisecond),
                      step_timeout_timer: timer}}
  end
  def handle_info(:start_step, state) do
    Logger.info("All steps done, asking monitor to exit")
    send_exit(state)
    {:noreply, state}
  end
  def handle_info(:step_timeout, state) do
    if is_nil(state.current_step) do
      {:noreply, state}
    else
      Logger.error("Timeout on step #{inspect state.current_step}, exiting")
      state.error_report_fun.(state.monitor_logical_name, state.current_step.check_logical_name, "Timeout: check did not complete within #{state.current_step.timeout_secs} seconds - #{@monitor_error_tag}", %{})
      send_exit(state)
      {:stop, :normal, state}
    end
  end
  def handle_info(:check_webhook_wait, state) do
    wait = state.webhook_waiting_for
    case Orchestrator.APIClient.get_webhook(wait, state.monitor_logical_name) do
      nil ->
        # Check every 5 seconds or until we are killed
        Process.send_after(self(), :check_webhook_wait, round(5 * 1_000))
        {:noreply, state}
      webhook ->
        json = Jason.encode!(webhook)
        Logger.info("Found webhook. Returning #{json}")
        send_msg("Webhook Wait Response #{json}", state)
        {:noreply, %State{state | webhook_waiting_for: nil}}
    end
  end


  defp send_exit(state) do
    do_cleanup = if Orchestrator.Application.do_cleanup?(), do: "1", else: "0"
    send_msg("Exit #{do_cleanup}", state)
    Process.send_after(state.io_handler, :force_exit, @exit_timeout)
  end

  defp send_msg(msg, state) do
    send state.io_handler, {:write, msg}
  end

  defp start_step() do
    send self(), :start_step
  end

  defp start_webhook_wait() do
    send self(), :check_webhook_wait
  end

  defp do_log(level, message, state) do
    message = String.trim(message)
    if String.length(message) > 0 do
      Logger.log(level, "Received log: #{message}")
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

  # Monitors should not have to do any shutdown activities by the time
  # we really want to force quit them, so if a port has an associated
  # OS process, we just send it a KILL signal to guarantee success. Otherwise,
  # we close the port and hope for the best.
  defp kill_or_close(port) do
    maybe_info = Port.info(port)
    maybe_pid = Keyword.get((maybe_info || []), :os_pid)
    case {maybe_info, maybe_pid} do
      {nil, _} ->
        Logger.info("Port already closed")
      {_, nil} ->
        Logger.info("No OS process id associated with port, just closing it")
        Port.close(port)
      {_, pid} ->
        Logger.info("Port is associated with OS process #{maybe_pid}, killing it")
        # Wrapped System.cmd/2 call with try catch since it raises an ` Erlang error: :enoent` occasionally
        try do
          # A kill -9 may not get rid of subprocesses of the monitor. Do a two step kill.
          kill = fn sig -> System.cmd("kill", ["-#{sig}", "#{pid}"]) end
          kill.(15)
          Process.sleep(1_000)
          kill.(9)
        rescue
          e -> Logger.error("Got error killing process #{inspect(pid)}: #{Exception.format(:error, e, __STACKTRACE__)}")
        end
    end
  end

  # Public for testing
  def parse_metadata(nil), do: %{}
  def parse_metadata(s) do
    try do
	    try_parse_metadata(s)
    rescue
      _ ->
        Logger.warn("Could not parse as metadata: '#{s}', ignoring")
        %{}
    end
  end
  defp try_parse_metadata(s) do
    s
    |> String.trim()
    |> String.split(",")
    |> Enum.map(fn elem ->
      case String.split(elem, "=") do
        [""] -> nil
        [key, val] -> {key, try_decode(val)}
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp try_decode(val) do
    decoded =
      case Base.decode16(String.upcase(val)) do
        :error -> val
        {:ok, decoded} -> decoded
      end
    case Float.parse(decoded) do
      {val, ""} -> val
      {_, _rest} -> decoded
      :error -> decoded
    end
  end

end
