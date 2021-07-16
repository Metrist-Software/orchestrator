defmodule Orchestrator.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _config) do
    print_header()
    # TODO set stuff from run time environment
    # AWS_REGION
    configure_api_token()
    configure_neuron()
    configure_monitors()

    run_groups = Application.get_env(:orchestrator, :run_groups, [])
    instance = System.get_env("AWS_REGION", "fake-dev-region")

    # So you can separate the AWS settings from the "what instance do we want to report as?" settings
    instance = System.get_env("CANARY_INSTANCE_NAME", instance)

    Application.put_env(:orchestrator, :aws_region, instance)

    config_fetch_fun = fn -> Orchestrator.GraphQLConfig.get_config(run_groups, instance) end

    # Transitional, we probably will end up with just the .NET DLL invoker. At some point,
    # this needs to be configurable by monitor but for now it'll allow us to run either
    # as the Lambda-invoking Orchestrator or the DLL-invoking Private Monitor.
    invoker = case System.get_env("CANARY_INVOCATION_STYLE") do
                nil -> Orchestrator.LambdaInvoker
                "lambda" -> Orchestrator.LambdaInvoker
                "rundll" -> Orchestrator.DotNetDLLInvoker
                other -> raise "Unknown invoker #{other} set, cannot continue"
              end
    Application.put_env(:orchestrator, :invoker, invoker)

    children = [
      {Orchestrator.ConfigFetcher, [config_fetch_fun: config_fetch_fun]},
      Orchestrator.MonitorSupervisor
    ]
    opts = [strategy: :one_for_one, name: Orchestrator.Supervisor, max_restarts: 5]
    Supervisor.start_link(children, opts)
  end

  defp configure_api_token do
    token =
      case System.get_env("CANARY_API_TOKEN") do
        nil ->
          case System.get_env("SECRETS_NAMESPACE") do
            nil ->
              "fake-token-for-dev"

            env ->
              get_secret("canary-internal/api-token", env)
              |> Jason.decode!()
              |> Map.get("token")
          end

        token -> token
      end

    Application.put_env(:orchestrator, :api_token, token)
  end


  defp configure_neuron do
    case System.get_env("APP_API_HOSTNAME") do
      nil ->
        Logger.error("APP_API_HOSTNAME not set!")

      host ->
        transport =
        if String.starts_with?(host, ["localhost", "172."]),
          do: "http",
          else: "https"

        api_token = Application.get_env(:orchestrator, :api_token)
        Neuron.Config.set(url: "#{transport}://#{host}/graphql")
        Neuron.Config.set(headers: [Authorization: "Bearer #{api_token}"])
        Neuron.Config.set(parse_options: [keys: :atoms])
        # our API can be slooow... Wait for it :)
        Neuron.Config.set(connection_opts: [recv_timeout: 15_000])
    end
  end

  defp configure_monitors() do
    # Artifactory is currently the only one we run as a private monitor with a separate API key
    copy_secret("artifactory/api-token", "token", "CANARY_ARTIFACTORY_API_TOKEN")
  end

  defp copy_secret(path, field, env_var) do
    secret = get_secret(path) |> Jason.decode!()
    IO.puts("Copy field #{field} to #{env_var}")
    System.put_env(env_var, Map.get(secret, field))
  end

  def get_secret(path) do
    case System.get_env("SECRETS_NAMESPACE") do
      nil ->
        Logger.warning("No SECRETS_NAMESPACE found, not fetching secret #{path}")
        nil
      env ->
        get_secret(path, env)
    end
  end
  defp get_secret(path, namespace) do
    Logger.debug("get_secret(#{path}, #{namespace}) (or #{namespace}#{path})")

    # We may be called in various stages of the life cycle, including really
    # early, so make sure that what ExAws needs is up and running.
    [:ex_aws_secretsmanager, :hackney, :jason]
    |> Enum.map(&Application.ensure_all_started/1)

    {:ok, %{"SecretString" => secret}} =
      "#{namespace}#{path}"
      |> ExAws.SecretsManager.get_secret_value()
      |> do_aws_request()

    secret
  end

  defp do_aws_request(request) do
    region = System.get_env("AWS_REGION") || "us-east-1"
    ExAws.request(request, region: region)
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
