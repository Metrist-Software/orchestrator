defmodule Orchestrator.MonitorScheduler do
  @moduledoc """
  Process to control a monitor. The monitor itself is invoked through the passed `invoke` function, which
  should return a task.
  """
  use GenServer
  require Logger
  alias Orchestrator.Configuration

  defmodule State do
    defstruct [:config, :config_id, :task, :overtime, :monitor_pid]
  end

  # How often we force re-reading configuration. This is mostly to ensure that
  # changes in secrets propagate.
  @config_refresh_interval_ms :timer.minutes(10)

  # A long, long time ago. Epoch of the modified Julian Date
  @never "1858-11-07 00:00:00"

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    config_id = Keyword.get(opts, :config_id)

    GenServer.start_link(__MODULE__, config_id, name: name)
  end

  @doc """
  Ask scheduler to re-read te config.
  """
  def config_change(name) do
    GenServer.cast(name, :config_change)
  end

  @impl true
  def init(config_id) do
    Process.flag(:trap_exit, true)

    config = Configuration.get_config(config_id)

    Orchestrator.Application.set_monitor_logging_metadata(config)
    Logger.info("Initialize monitor with #{inspect Configuration.redact(config)}")

    Orchestrator.MonitorRunningAlerting.track_monitor(config)

    schedule_initially(config)
    schedule_config_change()
    {:ok, %State{config: config, config_id: config_id}}
  end

  @impl true
  def handle_cast(:config_change, state) do
    # We simply fetch the new config; the next run will then use the new data for scheduling.
    config = Configuration.get_config(state.config_id)

    Logger.info("Config change: setting new config to #{inspect Configuration.redact(config)}.")
    {:noreply, %State{state | config: config}}
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
      Orchestrator.MonitorRunningAlerting.update_monitor(state.config)
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

  # Ideally, if we get a forced config change from the backend, we should reschedule
  # our config change but that's a lot of complication for avoiding the extremely occasional
  # double invocation. Except for secrets, config reads are extremely cheap anyway.
  def handle_info(:config_change, state) do
    Logger.info("Config change: timed refresh of configuration called.")
    schedule_config_change()
    handle_cast(:config_change, state)
  end

  # Handle various messages that flow in from subprocesses given that we trap
  # exits. Our primary concern is the task that do_run has spawned. There are four
  # exit possibilities: a regular Task completion with timeout, error, or ok and
  # a :DOWN message that signals the process exited before our state machine
  # completed. In all cases, we consider the task complete.

  def handle_info({task_ref, completion}, state) do
    Logger.info("Received task completion for #{show(state)}, completion is #{inspect completion}")
    Process.demonitor(task_ref, [:flush])
    {:noreply, %State{state | task: nil, monitor_pid: nil, overtime: false}}
  end

  def handle_info({:DOWN, _task_ref, :process, _task_pid, reason} = msg, state) do
    Logger.info("Received task down message: #{inspect msg}, reason: #{inspect reason}")
    {:noreply, %State{state | monitor_pid: nil, task: nil, overtime: false}}
  end

  # Catch-all message handler. Should not happen so we log this as an error.
  def handle_info(msg, state) do
    Logger.error("Received unknown message: #{inspect msg}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %State{monitor_pid: pid, config: config}) when pid != nil do
    Logger.info("Monitor Scheduler terminate callback killing os pid #{pid}")
    :exec.kill(pid, 9)

    Orchestrator.MonitorRunningAlerting.untrack_monitor(config)
  end

  def terminate(_reason, %State{config: config}) do
    Orchestrator.MonitorRunningAlerting.untrack_monitor(config)
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
    Logger.warn("Unknown run specification in config: #{inspect Configuration.redact(cfg)}")
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

  defp schedule_config_change() do
    Process.send_after(self(), :config_change, @config_refresh_interval_ms)
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
