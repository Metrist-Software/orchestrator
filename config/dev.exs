import Config

config :orchestrator,
  enable_host_telemetry?:
    System.get_env("METRIST_ENABLE_HOST_TELEMETRY", "false") |> String.to_existing_atom(),
  api_token: System.get_env("METRIST_API_TOKEN"),
  instance_id: System.get_env("METRIST_INSTANCE_ID", "fake-dev-instance"),
  slack_api_token: System.get_env("SLACK_API_TOKEN"),
  slack_reporting_channel: System.get_env("SLACK_ALERTING_CHANNEL"),
  monitor_running_alert_webhook_url: System.get_env("METRIST_MONITOR_RUNNING_ALERT_WEBHOOK_URL"),
  monitor_running_alert_webhook_token: System.get_env("METRIST_MONITOR_RUNNING_ALERT_WEBHOOK_TOKEN")
