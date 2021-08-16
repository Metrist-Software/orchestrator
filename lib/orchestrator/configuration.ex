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

  A monitor is uniquely identified by the tuple `{monitor_logical_name, check_logical_names}`, the latter being the
  logical names of the steps configured for that monitor configuration. This way, we can have different things running
  for different parts of a logical "monitor"; an example is the Zoom monitor, where one step (GetUsers) uses a regular
  C# API, while another step (JoinCall) is run through NodeJS essentially running a browser test.
  """

  require Logger

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
    Enum.filter(new_list, fn cfg -> find_by_unique_key(old_list, cfg) == nil end)
  end

  defp find_deleted(new_config, old_config) do
    new_list = Map.get(new_config, :monitors, [])
    old_list = Map.get(old_config, :monitors, [])
    Enum.filter(old_list, fn cfg -> find_by_unique_key(new_list, cfg) == nil end)
  end

  defp find_changed(new_config, old_config) do
    new_list = Map.get(new_config, :monitors, [])
    old_list = Map.get(old_config, :monitors, [])

    Enum.filter(old_list, fn cfg ->
      case find_by_unique_key(new_list, cfg) do
        nil -> false
        new_cfg ->
          # can't just compare maps as last_run_time is in there and changes on every run
          has_time_interval_changes?(new_cfg, cfg)
          || has_config_changes?(new_cfg, cfg)
          || has_run_spec_changes?(new_cfg, cfg)
      end
    end)
  end

  defp has_time_interval_changes?(new_monitor_cfg, old_monitor_cfg), do: new_monitor_cfg.interval_secs != old_monitor_cfg.interval_secs
  # extra_config are maps so !== is safe which delegates to Kernel.!==/2 where http://erlang.org/doc/reference_manual/expressions.html#term-comparisons states
  # Maps are ordered by size, two maps with the same size are compared by keys in ascending term order and then by values in key order.
  defp has_config_changes?(new_monitor_cfg, old_monitor_cfg), do: Map.get(new_monitor_cfg, :extra_config, %{}) !== Map.get(old_monitor_cfg, :extra_config, %{})
  defp has_run_spec_changes?(new_monitor_cfg, old_monitor_cfg), do: Map.get(new_monitor_cfg, :run_spec, nil) !== Map.get(old_monitor_cfg, :run_spec, nil)

  defp find_by_unique_key(list, config) do
    key = unique_key(config)
    Enum.find(list, fn elem -> key == unique_key(elem) end)
  end

  defp unique_key(config) do
    steps = config
    |> Map.get(:steps, [])
    |> Enum.map(fn step -> step.check_logical_name end)
    {config.monitor_logical_name, steps}
  end

  @doc """
  Translate all the values that are present in the configurations. This accepts a single monitor configuration,
  because fetching secrets, etcetera, may be an expensive operation so we only want to call it when we are
  starting a monitor.
  """
  def translate_config(monitor_config) do
    monitor_config
    |> Map.put(
      :extra_config,
      (monitor_config.extra_config || %{})
      |> Enum.map(fn {k, v} -> {k, translate_value(v)} end)
      |> Map.new()
    )
    |> Map.put(
      :run_spec,
      maybe_override_run_spec(monitor_config.run_spec)
    )
  end

  # This is mostly for temporary overrides during migrations.
  # TODO remove backend code that sets this to awslambda in agent_controller.
  defp maybe_override_run_spec(%{name: "zoomclient"}), do: %{name: "zoomclient", run_type: "exe"}
  defp maybe_override_run_spec(run_spec), do: run_spec

  @doc """
  We have three kinds of values that can be in the monitor's "extra config":

  * A straight value
  * A pointer to a secrets source secret, initiated by `@secret@:`
  * A interpolated string using the environment, initiated by `@env@:`

  The latter two options are recursive, so you can use the environment to form a secret name and then look that up.

  Environment interpolation is simple: only "${WORD}" is supported.
  """
  def translate_value(<<"@secret@:", name::binary>>) do
    case Orchestrator.Application.secrets_source().fetch(name) do
      nil -> "<<ERROR: secret #{name} not found>>"
      other -> translate_value(other)
    end
  end

  def translate_value(<<"@env@:", value::binary>>) do
    String.replace(value, ~r/\$\{([A-Za-z_]+)\}/, fn match ->
      match
      |> String.slice(2, String.length(match) - 3)
      |> System.get_env(
        "<<ERROR: could not expand \"#{match}\", environment variable not found>>"
      )
    end)
    |> translate_value()
  end

  def translate_value(straight), do: straight
end
