defmodule Orchestrator.MonitorScheduler do
  @moduledoc """
  Process to control a monitor. The monitor itself is invoked through the passed `invoke` function, which
  should return a task.
  """
  use GenServer
  require Logger

  defmodule State do
    defstruct [:config, :task, :overtime]
  end

  # A long, long time ago. Epoch of the modified Julian Date
  @never "1858-11-07 00:00:00"

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    config = Keyword.get(opts, :config_id)
    |> Orchestrator.Configuration.get_config()

    GenServer.start_link(__MODULE__, config, name: name)
  end

  @impl true
  def init(config) do
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

  # As we're a GenServer, all Task completion messages arrive as info messages.

  @impl true
  def handle_info({_task_ref, {:error, error}}, state) do
    Logger.error("Received task error for #{show(state)}, error is: #{inspect error}")
    {:noreply, %State{state | task: nil, overtime: false}}
  end

  @impl true
  def handle_info({_task_ref, result}, state) do
    Logger.info("Received task completion for #{show(state)}, result is #{inspect result}")
    {:noreply, %State{state | task: nil, overtime: false}}
  end

  @impl true
  def handle_info({:DOWN, _task_ref, :process, _task_pid, :normal}, state) do
    # Safely ignored, we did the work in the task completion handlers, above
    {:noreply, state}
  end

  defp do_run(cfg = %{run_spec: %{run_type: "dll"}}) do
    Orchestrator.DotNetDLLInvoker.invoke(cfg)
  end
  defp do_run(cfg = %{run_spec: %{run_type: "exe"}}) do
    Orchestrator.ExecutableInvoker.invoke(cfg)
  end
  defp do_run(cfg = %{run_spec: %{run_type: "awslambda"}}) do
    Orchestrator.LambdaInvoker.invoke(cfg)
  end
  defp do_run(cfg = %{run_spec: %{run_type: _}}) do
    Logger.warn("Unknown run specification in config: #{inspect Orchestrator.MonitorSupervisor.redact(cfg)}")
    Task.async(fn -> :ok end)
  end
  defp do_run(cfg) do
    invocation_style = Orchestrator.Application.invocation_style()
    Logger.info("No run specification given, running based on configured invocation style #{invocation_style}")
    case invocation_style do
      "rundll" ->
        Orchestrator.DotNetDLLInvoker.invoke(cfg)
      "awslambda" ->
        Orchestrator.LambdaInvoker.invoke(cfg)
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
    Process.send_after(self(), :run, time_to_next_run * 1_000)
  end

  def time_to_next_run(nil, _interval), do: 0
  def time_to_next_run(last_run, interval), do: time_to_next_run(last_run, interval, NaiveDateTime.utc_now())
  def time_to_next_run(last_run, interval, now) do
    next_run = NaiveDateTime.add(last_run, interval, :second)
    max(NaiveDateTime.diff(next_run, now, :second), 0)
  end
 end
