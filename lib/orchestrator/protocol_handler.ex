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

  # Tag to represent a step error from one of METRIST's monitors for log filtering
  @monitor_error_tag "METRIST_MONITOR_ERROR"


  defmodule State do
    @type t() :: %__MODULE__{
      monitor_logical_name: String.t(),
      steps: [String.t()],
      owner: pid,
      telemetry_report_fun: function(),
      error_report_fun: function(),
      current_step: String.t(),
      step_start_time: integer(),
      step_timeout_timer: reference(),
      webhook_waiting_for: String.t()
    }
    defstruct [:monitor_logical_name, :steps, :owner, :telemetry_report_fun, :error_report_fun,
               :current_step, :step_start_time, :step_timeout_timer, :webhook_waiting_for]
  end

  @doc """
  Run the Orchestrator protocol for the given configuration and using the running monitor.

  This will setup handshake, handle timeouts, and generally do the whole processing associated
  with the protocol as documented in [the protocol documentation](docs/protocol.md).

  - `config` is the monitor configuration.
  - `os_pid` refers to a process that has been started using Erlexec.
  - `opts` can optionally override the reporting callbacks for errors and telemetry

  The code is implemented using a genserver process that does a lot of the actual I/O and
  the calling process blocking until the monitor is done. In this way, we can easily handle
  timeouts, etcetera, but it does complicate things a little bit.
  """
  def run_protocol(config, os_pid, opts \\ []) do
    Orchestrator.Application.set_monitor_logging_metadata(config)
    error_report_fun = Keyword.get(opts, :error_report_fun, &Orchestrator.APIClient.write_error/4)
    telemetry_report_fun = Keyword.get(opts, :telemetry_report_fun, &Orchestrator.APIClient.write_telemetry/4)

    :ok = handle_handshake(os_pid, config)
    {:ok, pid} =
      GenServer.start_link(__MODULE__, {config.monitor_logical_name,
                                        config.steps,
                                        self(),
                                        telemetry_report_fun,
                                        error_report_fun,
                                        os_pid})

    result = wait_for_complete(os_pid, config.monitor_logical_name, pid)

    # There's a race here, and GenServer.stop takes its business seriously: if we try to
    # stop an already stopped process, it'll end up exiting us. This is one of the rare
    # instances where we don't care about the outcome (either we stop it or the process stopped
    # itself, we do not care), so Process.spawn/2 is like the correct solution.
    if Process.alive?(pid), do: Process.spawn(fn -> GenServer.stop(pid) end, [])

    Logger.info("Monitor is complete")
    result
  end

  # A lot of functions from here on are public for testing.

  @doc false
  def wait_for_complete(os_pid, monitor_logical_name, protocol_handler, previous_partial_message \\ "") do
    receive do
      {:stdout, ^os_pid, data} ->
        case handle_message(protocol_handler, monitor_logical_name, previous_partial_message <> data) do
          {:incomplete, message} ->
            # append to returned partial message as this partial piece was not complete
            wait_for_complete(os_pid, monitor_logical_name, protocol_handler, message)
          {:ok, _} ->
            # call wait_for_complete normally
            wait_for_complete(os_pid, monitor_logical_name, protocol_handler)
          {:error, message} ->
            Logger.warn("Skipping unparsable message: #{message}")
            # call wait_for_complete normally but skip the bad message
            wait_for_complete(os_pid, monitor_logical_name, protocol_handler)
        end

      {:stderr, ^os_pid, data} ->
        Logger.info("monitor stderr: #{data}")
        wait_for_complete(os_pid, monitor_logical_name, protocol_handler)

      {:write, message} ->
        write(os_pid, message)
        wait_for_complete(os_pid, monitor_logical_name, protocol_handler)

      :force_exit ->
        Logger.error("Monitor did not complete after receiving Exit command in #{@exit_timeout}ms, killing it")
        {:error, :timeout}

      :exit_for_test ->
        # Unit testing only!
        :test_exit_ok

      msg ->
        Logger.debug("Ignoring message #{inspect(msg)}")
        wait_for_complete(os_pid, monitor_logical_name, protocol_handler)
    after
      @max_monitor_runtime ->
        Logger.error("Monitor did not complete in time, killing it")
        {:error, :timeout}
    end
  end

  @doc false
  def handle_message(pid, monitor_logical_name, message) do
    case Integer.parse(message) do
      {len, rest} ->
        case rest do
          <<" ", message_body::binary-size(len), new_rest::binary>> ->
            GenServer.cast(pid, {:message, message_body})
            # If there's more, try to process more (but it may be incomplete)
            handle_message(pid, monitor_logical_name, new_rest)
        _ ->
            # Incomplete message
            # Send message back if we can't process it
            # so that future data can be appended
            {:incomplete, message}
        end
      :error ->
        if byte_size(message) > 0 do
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

  @doc false
  def handle_handshake(os_pid, config, writer \\ &write/2) do
    matches = expect(os_pid, ~r/Started ([0-9]+)\.([0-9]+)/)
    {major, _} = Integer.parse(Enum.at(matches, 1))
    {minor, _} = Integer.parse(Enum.at(matches, 2))
    assert_compatible(config.monitor_logical_name, major, minor)
    writer.(os_pid, "Version #{@major}.#{@minor}")
    expect(os_pid, ~r/Ready/)
    json = Jason.encode!(config.extra_config || %{})
    writer.(os_pid, "Config #{json}")
    :ok
  end

  # Server side of protocol handling.

  @impl true
  def init({monitor_logical_name, steps, owner, telemetry_report_fun, error_report_fun, os_pid}) do
    Orchestrator.Application.set_monitor_logging_metadata(monitor_logical_name, steps)
    Logger.metadata(os_pid: os_pid)
    {:ok, %State{monitor_logical_name: monitor_logical_name, steps: steps, owner: owner, telemetry_report_fun: telemetry_report_fun, error_report_fun: error_report_fun}}
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

      state.telemetry_report_fun.(state.monitor_logical_name, state.current_step.check_logical_name, time, metadata: with_source(metadata))
      start_step()
      {:noreply, %State{state | current_step: nil, step_start_time: nil}}
    end)
  end
  def handle_cast({:message, msg = <<"Step OK", rest::binary>>}, state) do
    when_current_step(msg, state, fn ->
      state = cancel_timer(state)
      time_taken = :erlang.monotonic_time(:millisecond) - state.step_start_time
      metadata = parse_metadata(rest)
      state.telemetry_report_fun.(state.monitor_logical_name, state.current_step.check_logical_name, time_taken / 1, metadata: with_source(metadata))
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
      state.error_report_fun.(
        state.monitor_logical_name,
        state.current_step.check_logical_name,
        error_msg,
        metadata: with_source(metadata),
        blocked_steps: get_blocked_steps(state.steps)
      )
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
      state.error_report_fun.(
        state.monitor_logical_name,
        state.current_step.check_logical_name,
        "Timeout: check did not complete within #{state.current_step.timeout_secs} seconds - #{
          @monitor_error_tag
        }",
        metadata: with_source(%{}),
        blocked_steps: get_blocked_steps(state.steps)
      )
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
    Process.send_after(state.owner, :force_exit, @exit_timeout)
  end

  defp send_msg(msg, state) do
    # Done through the owner so we don't start writing in the middle of reads.
    send state.owner, {:write, msg}
  end

  defp start_step() do
    send self(), :start_step
  end

  defp start_webhook_wait() do
    send self(), :check_webhook_wait
  end

  defp do_log(level, message, state) do
    message = String.trim(message)
    if byte_size(message) > 0 do
      Logger.log(level, "Received log: #{message}")
    end
    {:noreply, state}
  end

  defp assert_compatible(monitor_logical_name, major, _minor) when major != @major,
    do: raise("#{monitor_logical_name}: Incompatible major version, got #{major}, want #{@major}")
  defp assert_compatible(monitor_logical_name, _major, minor) when minor > @minor,
    do: raise("#{monitor_logical_name}: Incompatible minor version, got #{minor}, want >= #{@minor}")
  defp assert_compatible(_monitor_logical_name, _major, _minor), do: :ok

  defp expect(os_pid, regex) do
    msg = read(os_pid)
    Regex.run(regex, msg)
  end

  defp read(os_pid) do
    receive do
      {:stdout, ^os_pid, data} ->
        Logger.debug("Received data: #{inspect data}")
        case Integer.parse(data) do
          {len, rest} ->
            # This should not happen, but if it does, we can always make a more complex read function. For now, good enough.
            # Note that technically, we can have other stuff interfering here, or multiple messages in one go, but at this
            # part in the protocol (we only get called from the handshake) we should not be too worried about that.
            if len + 1 != byte_size(rest), do: raise "Unexpected message, expected #{len} bytes, got \"#{rest}\""
            String.trim_leading(rest)
          :error ->
            Logger.info("Ignoring monitor output: #{data}")
            read(os_pid)
        end
    after
      60_000->
        raise "Nothing read during handshake"
    end
  end

  def write(os_pid, msg) do
    len =
      msg
      |> byte_size()
      |> Integer.to_string()
      |> String.pad_leading(5, "0")
    msg = len <> " " <> msg
    :exec.send(os_pid, msg)
    Logger.debug("Sent message: #{inspect msg}")
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
    |> Enum.flat_map(fn elem ->
      case String.split(elem, "=") do
        [""] -> []
        [key, val] -> [{key, try_decode(val)}]
      end
    end)
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

  defp get_blocked_steps(steps) when is_list(steps) do
    Enum.map(steps, & &1.check_logical_name)
  end
  defp get_blocked_steps(_steps), do: []

  defp with_source(metadata) do
    metadata
    |> Map.put("metrist.source", "monitor")
  end
end
