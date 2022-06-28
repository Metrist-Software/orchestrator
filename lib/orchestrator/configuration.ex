defmodule Orchestrator.Configuration do
  @moduledoc """
  Code to handle monitor configurations and operations on it. Monitor configurations have the following shape:

  ```
  {
  "monitors": [
    {
      "id": "23846123486712ewnfdvlkjhv",
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
          "check_logical_name": "UploadArtifact",
          "timeout_secs": 90.0,
        },
        {
          "check_logical_name": "DownloadArtifact",
          "timeout_secs": 30.0,
        },
        {
          "check_logical_name": "DeleteArtifact",
          "timeout_secs": 90.0,
        }
      ]
    },
  ]
  }
  ```

  A monitor is uniquely identified by the tuple `{monitor_logical_name, check_logical_names}`, the latter being the
  logical names of the steps configured for that monitor configuration. This way, we can have different things running
  for different parts of a logical "monitor"; an example is the Zoom monitor, where one step (GetUsers) uses a regular
  C# API, while another step (JoinCall) is run through NodeJS essentially running a browser test.
  """

  require Logger

  def init() do
    # Stores configs based on their unique key (logical_name + steps)
    Logger.info("Configuration ETS initialized.")
    :ets.new(__MODULE__, [:set, :public, :named_table, read_concurrency: true])
  end

  @doc """
  Retrieve a config by its unique id. The config is retrieved from the ETS table that
  contains all monitor configurations we know about.
  """
  def get_config(name) do
    case :ets.lookup(__MODULE__, name) do
      [{_name, config}] ->
        # could do this on store but should be fine here
        # (only pulls when it starts a new child)
        translate_config(config)
      _ ->
        nil
    end
  end

  @doc """
  Given an individual monitor config, return its unique key
  """
  def unique_key(monitor_config), do: monitor_config.id

  @doc """
  Given a new and old config, pick out the relevant changes and return a list of deltas. Deltas are basically
  commands to delete, add, or update monitors.

  On calculating the deltas, the ETS table that holds the configuration (and is used by `get_config/`)
  is also updated to reflect the changes. The returned deltas are therefore purely informational,
  no further processing is needed.
  """
  def diff_and_store_config(new_config, old_config) do
    %{
      add: find_added(new_config, old_config),
      delete: find_deleted(new_config, old_config),
      change: find_changed(new_config, old_config)
    }
    |> store_configs
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

    Enum.reduce(old_list, [], fn cfg, acc ->
      case find_by_unique_key(new_list, cfg) do
        nil -> acc
        new_cfg ->
          # last_run_time always changes so compare without it
          # NOTE: If anything in the config structure is added that changes
          # on every run, this has to be updated
          if Map.delete(new_cfg, :last_run_time) !== Map.delete(cfg, :last_run_time) do
            [ new_cfg | acc ]
          else
            acc
          end
      end
    end)
  end

  defp find_by_unique_key(list, config) do
    key = unique_key(config)
    Enum.find(list, fn elem -> key == unique_key(elem) end)
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
      monitor_config
      |> Map.get(:extra_config, %{})
      |> Enum.map(fn {k, v} -> {k, translate_value(v)} end)
      |> Map.new()
    )
    |> Map.put(
      :run_spec,
      maybe_override_run_spec(Map.get(monitor_config, :run_spec, %{}))
    )
  end

  # This is mostly for temporary overrides during migrations.
  # TODO remove backend code that sets this to awslambda in agent_controller.
  defp maybe_override_run_spec(%{name: "zoomclient"}), do: %{name: "zoomclient", run_type: "exe"}
  defp maybe_override_run_spec(%{name: "snowflake"}), do: %{name: "snowflake", run_type: "exe"}
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
    secret_key = name
    |> translate_value()
    |> Orchestrator.Application.secrets_source().fetch()

    case secret_key do
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

  defp store_configs(deltas) do
    Enum.each(deltas.add, fn elem -> :ets.insert(__MODULE__, { unique_key(elem), elem }) end)
    Enum.each(deltas.change, fn elem -> :ets.insert(__MODULE__, { unique_key(elem), elem }) end)
    Enum.each(deltas.delete, fn elem -> :ets.delete(__MODULE__, unique_key(elem)) end )
    deltas
  end
end
