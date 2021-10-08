defmodule Orchestrator.SlackReporter do
  require Logger

  @slack_url "https://slack.com/api/chat.postMessage"

  def send_monitor_error(monitor_logical_name, check_logical_name, message) do
    channel = Application.get_env(:slack, :reporting_channel)

    if is_nil(channel) do
      Logger.warn("Slack Reporter channel not configured. Unable to send message")
      {:error, :channel_not_set}
    else
      body = %{
        channel: channel,
        text: ":x: *Error running #{monitor_logical_name}/#{check_logical_name} in #{Orchestrator.Application.instance()}*\n#{message}"
      }

      case Jason.encode(body) do
        {:ok, json} ->
          send_message(json)

        {:error, _} ->
          Logger.error("Failed to encode slack monitor error: #{message}")
          {:error, :invalid_message}
      end
    end
  end

  def send_message(message) do
    case Application.get_env(:slack, :api_token) do
      nil ->
        Logger.warn("Slack Reporter api token not configured. Unable to send message")
        {:error, :api_token_not_set}

      token ->
        send_message(message, token)
    end
  end

  def send_message(message, token) do
    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json; charset=UTF-8"}
    ]

    HTTPoison.post(@slack_url, message, headers)
  end
end
