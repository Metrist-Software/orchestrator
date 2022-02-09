defmodule Orchestrator.Application do
  use Application
  require Logger

  @known_secrets_managers %{
    "aws" => Orchestrator.AWSSecretsManager
  }

  @impl true
  def start(_type, _config) do
    print_header()

    ll_config = System.get_env("CANARY_LOGGING_LEVEL", "Info")
    set_logging(String.downcase(ll_config))
    #  Monitors can have very long logging outputs and truncating them throws awa
    #  potentially important information.
    Logger.configure(truncate: :infinity)
    Logger.configure_backend(:console, metadata: [:monitor, :os_pid])

    configure_configs()

    rg_string = System.get_env("CANARY_RUN_GROUPS", "")
    run_groups = parse_run_groups(rg_string)

    config_fetch_fun = fn -> Orchestrator.APIClient.get_config(instance(), run_groups) end

    configure_api_token()
    configure_slack_reporter()

    configure_temp_dir()

    children = [
      Orchestrator.HostTelemetry,
      CanaryIPA.Agent,
      {Orchestrator.ConfigFetcher, [config_fetch_fun: config_fetch_fun]},
      Orchestrator.MonitorSupervisor,
      Orchestrator.IPAServer
    ]
    |> filter_children()
    opts = [strategy: :one_for_one, name: Orchestrator.Supervisor, max_restarts: 5]
    Supervisor.start_link(children, opts)
  end

  def instance, do: System.get_env("CANARY_INSTANCE_ID", "fake-dev-instance")

  def do_cleanup?, do: System.get_env("CANARY_CLEANUP_ENABLED") != nil

  # TODO set default invocation style back to rundll
  def invocation_style, do: System.get_env("CANARY_INVOCATION_STYLE", "aws_lambda")

  def cma_config, do: System.get_env("CANARY_CMA_CONFIG")

  def preview_mode?, do: System.get_env("CANARY_PREVIEW_MODE") != nil

  def secrets_source do
    env = System.get_env("CANARY_SECRETS_SOURCE")
    Map.get(@known_secrets_managers, env, Orchestrator.AWSSecretsManager)
  end

  def aws_region, do: System.get_env("AWS_REGION", "fake-dev-region")

  def api_token, do: Application.get_env(:orchestrator, :api_token)

  def slack_api_token, do: Application.get_env(:slack, :api_token)

  def ipa_loopback_only?, do: Application.get_env(:orchestrator, :ipa_loopback_only)

  defp configure_configs(), do: Orchestrator.Configuration.init()

  defp parse_run_groups(""), do: []
  defp parse_run_groups(string) do
    String.split(string, ",")
  end

  def set_monitor_metadata(monitor_config) do
    step_names =
      monitor_config.steps
      |> Enum.map(&(&1.check_logical_name))
      |> Enum.join(",")
    meta = "#{monitor_config.monitor_logical_name}(#{step_names})"
    Logger.metadata(monitor: meta)
  end
  def set_monitor_metadata(monitor_logical_name, steps) do
    set_monitor_metadata(%{monitor_logical_name: monitor_logical_name, steps: steps})
  end

  defp set_logging("all"), do: Logger.configure(level: :debug)
  defp set_logging("none"), do: Logger.configure(level: :none)

  defp set_logging("debug"), do: Logger.configure(level: :debug)
  defp set_logging("info"), do: Logger.configure(level: :info)
  defp set_logging("information"), do: Logger.configure(level: :info)  # For C# compat
  defp set_logging("notice"), do: Logger.configure(level: :notice)
  defp set_logging("warning"), do: Logger.configure(level: :warning)
  defp set_logging("error"), do: Logger.configure(level: :error)
  defp set_logging("critical"), do: Logger.configure(level: :critical)
  defp set_logging("alert"), do: Logger.configure(level: :alert)
  defp set_logging("emergency"), do: Logger.configure(level: :emergency)

  # We overwrite this when starting monitors, so stash it at startup.
  defp configure_temp_dir(), do: Application.put_env(:orchestrator, :temp_dir, System.tmp_dir())
  def temp_dir(), do: Application.get_env(:orchestrator, :temp_dir, System.tmp_dir())

if Mix.env() == :test do
  # For now, the simplest way to make tests just do tests, not configure/start anything.
  defp filter_children(_children), do: []
  defp configure_api_token, do: :ok
  defp configure_slack_reporter, do: :ok
else
  defp filter_children(children), do: children
  defp configure_api_token do
    token =
      case System.get_env("CANARY_API_TOKEN") do
        nil ->
          "fake-token-for-dev"

        token ->
          Orchestrator.Configuration.translate_value(token)
      end

    Application.put_env(:orchestrator, :api_token, token)
  end
  defp configure_slack_reporter do
    token = System.get_env("SLACK_API_TOKEN")
    |> Orchestrator.Configuration.translate_value()
    Application.put_env(:slack, :api_token, token)

    channel = System.get_env("SLACK_ALERTING_CHANNEL")
    |> Orchestrator.Configuration.translate_value()
    Application.put_env(:slack, :reporting_channel, channel)
  end
end

  defp print_header() do
    build_txt = Path.join(Application.app_dir(:orchestrator, "priv"), "build.txt")
    build = if File.exists?(build_txt) do
      File.read!(build_txt)
    else
      "(unknown build)"
    end
    IO.puts """
    Canary Monitoring Orchestrator starting.

    Build info:
    ===
    #{build}
    ===
    """
  end
end
