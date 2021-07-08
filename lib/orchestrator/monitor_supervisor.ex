defmodule Orchestrator.MonitorSupervisor do
  @moduledoc """
  Dynamic supervisor for monitor orchestration processes.

  """
  use DynamicSupervisor
  require Logger

  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)
    {:ok, _} = Registry.start_link(keys: :unique, name: reg_name(name))
    DynamicSupervisor.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp reg_name(name), do: String.to_atom("#{name}.Registry")

  def process_deltas(supervisor_name, deltas) do
    stop_deleted(supervisor_name, deltas.delete)
    start_added(supervisor_name, deltas.add)
    update_changed(supervisor_name, deltas.change)
  end

  defp stop_deleted(_supervisor_name, monitor_configs) do
    IO.inspect(monitor_configs, label: "Stop deleted")
  end

  defp start_added(supervisor_name, monitor_configs) do
    Enum.map(monitor_configs, fn {id, monitor_config} ->
      name = {:via, Registry, {reg_name(supervisor_name), id}}
      case DynamicSupervisor.start_child(supervisor_name, {Orchestrator.LambdaMonitor, [config: monitor_config, name: name]}) do
        {:error, message} ->
          Logger.error("Could not start child #{id} with config #{inspect monitor_config}, error: #{inspect message}")
        {:ok, pid} ->
          Logger.info("Started child #{id} with config #{inspect monitor_config} as #{inspect pid}")
      end
    end)
  end

  defp update_changed(_supervisor_name, monitor_configs) do
    IO.inspect(monitor_configs, label: "Update changed")
  end

end
