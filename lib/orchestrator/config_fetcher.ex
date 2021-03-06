defmodule Orchestrator.ConfigFetcher do
  @moduledoc """
  This process fetches the configuration every minute and compares it with the current state. If anything
  changes, it'll forward the diffs to the process that supervises all the monitors so it can make
  adjustments.
  """
  use GenServer
  require Logger

  defmodule State do
    defstruct [:monitor_supervisor_pid, :config_fetch_fun, :current_config]
  end

  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  # Server side

  @impl true
  def init(args) do
    monitor_supervisor_pid = Keyword.get(args, :monitor_supervisor_pid, Orchestrator.MonitorSupervisor)
    config_fetch_fun = Keyword.get(args, :config_fetch_fun, fn ->
      Logger.error("No fetch function defined, returning empty!")
      %{}
    end)
    schedule_fetch(0)
    {:ok, %State{
        monitor_supervisor_pid: monitor_supervisor_pid,
        config_fetch_fun: config_fetch_fun,
        current_config: %{}
     }}
  end

  @impl true
  def handle_info(:fetch, state) do
    Logger.info("Pulling configs...")
    state = run_fetch(state)
    schedule_fetch()
    {:noreply, state}
  end

  defp run_fetch(state) do
    try do
      new_config = state.config_fetch_fun.()
      deltas = Orchestrator.Configuration.diff_and_store_config(new_config, state.current_config)
      Logger.info("- deltas: add=#{length(deltas.add)} delete=#{length(deltas.delete)} change=#{length(deltas.change)}")
      Orchestrator.MonitorSupervisor.process_deltas(state.monitor_supervisor_pid, deltas)
      %State{state | current_config: new_config}
    rescue
      e ->
        Logger.warn("Error pulling configuration, nothing fetched: #{Exception.format(:error, e, __STACKTRACE__)}")
        state
    end
  end

  defp schedule_fetch(delay \\ 60_000) do
    Process.send_after(self(), :fetch, delay)
  end
end
