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
  @cpu_check_time 1_000

  defmodule State do
    defstruct [:instance, :cpu_samples]
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init(_args) do
    Logger.info("Host telemetry: process starting, sending telemetry every #{@tick_time}ms")
    schedule_cpu_check()
    schedule_tick()
    :cpu_sup.util() # The first call may be garbage according to the manual.
    {:ok, %State{instance: Orchestrator.Application.instance(), cpu_samples: []}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick()
    execute_tick(state)
    {:noreply, %State{ state | cpu_samples: [] }}
  end

  @impl true
  def handle_info(:cpu_check, state) do
    schedule_cpu_check()
    {:noreply, %State{state | cpu_samples: [ cpu_load() | state.cpu_samples ]}}
  end

  defp execute_tick(state) do
    telemetry =
      %{
        disk: disk_usage(),
        cpu: round(Enum.sum(state.cpu_samples) / Enum.count(state.cpu_samples)) ,
        mem: mem_usage(),
        instance: state.instance,
        max_cpu: Enum.max(state.cpu_samples)
      }
    Logger.info("Host telemetry: sending #{inspect telemetry}")
    Orchestrator.APIClient.write_host_telemetry(telemetry)
  end

  defp disk_usage() do
    # We just grab the percentage of the root fs
    {_id, _bytes, percentage} = :disksup.get_disk_data() |> Enum.filter(fn {part, _free, _per} -> part == '/' end) |> hd()
    percentage
  end

  defp cpu_load() do
    # CPU load normalized to an integer percentage
    round(:cpu_sup.util())
  end

  defp mem_usage() do
    # Available is including buffers and cache, but that's probably what we want anyway. It looks like `:available_memory` is
    # not always available so we calculate it by hand.
    m = :memsup.get_system_memory_data()
    available = m[:free_memory] + m[:buffered_memory] + m[:cached_memory]
    used = m[:total_memory] - available
    used_fraction = used / m[:total_memory]
    round(used_fraction * 100)
  end

  defp schedule_tick() do
    Process.send_after(self(), :tick, @tick_time)
  end

  defp schedule_cpu_check() do
    Process.send_after(self(), :cpu_check, @cpu_check_time)
  end
end
