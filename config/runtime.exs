import Config

if config_env() == :prod do
  config :orchestrator,
    enable_host_telemetry?:
      System.get_env("METRIST_ENABLE_HOST_TELEMETRY", "true") |> String.to_existing_atom(),
    api_token: Orchestrator.Application.translate_config_from_env("CANARY_API_TOKEN"),
    slack_api_token: Orchestrator.Application.translate_config_from_env("SLACK_API_TOKEN"),
    slack_reporting_channel: Orchestrator.Application.translate_config_from_env("SLACK_ALERTING_CHANNEL")
end
