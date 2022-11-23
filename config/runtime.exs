import Config

if config_env() == :prod do
  config :orchestrator,
    enable_host_telemetry?:
      System.get_env("METRIST_ENABLE_HOST_TELEMETRY", "false") |> String.to_existing_atom(),
    api_token: Orchestrator.Application.translate_config_from_env("METRIST_API_TOKEN"),
    slack_api_token: Orchestrator.Application.translate_config_from_env("SLACK_API_TOKEN"),
    slack_reporting_channel: Orchestrator.Application.translate_config_from_env("SLACK_ALERTING_CHANNEL")

  if System.get_env("SENTRY_DSN") do
    config :sentry,
      dsn: System.get_env("SENTRY_DSN"),
      environment: System.get_env("METRIST_INSTANCE_ID", "fake-dev-instance")

    config :logger, Sentry.LoggerBackend,
      capture_log_messages: true
  end
end
