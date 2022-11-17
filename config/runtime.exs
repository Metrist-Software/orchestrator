import Config

if config_env() == :prod do
  config :orchestrator,
    enable_host_telemetry?:
      System.get_env("METRIST_ENABLE_HOST_TELEMETRY", "false") |> String.to_existing_atom(),
    api_token: Orchestrator.Application.translate_config_from_env("METRIST_API_TOKEN"),
    slack_api_token: Orchestrator.Application.translate_config_from_env("SLACK_API_TOKEN"),
    slack_reporting_channel: Orchestrator.Application.translate_config_from_env("SLACK_ALERTING_CHANNEL")

  config :ex_aws,
    region: System.get_env("AWS_BACKEND_REGION", "us-east-1")
end
