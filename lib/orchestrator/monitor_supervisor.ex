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

  defp child_name(supervisor_name, id), do: {:via, Registry, {reg_name(supervisor_name), id}}

  def process_deltas(supervisor_name, deltas) do
    stop_deleted(supervisor_name, deltas.delete)
    start_added(supervisor_name, deltas.add)
    update_changed(supervisor_name, deltas.change)
  end

  defp stop_deleted(supervisor_name, monitor_configs) do
    registry = reg_name(supervisor_name)
    Enum.map(monitor_configs, fn {id, monitor_config} ->
      [{pid, _}] = Registry.lookup(registry, id)
      case DynamicSupervisor.terminate_child(supervisor_name, pid) do
        :ok ->
          Logger.info("Terminated child #{id} with config #{inspect monitor_config} running as #{inspect pid}")
        {:error, err} ->
          Logger.error("Could not terminate child #{id} with config #{inspect monitor_config}, error: #{inspect err}")
      end
    end)
  end

  defp start_added(supervisor_name, monitor_configs) do
    Enum.map(monitor_configs, fn {id, monitor_config} ->
      name = child_name(supervisor_name, id)
      invoker = case monitor_config.monitorName do
                  # TODO store this somewhere else than hardcoded here :-)
                  # For our private synthetic monitor
                  "artifactory" -> Orchestrator.DotNetDLLInvoker
                  # For testing.
                  "testsignal" -> Orchestrator.DotNetDLLInvoker
                  _ -> Orchestrator.NilInvoker
                  #_ -> Orchestrator.LambdaInvoker
                end
      case DynamicSupervisor.start_child(supervisor_name, {Orchestrator.MonitorScheduler, [config: monitor_config, name: name, invoker: invoker]}) do
        {:ok, pid} ->
          Logger.info("Started child #{id} with config #{inspect monitor_config} as #{inspect pid}")
        {:error, message} ->
          Logger.error("Could not start child #{id} with config #{inspect monitor_config}, error: #{inspect message}")
      end
    end)
  end

  defp update_changed(supervisor_name, monitor_configs) do
    Enum.map(monitor_configs, fn {id, monitor_config} ->
      name = child_name(supervisor_name, id)
      GenServer.cast(name, {:config_change, monitor_config})
    end)
  end
end
