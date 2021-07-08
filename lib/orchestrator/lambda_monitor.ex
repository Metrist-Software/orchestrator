defmodule Orchestrator.LambdaMonitor do
  @moduledoc """
  Process to control a lambda monitor.
  """
  use GenServer
  require Logger

  defmodule State do
    defstruct [:config, :task, :overtime]
  end

  # A long, long time ago. Epoch of the modified Julian Date
  @never "1858-11-07 00:00:00"

  def start_link(opts) do
    config = Keyword.get(opts, :config)
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, config, name: name)
  end

  @impl true
  def init(config) do
    Logger.info("Initialize lambda monitor with #{inspect config}")
    schedule_initially(config)
    {:ok, %State{config: config}}
  end

  @impl true
  def handle_info(:run, state) do
    Logger.info("Asked to run #{inspect state}")
    if state.task == nil do
      Logger.info("Running #{inspect state.config}")
      Process.send_after(self(), :run, state.config.intervalSecs * 1_000)
      task = invoke(state.config)
      Process.send_after(self(), :check_completion, 1_000)
      {:noreply, %State{state | task: task, overtime: false}}
    else
      Logger.info("Skipping run, marking us in overtime")
      {:noreply, %State{state | overtime: true}}
    end
  end

  @impl true
  def handle_info(:check_completion, state) do
    # The timing is here unimportant, we can poll every ms if we want but let's not flood the logs
    case Task.yield(state.task, 5_000) do
      {:ok, result} ->
        Logger.info("Task complete for #{inspect state} with result #{inspect result}")
        {:noreply, %State{state | task: nil, overtime: false}}
      {:exit, reason} ->
        Logger.info("Task exited (should not happen) for #{inspect state}, reason: #{inspect reason}")
      nil ->
        Logger.debug("Task still running for #{inspect state}")
        Process.send_after(self(), :check_completion, 1_000)
    end
  end

  @impl true
  def handle_info({:config_change, new_config}, state) do
    # We simply adopt the new config; the next run will then use the new data for scheduling.
    {:noreply, %State{state | config: new_config}}
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
  defp invoke(config) do
    name = lambda_function_name(config)
    req = ExAws.Lambda.invoke(name, %{}, %{}, invocation_type: :request_response)
    # We spawn this as a task, so that we can keep receiving messages and do things like handle timeouts eventually.
    Task.async(fn -> ExAws.request(req) end)
  end

  defp lambda_function_name(%{functionName: function_name}) when not is_nil(function_name), do: lambda_function_name(function_name)
  defp lambda_function_name(%{monitorName: monitor_name}), do: lambda_function_name(monitor_name)
  defp lambda_function_name(name) when is_binary(name), do: "monitor-#{name}-#{env()}-{#name}Monitor"

  defp env, do: System.get_env("ENVIRONMENT_TAG", "local-development")
 end
