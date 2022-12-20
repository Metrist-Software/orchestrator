defmodule Orchestrator.APIClient do
  require Logger
  alias Orchestrator.MetristAPI

  @type metadata_value :: String.t() | number()
  @type metadata :: %{String.t() => metadata_value()}

  @json_content_type_headers [{"Content-Type", "application/json"}]

  def get_config(instance, run_groups) do
    Logger.info("Fetching config for instance #{instance} and run groups #{inspect run_groups}")

    qs =
      case run_groups do
        [] ->
          ""

        groups ->
          gs =
            groups
            |> Enum.map(fn g -> URI.encode_query(%{"rg[]" => g}) end)
            |> Enum.join("&")

          "?" <> gs
      end

    {:ok, %HTTPoison.Response{body: body}} = MetristAPI.get("agent/run-config/#{instance}/#{qs}")

    {:ok, config} = Jason.decode(body, keys: :atoms)
    config
  end

  @spec write_telemetry(String.t(), String.t(), float(), [metadata: metadata()])  :: :ok
  def write_telemetry(monitor_logical_name, check_logical_name, value, opts \\ []) do
    msg = %{
      monitor_logical_name: monitor_logical_name,
      instance_name: Orchestrator.Application.instance(),
      check_logical_name: check_logical_name,
      value: value,
      metadata: opts[:metadata] || %{},
    }
    |> Jason.encode!()

    Orchestrator.RetryQueue.queue(
      Orchestrator.RetryQueue,
      {MetristAPI, :post, ["agent/telemetry", msg, @json_content_type_headers]},
      {__MODULE__, :retry_api_request?},
      {__MODULE__, :delay_retry}
    )
  end

  @type write_error_opts :: [metadata: metadata(), blocked_steps: [binary()]]
  @spec write_error(String.t(), String.t(), String.t(), write_error_opts()) :: :ok
  def write_error(monitor_logical_name, check_logical_name, message, opts \\ []) do
    msg = %{
      monitor_logical_name: monitor_logical_name,
      instance_name: Orchestrator.Application.instance(),
      check_logical_name: check_logical_name,
      message: message,
      time: NaiveDateTime.utc_now(),
      metadata: opts[:metadata] || %{},
      blocked_steps: opts[:blocked_steps] ||  []
    }
    |> Jason.encode!()

    Orchestrator.RetryQueue.queue(
      Orchestrator.RetryQueue,
      {MetristAPI, :post, ["agent/error", msg, @json_content_type_headers]},
      {__MODULE__, :retry_api_request?},
      {__MODULE__, :delay_retry}
    )
  end

  def write_host_telemetry(telemetry) do
    # No retries, error handling, etc - just one-shot and hope for the best.
    headers = [{"Content-Type", "application/json"}]
    msg = Jason.encode!(telemetry)

    MetristAPI.post("agent/host_telemetry", msg, headers)
    :ok
  end

  def get_webhook(uid, monitor_logical_name) do
    instance_name = Orchestrator.Application.instance()
    Logger.info("Checking for webhoook with uid #{uid} for monitor #{monitor_logical_name} with instance #{instance_name}")

    {:ok, %HTTPoison.Response{status_code: status_code, body: body}} = MetristAPI.get("webhook/#{monitor_logical_name}/#{instance_name}/#{uid}")

    case status_code do
      200 ->
        {:ok, webhook} = Jason.decode(body, keys: :atoms)
        webhook
      _ ->
        nil
    end
  end

  def retry_api_request?({:ok, %HTTPoison.Response{status_code: 429, request: request}}) do
    Logger.error("Got status code 429 from #{request.url}. Retrying")
    true
  end
  def retry_api_request?({:ok, %HTTPoison.Response{status_code: status, request: request} }) when status >= 500 do
    Logger.error("Got status code #{status} from #{request.url}. Retrying")
    true
  end
  def retry_api_request?({:error, %HTTPoison.Error{} = reason}) do
    Logger.error("Got an error with reason: #{inspect(reason)}. Retrying.")
    true
  end
  def retry_api_request?(_response), do: false

  def delay_retry({:ok, %{status: 429} = resp} , retry_count) do
    if reset_seconds_str = Enum.into(resp.headers, %{}) |> Map.get("x-ratelimit-reset") do
      {seconds, _} = Integer.parse(reset_seconds_str)
      seconds = seconds + :rand.uniform(seconds)
      Logger.info("Delaying retry for #{seconds} seconds")
      :timer.seconds(seconds)
      |> Process.sleep()
    else
      delay_retry(nil, retry_count) 
    end
  end
  def delay_retry(_response, retry_count) do
    seconds = Integer.pow(2, retry_count)
    seconds = seconds + :rand.uniform(seconds)
    Logger.info("Delaying retry for #{seconds} seconds")
    :timer.seconds(seconds)
    |> Process.sleep()
  end
end
