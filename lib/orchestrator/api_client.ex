defmodule Orchestrator.APIClient do
  require Logger

  def get_config(instance) do
    {url, headers} = base_url_and_headers()

    {:ok, %HTTPoison.Response{body: body}} =
      HTTPoison.get("#{url}/run-config/#{instance}", headers)
    Jason.decode!(body, keys: :atoms)
    |> IO.inspect(label: "Config for instance #{instance}")
  end

  def write_telemetry(monitor_logical_name, check_logical_name, value) do
    Logger.error("Unimplemented: write_telemetry(#{monitor_logical_name}, #{check_logical_name}, #{value})")
  end

  def write_error(monitor_logical_name, check_logical_name, message) do
    Logger.error("Unimplemented: write_error(#{monitor_logical_name}, #{check_logical_name}, #{message})")
  end


  defp base_url_and_headers do
    host = System.get_env("CANARY_API_HOST", "app.canarymonitor.com")

    transport =
      if String.starts_with?(host, ["localhost", "172."]),
        do: "http",
        else: "https"

    api_token = Application.get_env(:orchestrator, :api_token)

    {"#{transport}://#{host}/api/agent", [{"Authorization", "Bearer #{api_token}"}]}
  end
end
