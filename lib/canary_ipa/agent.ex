defmodule CanaryIPA.Agent do
  @moduledoc """
  Canary In-Process Agent for the BEAM ecosystem (Erlang, Elixir). This agent will forward timings of intercepted
  calls to the Canary Monitoring Agent for further processing.

  Interception is currently only implemented for Hackney, which comes with a tracing library. This means that libraries
  that use Hackney, like HTTPoison, will automatically work.

  To use the agent, simply add this module to your application's supervision tree.
  """
  require Logger
  use GenServer

  require Record

  Record.defrecord(
    :hackney_url,
    Record.extract(:hackney_url, from: "deps/hackney/include/hackney_lib.hrl")
  )

  defmodule State do
    defstruct [:socket, :host, :port, :current_requests_by_pid]
  end

  def start_link(args, name \\ __MODULE__) do
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def init(opts) do
    host = Keyword.get(opts, :host, {127, 0, 0, 1})
    port = Keyword.get(opts, :port, 51712)
    {:ok, socket} = :gen_udp.open(0)
    enable_tracing()
    {:ok, %State{socket: socket, host: host, port: port, current_requests_by_pid: %{}}}
  end

  def handle_cast({:trace, trace}, state) do
    state =
      case trace do
        {:trace_ts, source_pid, :call, {:hackney_trace, :report_event, event}, ts} ->
          process_event(event, ts, source_pid, state)

        other ->
          Logger.debug("Ignoring unknown trace message: #{inspect(other)}")
          state
      end

    {:noreply, state}
  end

  defp process_event([_level, 'request', :hackney, opts], ts, source_pid, state) do
    with body <- Keyword.get(opts, :body, "{}"),
         {:ok, decoded} <- Jason.decode(body),
         %{"check_logical_name" => "SendTelemetry", "monitor_logical_name" => "canary"} <- decoded do
      Logger.debug("Refusing to enter endless loop on telemetry send request: #{inspect opts}")
      %State{state |
             current_requests_by_pid: Map.put(state.current_requests_by_pid, source_pid, :ignore)}
    else
      _ ->
        method = Keyword.get(opts, :method)
        url = Keyword.get(opts, :url)
        host = hackney_url(url, :host)
        path = hackney_url(url, :path)
        %State{state |
               current_requests_by_pid: Map.put(state.current_requests_by_pid, source_pid, {method, host, path, ts})}
    end
  end

  defp process_event([_level, 'got response', :hackney, _opts], ts, source_pid, state) do
    case Map.get(state.current_requests_by_pid, source_pid) do
      nil ->
        Logger.warn("Cannot find process #{inspect source_pid} that started request, ignoring")
        Logger.debug("Current state: #{inspect state}")
        state
      :ignore ->
        Logger.debug("Ignoring response on suppressed telemetry request")
        %State{state |
              current_requests_by_pid: Map.delete(state.current_requests_by_pid, source_pid)}
      {method, host, path, start_ts} ->
        dt = delta_time(ts, start_ts)
        send_data(method, host, path, dt, state)
        %State{state |
              current_requests_by_pid: Map.delete(state.current_requests_by_pid, source_pid)}
    end
  end
  defp process_event(_other, _ts, _source_pid, state) do
    state
  end

  defp send_data(method, host, path, dt, state) do
    method = String.upcase("#{method}")
    :gen_udp.send(state.socket, state.host, state.port, "0 #{method} #{host} #{path} #{dt}")
  end

  defp delta_time(stop, start) do
    delta_secs = ts_to_float(stop) - ts_to_float(start)
    _delta_millisecs = delta_secs * 1_000
  end
  defp ts_to_float({mega, secs, micro}), do: (mega * 1_000_000 + secs + micro / 1_000_000)

  defp enable_tracing do
    :hackney_trace.enable(:max, {&handle_trace/2, self()})
  end

  defp handle_trace(trace, pid) do
    GenServer.cast(pid, {:trace, trace})
    pid
  end
end
