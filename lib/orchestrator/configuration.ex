defmodule Orchestrator.Configuration do
  @moduledoc """
  Code to handle monitor configurations and operations on it. Monitor configurations have the following shape:

  ```
    %{
      checkName: nil,
      extraConfig: [],
      functionName: nil,
      id: "11vpT2iBDbLTDFOz5QhbQLV",
      intervalSecs: 120,
      monitor: %{
        id: "gcal",
        instance: %{
          checkLastReports: [
            %{key: "CreateEvent", value: "2021-07-08T14:25:32.119925"},
            %{key: "DeleteEvent", value: "2021-07-08T14:25:32.119925"},
            %{key: "GetEvent", value: "2021-07-08T14:25:32.119925"}
          ],
          lastReport: "2021-07-08T14:25:32.119925",
          name: "us-east-1"
        },
        logicalName: "gcal",
        name: "Google Calendar"
      },
      monitorName: "gcal"
    }
  ```

  Where `checkName` can either be nil, meaning that a whole scenario is expected to be ran, or a value indicating a single
  check. In this case, `functionName` will be the name of the lambda function to be invoked (instead of something based
  on the monitor name) and the last run time is not the monitor instance's last run, but the corresponding `checkLastReports`
  array last run.

  Note that the above structure is not perfect and just a simple set of transformations, at the moment, from what our
  GraphQL API emits. This needs more work and at some point pinning down in type definitions.
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
