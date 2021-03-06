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
      id = Orchestrator.Configuration.unique_key(monitor_config)
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
      id = Orchestrator.Configuration.unique_key(monitor_config)
      name = child_name(supervisor_name, id)
      # config_id is passed so that it can be retrieved from the config cache ETS table as it is started.
      # This way if a config changes it won't restart with the old one
      case DynamicSupervisor.start_child(supervisor_name, {Orchestrator.MonitorScheduler, [name: name, config_id: id]}) do
        {:ok, pid} ->
          Logger.info("Started child #{inspect id} with config #{inspect redact(monitor_config)} as #{inspect pid}")
        {:error, message} ->
          Logger.error("Could not start child #{inspect id} with config #{inspect redact(monitor_config)}, error: #{inspect message}")
      end
    end)
  end

  defp update_changed(supervisor_name, monitor_configs) do
    Enum.map(monitor_configs, fn monitor_config ->
      name = child_name(supervisor_name, Orchestrator.Configuration.unique_key(monitor_config))
      monitor_config = Orchestrator.Configuration.translate_config(monitor_config)
      Logger.info("Sending config change signal to child for #{inspect monitor_config}")
      GenServer.cast(name, {:config_change, monitor_config})
    end)
  end

  def redact(monitor_config) do
    Map.put(monitor_config, :extra_config, do_redact(monitor_config.extra_config))
  end
  def do_redact(nil), do: nil
  def do_redact(extra_config) do
    extra_config
    |> Enum.map(fn
      {k, nil} ->
        # Yes, this will probably log the same thing more often than once, but better that then never for now.
        Logger.error("Unexpected nil value in extra config under key #{k} found during redaction, monitor may not work!")
        {k, nil}
      {k, e = << "<<ERROR:", _rest::binary>>} ->
        # "<<ERROR: error message>>" is generated during `translate_value/1`, let's keep these in the clear
        {k, e}
      {k, v} ->
        {k, String.replace(v, ~r/(...).+(...)/, "\\1..\\2")}
    end)
    |> Map.new()
  end
end
