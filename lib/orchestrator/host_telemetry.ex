defmodule Orchestrator.HostTelemetry do
  @moduledoc """
  A simple module that polls some stats from [`:os_mon`](https://www.erlang.org/doc/man/os_mon_app.html) and forwards
  that to the Backend Agent Host Telemetry endpoint. From there we can than ship things off to Grafana. Doing it through
  the backend has two advantages:
  * We can have all Orchestrators send telemetry, regardless of who runs it or where;
  * Grafana by default ingests through Prometheus, that wants to pull events from observed instances which is a bit hard
    to setup; this way we can push

  To keep things simple, we just poll once a minute and just three simple stats about CPU, Disk and Memory. Orchestrator
  load is very predictable and this is mostly to detect longer term leaks in either. All three stats are just integers
  between 0-100, that's plenty of info to figure out whether an orchestrator is healthy.
  """
  use GenServer
  require Logger

  @tick_time 60_000

  defmodule State do
    defstruct [:instance]
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init(_args) do
    schedule_tick()
    :cpu_sup.util() # The first call may be garbage according to the manual.
    {:ok, %State{instance: Orchestrator.Application.instance()}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick()
    execute_tick(state)
    {:noreply, state}
  end

  defp execute_tick(state) do
    telemetry = %{disk: disk_usage(), cpu: cpu_load(), mem: mem_usage(), instance: state.instance}
    Logger.info("Host telemetry: #{inspect telemetry}")
    Orchestrator.APIClient.write_host_telemetry(telemetry)
  end

  defp disk_usage() do
    # We just grab the percentage of the root fs
    {_id, _bytes, percentage} = :disksup.get_disk_data() |> Enum.filter(fn {part, _free, _per} -> part == '/' end) |> hd()
    percentage
  end

  defp cpu_load() do
    # CPU load normalized to an integer percentags
    round(:cpu_sup.util())
  end

  defp mem_usage() do
    m = :memsup.get_system_memory_data()
    used = m[:total_memory] - m[:available_memory]
    used_fraction = used / m[:available_memory]
    round(used_fraction * 100)
  end

  defp schedule_tick() do
    Process.send_after(self(), :tick, @tick_time)
  end
end
