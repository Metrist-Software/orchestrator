defmodule Orchestrator.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _config) do
    print_header()

    configure_api_token()
    configure_neuron()

    run_groups = Application.get_env(:orchestrator, :run_groups, [])

    region = System.get_env("AWS_REGION", "fake-dev-region")
    Application.put_env(:orchestrator, :aws_region, region)

    instance = System.get_env("CANARY_INSTANCE_ID", "fake-dev-instance")
    Application.put_env(:orchestrator, :instance, instance)
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
    |> filter_children()
    opts = [strategy: :one_for_one, name: Orchestrator.Supervisor, max_restarts: 5]
    Supervisor.start_link(children, opts)
  end

if Mix.env() == :test do
  # For now, the simplest way to make tests just do tests, not configure/start anything.
  defp filter_children(_children), do: []
  defp configure_api_token, do: :ok
  defp configure_neuron, do: :ok
else
  defp filter_children(children), do: children
  defp configure_api_token do
    token =
      case System.get_env("CANARY_API_TOKEN") do
        nil ->
          case System.get_env("CANARY_API_TOKEN_PATH") do
            nil ->
              "fake-token-for-dev"

            path ->
              token = get_secret(path)
              System.put_env("CANARY_API_TOKEN", token) # TODO remove when children stop reporting themselves
              token
          end

        token -> token
      end

    Application.put_env(:orchestrator, :api_token, token)
  end


  defp configure_neuron do
    host = System.get_env("CANARY_API_HOST", "app.canarymonitor.com")
    transport =
      if String.starts_with?(host, ["localhost", "172."]),
        do: "http",
        else: "https"

    api_token = Application.get_env(:orchestrator, :api_token)
    Neuron.Config.set(url: "#{transport}://#{host}/graphql")
    Neuron.Config.set(headers: [Authorization: "Bearer #{api_token}"])
    Neuron.Config.set(parse_options: [keys: :atoms])
    Neuron.Config.set(connection_opts: [recv_timeout: 15_000])
  end

  # TODO pluggable vault support (k8s, hashicorp, ...)
  defp get_secret(path) do
    Logger.debug("get_secret(#{path})")

    # We may be called in various stages of the life cycle, including really
    # early, so make sure that what ExAws needs is up and running.
    [:ex_aws_secretsmanager, :hackney, :jason]
    |> Enum.map(&Application.ensure_all_started/1)

    parts = String.split(path, ".")
    secret_name = hd(parts)
    {:ok, %{"SecretString" => secret}} =
      secret_name
      |> ExAws.SecretsManager.get_secret_value()
      |> do_aws_request()

    case parts do
      [_path] ->
        secret
      [_path, selector] ->
        secret
        |> Jason.decode!()
        |> Map.get(selector)
    end
    |> IO.inspect(label: "get_secret(#{path})")
  end
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
