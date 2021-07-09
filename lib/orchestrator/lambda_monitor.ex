defmodule Orchestrator.LambdaMonitor do
  @moduledoc """
  Process to control a lambda monitor.
  """
  use GenServer
  require Logger

  defmodule State do
    defstruct [:config, :task, :overtime, :region]
  end

  # A long, long time ago. Epoch of the modified Julian Date
  @never "1858-11-07 00:00:00"

  def start_link(opts) do
    config = Keyword.get(opts, :config)
    name = Keyword.get(opts, :name)
    region = Application.get_env(:orchestrator, :aws_region)
    GenServer.start_link(__MODULE__, {config, region}, name: name)
  end

  @impl true
  def init({config, region}) do
    Logger.info("Initialize lambda monitor with #{inspect config}")
    schedule_initially(config)
    {:ok, %State{config: config, region: region}}
  end

  @impl true
  def handle_info(:run, state) do
    Logger.info("Asked to run #{show(state)}")
    if state.task == nil do
      Logger.info("Doing run for #{show(state)}")
      Process.send_after(self(), :run, state.config.intervalSecs * 1_000)
      task = invoke(state.config, state.region)
      {:noreply, %State{state | task: task, overtime: false}}
    else
      # For now, this is entirely informational. We have the `:run` clock tick every `intervalSecs` and
      # will run if it is time, otherwise not. However, we can use this later on to change scheduling - an
      # overtime run ending may mean we want to schedule right away, or after half the interval, or whatever.
      Logger.info("Skipping run for #{show(state)}, marking us in overtime")
      {:noreply, %State{state | overtime: true}}
    end
  end

  @impl true
  def handle_info({:config_change, new_config}, state) do
    # We simply adopt the new config; the next run will then use the new data for scheduling.
    {:noreply, %State{state | config: new_config}}
  end

  # As we're a GenServer, all Task completion messages arrive as info messages.

  @impl true
  def handle_info({_task_ref, {:error, error}}, state) do
    Logger.error("Received task error for #{show(state)}, error is: #{inspect error}")
    {:noreply, %State{state | task: nil, overtime: false}}
  end

  @impl true
  def handle_info({_task_ref, {:ok, result}}, state) do
    Logger.info("Received task completion for #{show(state)}, result is #{inspect result}")
    {:noreply, %State{state | task: nil, overtime: false}}
  end

  @impl true
  def handle_info({:DOWN, _task_ref, :process, _task_pid, :normal}, state) do
    # Safely ignored, we did the work in the task completion handlers, above
    {:noreply, state}
  end

  defp show(state) do
    name =
      if state.config.checkName == nil do
        state.config.monitorName
      else
        "#{state.config.monitorName}.#{state.config.checkName}"
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

  # Helpers for the first time (when we start) scheduling of a run, based on the
  # last run value of either the monitor or the check we are supposed to run.
  defp schedule_initially(config = %{checkName: nil}) do
    # Schedule a whole monitor
    {:ok, last_run} = (config.monitor.instance.lastReport || @never)
    |> NaiveDateTime.from_iso8601()
    do_schedule_initially(config, last_run)
  end
  defp schedule_initially(config) do
    # Schedule a single check style monitor
    {:ok, last_run} = config.monitor.instance.checkLastReports
    |> Enum.find(%{value: @never}, fn clr -> clr.key == config.checkName end)
    |> Map.get(:value)
    |> NaiveDateTime.from_iso8601()
    do_schedule_initially(config, last_run)
  end

  defp do_schedule_initially(config, last_run) do
    time_to_next_run = time_to_next_run(last_run, config.intervalSecs)
    Process.send_after(self(), :run, time_to_next_run * 1_000)
  end

  def time_to_next_run(nil, _interval), do: 0
  def time_to_next_run(last_run, interval), do: time_to_next_run(last_run, interval, NaiveDateTime.utc_now())
  def time_to_next_run(last_run, interval, now) do
    next_run = NaiveDateTime.add(last_run, interval, :second)
    max(NaiveDateTime.diff(next_run, now, :second), 0)
  end

  # Only these bits are actually AWS Lambda specific.
  defp invoke(config, region) do
    name = lambda_function_name(config)
    req = ExAws.Lambda.invoke(name, %{}, %{}, invocation_type: :request_response)
    Logger.debug("About to spawn request #{inspect req}")
    # We spawn this as a task, so that we can keep receiving messages and do things like handle timeouts eventually.
    Task.async(fn -> ExAws.request(req, region: region, http_opts: [recv_timeout: 900_000], retries: [max_attempts: 1]) end)
  end

  defp lambda_function_name(%{functionName: function_name}) when not is_nil(function_name), do: lambda_function_name(function_name)
  defp lambda_function_name(%{monitorName: monitor_name}), do: lambda_function_name(monitor_name)
  defp lambda_function_name(name) when is_binary(name), do: "monitor-#{name}-#{env()}-#{name}Monitor"

  defp env, do: System.get_env("ENVIRONMENT_TAG", "local-development")
 end
