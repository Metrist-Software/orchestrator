defmodule Orchestrator.Configuration do
  @moduledoc """
  Code to handle monitor configurations and operations on it. Monitor configurations have the following shape:

  ```
  {
  "monitors": [
    {
      "extra_config": null,
      "interval_secs": 120,
      "last_run_time": null,
      "monitor_logical_name": "testsignal",
      "run_spec": null,
      "steps": []
    },
    {
      "extra_config": {
        "ApiToken": "<secret api token>",
        "Url": "https://canmon.jfrog.io/artifactory/example-repo-local/"
      },
      "interval_secs": 120,
      "last_run_time": "2021-07-19T15:50:01.638237",
      "monitor_logical_name": "artifactory",
      "run_spec": null,
      "steps": [
        {
          "check_logical_name": "UploadArtifact"
        },
        {
          "check_logical_name": "DownloadArtifact"
        },
        {
          "check_logical_name": "DeleteArtifact"
        }
      ]
    },
    {
      "extra_config": {
        "ApiToken": "<secret api token>",
        "StoreId": "<secret store id>"
      },
      "interval_secs": 120,
      "last_run_time": null,
      "monitor_logical_name": "moneris",
      "run_spec": null,
      "steps": [
        {
          "check_logical_name": "TestPurchase"
        },
        {
          "check_logical_name": "TestRefund"
        }
      ]
    }
  ]
  }
  ```

  All we need to do is run the checks :)
  """

  @doc """
  Given a new and old config, pick out the relevant changes and return a list of deltas. Deltas are basically
  commands to delete, add, or update monitors.
  """
  def diff_config(new_config, old_config) do
    %{
      add: find_added(new_config, old_config),
      delete: find_deleted(new_config, old_config),
      change: find_changed(new_config, old_config)
    }
  end

  defp find_added(new_config, old_config) do
    new_list = Map.get(new_config, :monitors, [])
    old_list = Map.get(old_config, :monitors, [])
    Enum.filter(new_list, fn cfg -> find_by_name(old_list, cfg.monitor_logical_name) == nil end)
  end

  defp find_deleted(new_config, old_config) do
    new_list = Map.get(new_config, :monitors, [])
    old_list = Map.get(old_config, :monitors, [])
    Enum.filter(old_list, fn cfg -> find_by_name(new_list, cfg.monitor_logical_name) == nil end)
  end

  defp find_changed(new_config, old_config) do
    new_list = Map.get(new_config, :monitors, [])
    old_list = Map.get(old_config, :monitors, [])
    Enum.filter(old_list, fn cfg ->
      case find_by_name(new_list, cfg.monitor_logical_name) do
        nil -> false
        # TODO: probably filter out last run time and then change on _everything_
        new_cfg -> new_cfg.interval_secs != cfg.interval_secs
      end
    end)
  end

  defp find_by_name(list, monitor_logical_name) do
    Enum.find(list, fn elem -> monitor_logical_name == elem.monitor_logical_name end)
  end

  @doc """
  Translate all the values that are present in the configurations. This accepts a single monitor configuration,
  because fetching secrets, etcetera, may be an expensive operation so we only want to call it when we are
  starting a monitor.
  """
  def translate_config(monitor_config) do
    Map.put(monitor_config, :extra_config,
      monitor_config.extra_config
      |> Enum.map(fn {k, v} -> {k, translate_value(v)} end)
      |> Map.new())
  end


  @doc """
  We have three kinds of values that can be in the monitor's "extra config":

  * A straight value
  * A pointer to a secrets source secret, initiated by `@secret@:`
  * A reference to an environment variable, initiated by `@env@:`

  In the latter two cases, if the translation cannot be made, the whole value is returned. This protects against the
  case where some other system requires the same format as we use.
  """
  def translate_value(v = <<"@secret@:", name::binary>>) do
    Orchestrator.Application.secrets_source().fetch(name) || v
  end
  def translate_value(v = <<"@env@:", name::binary>>) do
    System.get_env(name, v)
  end
  def translate_value(straight), do: straight

end
