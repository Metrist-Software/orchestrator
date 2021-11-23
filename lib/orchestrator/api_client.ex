defmodule Orchestrator.APIClient do
  require Logger

  def get_config(instance, run_groups) do
    Logger.info("Fetching config for instance #{instance} and run groups #{inspect run_groups}")
    {url, headers} = base_url_and_headers()

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

    {:ok, %HTTPoison.Response{body: body}} =
      HTTPoison.get("#{url}/run-config/#{instance}#{qs}", headers)

    {:ok, config} = Jason.decode(body, keys: :atoms)

    config
  end

  def write_telemetry(monitor_logical_name, check_logical_name, value) do
    post_with_retries("telemetry", %{
      monitor_logical_name: monitor_logical_name,
      instance_name: Orchestrator.Application.instance(),
      check_logical_name: check_logical_name,
      value: value
    })
  end

  def write_error(monitor_logical_name, check_logical_name, message) do
    post_with_retries("error", %{
      monitor_logical_name: monitor_logical_name,
      instance_name: Orchestrator.Application.instance(),
      check_logical_name: check_logical_name,
      message: message,
      time: NaiveDateTime.utc_now()
    })
  end

  def get_webhook(uid, monitor_logical_name) do
    instance_name = Orchestrator.Application.instance()
    Logger.info("Checking for webhoook with uid #{uid} for monitor #{monitor_logical_name} with instance #{instance_name}")
    {url, headers} = base_webhooks_url_and_headers()

    {:ok, %HTTPoison.Response{status_code: status_code, body: body}} =
      HTTPoison.get("#{url}/#{monitor_logical_name}/#{instance_name}/#{uid}", headers)

    case status_code do
      200 ->
        {:ok, webhook} = Jason.decode(body, keys: :atoms)
        webhook
      _ ->
        nil
    end
  end

  @backoff [5000, 2500, 500, 100]

  defp post_with_retries(path, msg) do
    {url, headers} = base_url_and_headers()
    headers = [{"Content-Type", "application/json"} | headers]
    msg = Jason.encode!(msg)

    Task.start_link(fn ->
      do_post_with_retries("#{url}/#{path}", headers, msg, length(@backoff))
    end)
  end

  defp do_post_with_retries(url, headers, msg, retries) do
    # TODO This is quite primitive for now. We probably should queue this up to a genserver, blablabla. Genserver
    # can then also start batching messages.

    case HTTPoison.post(url, msg, headers) do
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

  defp base_url_and_headers do
    System.get_env("CANARY_API_HOST", "app.metrist.io")
    |> do_get_base_url_and_headers("api/agent")
  end

  defp base_webhooks_url_and_headers do
    case System.get_env("CANARY_WEBHOOK_HOST", nil) do
      nil -> raise "Attempted to access Webhooks API but CANARY_WEBHOOK_HOST was not set!"
      host ->
        host
        |> do_get_base_url_and_headers("api/webhook")
    end
  end

  defp do_get_base_url_and_headers(nil, _), do: raise "Attempt to access Webhooks API but CANARY_WEBHOOK_HOST was not set!"
  defp do_get_base_url_and_headers(host, url) do
    transport =
      if String.starts_with?(host, ["localhost", "172."]),
        do: "http",
        else: "https"

    api_token = Orchestrator.Application.api_token()

    {"#{transport}://#{host}/#{url}", [{"Authorization", "Bearer #{api_token}"}]}
  end
end
