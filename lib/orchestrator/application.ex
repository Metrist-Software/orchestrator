defmodule Orchestrator.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _config) do
    print_header()

    region = System.get_env("AWS_REGION", "fake-dev-region")
    Application.put_env(:orchestrator, :aws_region, region)

    instance = System.get_env("CANARY_INSTANCE_ID", "fake-dev-instance")
    Application.put_env(:orchestrator, :instance, instance)

    rg_string = System.get_env("CANARY_RUN_GROUPS", "")
    run_groups = parse_run_groups(rg_string)

    cl_string = System.get_env("CANARY_INVOCATION_STYLE", "false")
    invocation_style = parse_bool(cl_string)
    Application.put_env(:orchestrator, :invocation_style, invocation_style)

    cl_string = System.get_env("CANARY_CLEANUP_ENABLED", "false")
    cleanup_enabled = parse_bool(cl_string)
    Application.put_env(:orchestrator, :cleanup_enabled, cleanup_enabled)

    ss_string = System.get_env("CANARY_SECRETS_SOURCE")
    secrets_source = Map.get(%{"aws" => Orchestrator.AWSSecretsManager}, ss_string, Orchestrator.AWSSecretsManager)
    Application.put_env(:orchestrator, :secrets_source, secrets_source)

    config_fetch_fun = fn -> Orchestrator.APIClient.get_config(instance, run_groups) end

    configure_api_token()

    children = [
      {Orchestrator.ConfigFetcher, [config_fetch_fun: config_fetch_fun]},
      Orchestrator.MonitorSupervisor
    ]
    |> filter_children()
    opts = [strategy: :one_for_one, name: Orchestrator.Supervisor, max_restarts: 5]
    Supervisor.start_link(children, opts)
  end


  def instance, do: Application.get_env(:orchestrator, :instance)
  def secrets_source, do: Application.get_env(:orchestrator, :secrets_source)
  def do_cleanup?, do: Application.get_env(:orchestrator, :cleanup_enabled)
  def invocation_style, do: Application.get_env(:orchestrator, :invocation_style)

  defp parse_run_groups(""), do: []
  defp parse_run_groups(string) do
    String.split(string, ",")
  end

  defp parse_bool(s), do: do_parse_bool(String.downcase(s))
  defp do_parse_bool("true"), do: true
  defp do_parse_bool("false"), do: false
  defp do_parse_bool("1"), do: true
  defp do_parse_bool("0"), do: false
  defp do_parse_bool(_), do: false # Safe default.

if Mix.env() == :test do
  # For now, the simplest way to make tests just do tests, not configure/start anything.
  defp filter_children(_children), do: []
  defp configure_api_token, do: :ok
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
