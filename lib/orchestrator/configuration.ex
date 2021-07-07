defmodule Orchestrator.Configuration do
  @moduledoc """
  Code to handle monitor configurations and operations on it.
  """

  @doc """
  Given a new and old config, pick out the relevant changes and return a list of deltas. Deltas are basically
  commands to delete, add, or update monitors.
  """
  def diff_config(new_config, old_config) do
    %{add: find_added(new_config, old_config),
      delete: find_deleted(new_config, old_config),
      change: find_changed(new_config, old_config)}
  end

  defp find_added(new_config, old_config) do
    new_config
    |> Enum.filter(fn {key, _cfg} -> !Map.has_key?(old_config, key) end)
    |> Map.new()
  end

  defp find_deleted(new_config, old_config) do
    old_config
    |> Enum.filter(fn {key, _cfg} -> !Map.has_key?(new_config, key) end)
    |> Map.new()
  end

  defp find_changed(new_config, old_config) do
    new_config
    |> Enum.filter(fn {key, cfg} ->
      case Map.get(old_config, key) do
        nil -> false
        oc -> oc.intervalSecs != cfg.intervalSecs
      end
    end)
    |> Map.new
  end
end
