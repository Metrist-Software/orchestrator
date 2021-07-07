defmodule Orchestrator.MonitorSupervisor do
  @moduledoc """
  Dynamic supervisor for monitor orchestration processes.

  """
  use DynamicSupervisor

  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def process_deltas(supervisor_pid, deltas) do
    stop_deleted(supervisor_pid, deltas.delete)
    start_added(supervisor_pid, deltas.add)
    update_changed(supervisor_pid, deltas.change)
  end

  defp stop_deleted(_supervisor_pid, monitor_configs) do
    IO.inspect(monitor_configs, label: "Stop deleted")
  end

  defp start_added(_supervisor_pid, monitor_configs) do
    IO.inspect(monitor_configs, label: "Start added")
  end

  defp update_changed(_supervisor_pid, monitor_configs) do
    IO.inspect(monitor_configs, label: "Update changed")
  end

end
