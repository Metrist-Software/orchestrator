defmodule Orchestrator.APIClient do
  require Logger
  alias Orchestrator.MetristAPI

  @type metadata_value :: String.t() | number()
  @type metadata :: %{String.t() => metadata_value()}

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

    {:ok, %HTTPoison.Response{body: config}} = MetristAPI.get("agent/run-config/#{instance}/#{qs}")

    config
  end

  @spec write_telemetry(String.t(), String.t(), float(), [metadata: metadata()])  :: {:ok, pid}
  def write_telemetry(monitor_logical_name, check_logical_name, value, opts \\ []) do
    post_with_retries("agent/telemetry", %{
      monitor_logical_name: monitor_logical_name,
      instance_name: Orchestrator.Application.instance(),
      check_logical_name: check_logical_name,
      value: value,
      metadata: opts[:metadata] || %{},
    })
  end

  @type write_error_opts :: [metadata: metadata(), blocked_steps: [binary()]]
  @spec write_error(String.t(), String.t(), String.t(), write_error_opts()) :: {:ok, pid}
  def write_error(monitor_logical_name, check_logical_name, message, opts \\ []) do
    post_with_retries("agent/error", %{
      monitor_logical_name: monitor_logical_name,
      instance_name: Orchestrator.Application.instance(),
      check_logical_name: check_logical_name,
      message: message,
      time: NaiveDateTime.utc_now(),
      metadata: opts[:metadata] || %{},
      blocked_steps: opts[:blocked_steps] ||  []
    })
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
      200 -> body
      _ -> nil
    end
  end

  @backoff [5000, 2500, 500, 100]

  defp post_with_retries(path, msg) do
    headers = [{"Content-Type", "application/json"}]
    msg = Jason.encode!(msg)

    Task.start_link(fn ->
      do_post_with_retries(path, headers, msg, length(@backoff))
    end)
  end

  defp do_post_with_retries(url, headers, msg, retries) do
    # TODO This is quite primitive for now. We probably should queue this up to a genserver, blablabla. Genserver
    # can then also start batching messages.

    case MetristAPI.post(url, msg, headers) do
      {:ok, %HTTPoison.Response{status_code: status_code}} ->
        case div(status_code, 100) do
          2 ->
            :ok

          4 ->
            Logger.error("Got #{status_code} posting #{url}/#{msg}, not retrying")
            :error

          5 ->
            if retries > 0 do
              sleep = Enum.at(@backoff, retries - 1)
              # Always toss jitter in your backoff, it's much better
              sleep = sleep - div(sleep, 4) + :rand.uniform(div(sleep, 2))
              Logger.info("Got #{status_code} posting #{url}/#{msg}, retrying after #{sleep}ms")
              Process.sleep(sleep)
              do_post_with_retries(url, headers, msg, retries - 1)
            else
              Logger.error(
                "Got #{status_code} posting #{url}/#{msg} after max retries, giving up"
              )

              :error
            end
        end

      {:error, error} ->
        if retries > 0 do
          sleep = Enum.at(@backoff, retries - 1)
          # Always toss jitter in your backoff, it's much better
          sleep = sleep - div(sleep, 4) + :rand.uniform(div(sleep, 2))
          Logger.info("Got #{inspect error} posting #{url}/#{msg}, retrying after #{sleep}ms")
          Process.sleep(sleep)
          do_post_with_retries(url, headers, msg, retries - 1)
        else
          Logger.error("Got #{inspect error} posting #{url}/#{msg} after max retries, giving up")
          :error
        end
    end
  end
end
