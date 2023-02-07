defmodule Orchestrator.MonitorSupervisor do
  @moduledoc """
  Dynamic supervisor for monitor orchestration processes.

  """
  use DynamicSupervisor
  require Logger
  alias Orchestrator.Configuration

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
  end

  defp stop_deleted(supervisor_name, monitor_configs) do
    registry = reg_name(supervisor_name)
    Enum.map(monitor_configs, fn monitor_config ->
      id = Configuration.unique_key(monitor_config)
      [{pid, _}] = Registry.lookup(registry, id)
      case DynamicSupervisor.terminate_child(supervisor_name, pid) do
        :ok ->
          Logger.info("Terminated child #{inspect id} with config #{inspect monitor_config} running as #{inspect pid}")
        {:error, err} ->
          Logger.error("Could not terminate child #{inspect id} with config #{inspect monitor_config}, error: #{inspect err}")
      end
    end)
  end

  defp start_added(supervisor_name, monitor_configs) do
    Enum.map(monitor_configs, fn monitor_config ->
      id = Configuration.unique_key(monitor_config)
      name = child_name(supervisor_name, id)
      # config_id is passed so that it can be retrieved from the config cache ETS table as it is started.
      # This way if a config changes it won't restart with the old one
      case DynamicSupervisor.start_child(supervisor_name, {Orchestrator.MonitorScheduler, [name: name, config_id: id]}) do
        {:ok, pid} ->
          Logger.info("Started child #{inspect id} with config #{inspect Configuration.redact(monitor_config)} as #{inspect pid}")
        {:error, message} ->
          Logger.error("Could not start child #{inspect id} with config #{inspect Configuration.redact(monitor_config)}, error: #{inspect message}")
      end
    end)
  end
end
