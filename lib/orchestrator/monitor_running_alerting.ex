defmodule Orchestrator.MonitorRunningAlerting do
  use GenServer

  @moduledoc """
  Tracks the latest runs for all configured monitors and alerts on any that have
  no recent data.

  This will send a POST request to the url configured by the METRIST_MONITOR_RUNNING_ALERT_WEBHOOK_URL
  environment variable, optionally setting a Bearer Authorization header using
  the METRIST_MONITOR_RUNNING_ALERT_WEBHOOK_TOKEN environment variable.

  The request will have the following json body structure:

    {
      "config_id": "config_id",
      "monitor_id": "monitor_id",
      "instance_id": "instance_id",
      "monitor_state": "ok",
      "last_update_time": "2023-01-01T00:00:00.000000"
    }
  """

  @timeout_threshold_seconds 90 * 60

  defmodule State do
    @type config_id :: String.t()
    @type monitor_id :: String.t()
    @type monitor_state :: :ok | :notrunning

    @type t() :: %__MODULE__{
      tracked_monitors: %{optional({config_id, monitor_id}) => {monitor_state, NaiveDateTime.t()}}
    }

    @enforce_keys [:tracked_monitors]
    defstruct tracked_monitors: %{}
  end

  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def track_monitor(%{id: config_id, monitor_logical_name: monitor_id}) do
    GenServer.cast(__MODULE__, {:track_monitor, config_id, monitor_id})
  end

  @spec untrack_monitor(%{:id => any, :monitor_logical_name => any, optional(any) => any}) :: :ok
  def untrack_monitor(%{id: config_id, monitor_logical_name: monitor_id}) do
    GenServer.cast(__MODULE__, {:untrack_monitor, config_id, monitor_id})
  end

  def update_monitor(%{id: config_id, monitor_logical_name: monitor_id}) do
    GenServer.cast(__MODULE__, {:update_monitor, config_id, monitor_id})
  end

  @impl true
  def init(_args) do
    schedule_check()

    {:ok, %State{tracked_monitors: %{}}}
  end

  @impl true
  def handle_cast({:track_monitor, config_id, monitor_id}, state) do
    tracked_monitors = Map.put_new(state.tracked_monitors, {config_id, monitor_id}, {:ok, NaiveDateTime.utc_now()})
    {:noreply, %State{state | tracked_monitors: tracked_monitors} |> IO.inspect()}
  end

  def handle_cast({:untrack_monitor,config_id,  monitor_id}, state) do
    tracked_monitors = Map.delete(state.tracked_monitors, {config_id, monitor_id})
    {:noreply, %State{state | tracked_monitors: tracked_monitors}}
  end

  def handle_cast({:update_monitor, config_id, monitor_id}, state) do
    tracked_monitors = case Map.get(state.tracked_monitors, {config_id, monitor_id}) do
      nil ->
        state.tracked_monitors
      {monitor_state, _last_update_time} ->
        Map.put(state.tracked_monitors, {config_id, monitor_id}, {monitor_state, NaiveDateTime.utc_now()})
    end

    {:noreply, %State{state | tracked_monitors: tracked_monitors}}
  end

  @impl true
  def handle_info(:check_monitors, state) do
    new_tracked_monitors = update_monitor_states(state.tracked_monitors)

    get_changed_monitors(state.tracked_monitors, new_tracked_monitors)
    |> send_alerts()

    schedule_check()

    {:noreply, %State{state | tracked_monitors: new_tracked_monitors}}
  end

  def update_monitor_states(tracked_monitors) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -@timeout_threshold_seconds)

    Enum.map(tracked_monitors, fn {key, {_monitor_state, last_update_time}} ->
      monitor_state = case NaiveDateTime.compare(last_update_time, cutoff) do
        :lt -> :notrunning
        _ -> :ok
      end
      {key, {monitor_state, last_update_time}}
    end)
    |> Map.new()
  end

  def get_changed_monitors(old_tracked_monitors, new_tracked_monitors) do
    Enum.filter(new_tracked_monitors, fn {key, {new_monitor_state, _last_update_time}} ->
      case Map.get(old_tracked_monitors, key) do
        {old_monitor_state, _} when new_monitor_state != old_monitor_state -> true
        _ -> false
      end
    end)
  end

  defp send_alerts(changes) do
    url = Application.get_env(:orchestrator, :monitor_running_alert_webhook_url)
    token = Application.get_env(:orchestrator, :monitor_running_alert_webhook_token)
    instance_id = Application.get_env(:orchestrator, :instance_id)

    headers = if token do
      [
        {"Authorization", "Bearer #{token}"},
        {"content-type", "application/json"}
      ]
    else
      [{"content-type", "application/json"}]
    end

    for {{config_id, monitor_id}, {monitor_state, last_update_time}} <- changes do
      body = %{
        config_id: config_id,
        monitor_id: monitor_id,
        instance_id: instance_id,
        monitor_state: monitor_state,
        last_update_time: NaiveDateTime.to_iso8601(last_update_time)
      }
      |> Jason.encode!()

      HTTPoison.post(url, body, headers)
    end
  end

  defp schedule_check(delay \\ 60_000) do
    Process.send_after(self(), :check_monitors, delay)
  end
end
