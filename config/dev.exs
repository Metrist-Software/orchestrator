import Config

config :orchestrator,
  enable_host_telemetry?:
    System.get_env("METRIST_ENABLE_HOST_TELEMETRY", "false") |> String.to_existing_atom(),
  api_token: System.get_env("METRIST_API_TOKEN"),
  slack_api_token: System.get_env("SLACK_API_TOKEN"),
  slack_reporting_channel: System.get_env("SLACK_ALERTING_CHANNEL")

