defmodule Orchestrator.LambdaMonitor do
  @moduledoc """
  Process to control a lambda monitor.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    config = Keyword.get(opts, :config)
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, config, name: name)
  end

  @impl true
  def init(config) do
    Logger.info("Initialize lambda monitor with #{inspect config}")
    schedule_initially(config)
    {:ok, config}
  end

  @impl true
  def handle_info(:run, config) do
    Logger.info("Scheduling run of #{inspect config}")
    Process.send_after(self(), :run, config.intervalSecs * 1_000)
    # TODO actual run
    {:noreply, config}
  end

  # Helpers for the first time (when we start) scheduling of a run, based on the
  # last run value of either the monitor or the check we are supposed to run.
  defp schedule_initially(config = %{checkName: nil}) do
    # Schedule a whole monitor
    {:ok, last_run} = config.monitor.instance.lastReport
    |> NaiveDateTime.from_iso8601()
    do_schedule_initially(config, last_run)
  end
  defp schedule_initially(config) do
    # Schedule a single check style monitor
    {:ok, last_run} = config.monitor.instance.checkLastReports
    |> Enum.find(fn clr -> clr.key == config.checkName end)
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
    max(NaiveDateTime.diff(next_run, now), 0)
  end

 end
