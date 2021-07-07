defmodule Orchestrator.GraphQLConfig do
  @monitors_query """
  query Monitors {
    monitors {
      id
      name
      logicalName
      instances {
        name
        lastReport
        checkLastReports {
          key
          value
        }
      }
    }
  }
  """

  @monitor_configs_query """
  query MonitorConfigurations($runGroups: [ID]) {
    monitorConfigurations(runGroups: $runGroups) {
      id
      monitorName
      checkName
      functionName
      intervalSecs
      extraConfig {
        key
        value
      }
    }
  }
  """

  def get_config(run_groups, instance) do
    monitors = get_monitors()
    configurations = get_monitor_configs(run_groups)

    # We simplify here. The whole somewhat complicated GraphQL thing should be hidden, preferably.
    monitors = monitors.monitors
    |> Enum.map(fn mon ->
      instance = case Enum.filter(mon.instances, fn i -> i.name == instance end) do
                   [i] -> i
                   [] ->
                     IO.puts("Not found #{instance} in #{inspect mon.instances}")
                     nil
      end
      mon = mon
      |> Map.delete(:instances)
      |> Map.put(:instance, instance)
      {mon.id, mon}
    end)
    |> Map.new()

    configurations.monitorConfigurations
    |> Enum.map(fn cfg ->
      cfg = Map.put(cfg, :monitor, Map.get(monitors, cfg.monitorName, %{}))
      {cfg.id, cfg}
    end)
    |> Map.new()
  end

  def get_monitors() do
    query(@monitors_query)
  end

  def get_monitor_configs(run_groups) do
    query(@monitor_configs_query, %{runGroups: run_groups})
  end

  def query(query, vars \\ %{}) do
    {time, data} =
      :timer.tc(fn ->
        case Neuron.query(query, vars) do
          {:ok, %Neuron.Response{body: %{data: data}}} -> data
          {:ok, %Neuron.Response{body: %{errors: errors}}} -> {:error, errors}
        end
      end)

    IO.puts("GraphQL query took #{time}µs")
    data
  end
end
