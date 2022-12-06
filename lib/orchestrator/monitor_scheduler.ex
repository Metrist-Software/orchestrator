defmodule Orchestrator.MonitorScheduler do
  @moduledoc """
  Process to control a monitor. The monitor itself is invoked through the passed `invoke` function, which
  should return a task.
  """
  use GenServer
  require Logger

  defmodule State do
    defstruct [:config, :task, :overtime, :monitor_pid]
  end

  # A long, long time ago. Epoch of the modified Julian Date
  @never "1858-11-07 00:00:00"

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    config_id = Keyword.get(opts, :config_id)
    get_config_fn = Keyword.get(opts, :get_config_fn, &Orchestrator.Configuration.get_config/1)

    config = get_config_fn.(config_id)

    GenServer.start_link(__MODULE__, config, name: name)
  end

  @impl true
  def init(config) do
    Orchestrator.Application.set_monitor_logging_metadata(config)
    Logger.info("Initialize monitor with #{inspect Orchestrator.MonitorSupervisor.redact(config)}")

    schedule_initially(config)
    {:ok, %State{config: config}}
  end

  @impl true
  def handle_cast({:config_change, new_config}, state) do
    # We simply adopt the new config; the next run will then use the new data for scheduling.
    Logger.info("Setting new config of #{inspect new_config}")
    {:noreply, %State{state | config: new_config}}
  end

  def handle_cast({:monitor_pid, pid}, state) do
    {:noreply, %State{state | monitor_pid: pid}}
  end

  @impl true
  def handle_info(:run, state) do
    Logger.info("Asked to run #{show(state)}")
    # So the next time we need to run is trivially simple now.
    Process.send_after(self(), :run, state.config.interval_secs * 1_000)
    if state.task == nil do
      Logger.info("Doing run for #{show(state)}")
      task = do_run(state.config)
      {:noreply, %State{state | task: task, overtime: false}}
    else
      # For now, this is entirely informational. We have the `:run` clock tick every `intervalSecs` and
      # will run if it is time, otherwise not. However, we can use this later on to change scheduling - an
      # overtime run ending may mean we want to schedule right away, or after half the interval, or whatever.
      Logger.info("Skipping run for #{show(state)}, marking us in overtime")
      {:noreply, %State{state | overtime: true}}
    end
  end

  # Handle various messages that flow in from subprocesses given that we trap
  # exits. Our primary concern is the task that do_run has spawned. There are four
  # exit possibilities: a regular Task completion with timeout, error, or ok and
  # a :DOWN message that signals an abnormal exit. In all cases, we consider the
  # task complete.

  def handle_info({task_ref, completion}, state) do
    Logger.info("Received task completion for #{show(state)}, completion is #{inspect completion}")
    Process.demonitor(task_ref, [:flush])
    {:noreply, %State{state | task: nil, monitor_pid: nil, overtime: false}}
  end

  def handle_info({:DOWN, _task_ref, :process, _task_pid, reason} = msg, state) do
    # Other completions of a task (like crashes) return this message.
    Logger.error("Received task down message: #{inspect msg}, reason: #{inspect reason}")
    {:noreply, %State{state | monitor_pid: nil, task: nil, overtime: false}}
  end

  # Catch-all message handler. Should not happen so we log this as an error.
  def handle_info(msg, state) do
    Logger.error("Received unknown message: #{inspect msg}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{monitor_pid: pid}) when pid != nil do
    Logger.info("Monitor Scheduler terminate callback killing os pid #{pid}")
    :exec.kill(pid, 9)
  end

  def terminate(_reason, _state) do
    # No running task so nothing to clean up
  end

  defp do_run(cfg = %{run_spec: %{run_type: "dll"}}) do
    opts = [error_report_fun: get_monitor_error_handler("dll")]
    Orchestrator.DotNetDLLInvoker.invoke(cfg, opts)
  end
  defp do_run(cfg = %{run_spec: %{run_type: "exe"}}) do
    opts = [error_report_fun: get_monitor_error_handler("exe")]
    Orchestrator.ExecutableInvoker.invoke(cfg, opts)
  end
  defp do_run(cfg = %{run_spec: %{run_type: "awslambda"}}) do
    opts = [error_report_fun: get_monitor_error_handler("awslambda")]
    Orchestrator.LambdaInvoker.invoke(cfg, opts)
  end
  defp do_run(cfg = %{run_spec: %{run_type: _}}) do
    Logger.warn("Unknown run specification in config: #{inspect Orchestrator.MonitorSupervisor.redact(cfg)}")
    Task.async(fn -> :ok end)
  end
  defp do_run(cfg) do
    invocation_style = Orchestrator.Application.invocation_style()
    Logger.info("No run specification given, running based on configured invocation style #{invocation_style}")
    opts = [error_report_fun: get_monitor_error_handler(invocation_style)]
    case invocation_style do
      "rundll" ->
        Orchestrator.DotNetDLLInvoker.invoke(cfg, opts)
      "awslambda" ->
        Orchestrator.LambdaInvoker.invoke(cfg, opts)
      other ->
        Logger.warn("Unknown invocation style #{other}, ignoring.")
        Task.async(fn -> :ok end)
    end
  end

  defp show(state) do
    name =
      if state.config.steps == nil do
        state.config.monitor_logical_name
      else
        "#{state.config.monitor_logical_name}.#{inspect Enum.map(state.config.steps, &(&1.check_logical_name))}"
      end
    state =
      if state.task != nil do
        if state.overtime do
          "in overtime"
        else
          "running"
        end
      else
        "idle"
      end
    "#{name} (#{state})"
  end

  # Helpers for the initial scheduling. After the initial scheduling, which introduces a
  # variable sleep, we just tick every interval_secs.

  defp schedule_initially(config) do
    {:ok, last_run} = NaiveDateTime.from_iso8601(config.last_run_time || @never)
    time_to_next_run = time_to_next_run(last_run, config.interval_secs) + :rand.uniform(config.interval_secs)
    Logger.debug("Schedule next run in #{time_to_next_run} seconds")
    Process.send_after(self(), :run, time_to_next_run * 1_000)
  end

  def time_to_next_run(nil, _interval), do: 0
  def time_to_next_run(last_run, interval), do: time_to_next_run(last_run, interval, NaiveDateTime.utc_now())
  def time_to_next_run(last_run, interval, now) do
    next_run = NaiveDateTime.add(last_run, interval, :second)
    max(NaiveDateTime.diff(next_run, now, :second), 0)
  end

  def get_monitor_error_handler(run_type) do
    fn monitor_logical_name, check_logical_name, message, opts ->
      monitor_error_handler(run_type, monitor_logical_name, check_logical_name, message, opts)
    end
  end

  @dotnet_http_error_match ~r/HttpRequestException.*(40[13]|429)/

  def monitor_error_handler("dll", monitor_logical_name, check_logical_name, message, opts) do
    if Orchestrator.SlackReporter.is_configured? do
      with [_match, status] <- Regex.run(@dotnet_http_error_match, message) do
        Orchestrator.SlackReporter.send_monitor_error(
          monitor_logical_name,
          check_logical_name,
          "Received HTTP #{status} response"
        )
      end
    end

    monitor_error_handler(nil, monitor_logical_name, check_logical_name, message, opts)
  end

  def monitor_error_handler(_, monitor_logical_name, check_logical_name, message, opts) do
    Orchestrator.APIClient.write_error(monitor_logical_name, check_logical_name, message, opts)
  end

  # Purely for testing the regex
  def dotnet_http_error_match, do: @dotnet_http_error_match
end
