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
    Enum.map(monitor_configs, fn monitor_config ->
      id = registry_key(monitor_config)
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
      id = registry_key(monitor_config)
      name = child_name(supervisor_name, id)
      case DynamicSupervisor.start_child(supervisor_name, {Orchestrator.MonitorScheduler, [config: monitor_config, name: name]}) do
        {:ok, pid} ->
          Logger.info("Started child #{inspect id} with config #{inspect redact(monitor_config)} as #{inspect pid}")
        {:error, message} ->
          Logger.error("Could not start child #{inspect id} with config #{inspect redact(monitor_config)}, error: #{inspect message}")
      end
    end)
  end

  defp update_changed(supervisor_name, monitor_configs) do
    Enum.map(monitor_configs, fn monitor_config ->
      name = child_name(supervisor_name, registry_key(monitor_config))
      GenServer.cast(name, {:config_change, monitor_config})
    end)
  end

  def redact(monitor_config) do
    IO.puts("Redact #{inspect monitor_config}")
    Map.put(monitor_config, :extra_config, do_redact(monitor_config.extra_config))
  end
  def do_redact(nil), do: nil
  def do_redact(extra_config) do
    extra_config
    |> Enum.map(fn {k, v} ->
      {k, String.replace(v, ~r/(...).+(...)/, "\\1..\\2")}
    end)
    |> Map.new()
  end

  def registry_key(monitor_config) do
    {monitor_config.monitor_logical_name, Enum.map(monitor_config.steps, fn step -> step.check_logical_name end)}
  end
end
