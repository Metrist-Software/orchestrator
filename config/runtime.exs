import Config

if config_env() == :prod do
  config :orchestrator,
    enable_host_telemetry?:
      System.get_env("METRIST_ENABLE_HOST_TELEMETRY", "false") |> String.to_existing_atom(),
    api_token: Orchestrator.Application.translate_config_from_env("METRIST_API_TOKEN"),
    instance_id: Orchestrator.Application.translate_config_from_env("METRIST_INSTANCE_ID"),
    slack_api_token: Orchestrator.Application.translate_config_from_env("SLACK_API_TOKEN"),
    slack_reporting_channel: Orchestrator.Application.translate_config_from_env("SLACK_ALERTING_CHANNEL")
end

# Erlexec has some protection against accidentally
# running as root, but this complicates how we can
# operate a bit; for example, at CI time we likely
# run in a container wit just root. This tells
# the library that we're fine to run as pretty
# much anything.
config :erlexec,
  user: System.get_env("USER")

# Erlexec also needs SHELL set. Might just as well do it here
# to keep all Erlexec config bits together.
System.put_env("SHELL", System.get_env("SHELL", "/bin/sh"))
