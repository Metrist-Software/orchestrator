defmodule Orchestrator.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _config) do
    # TODO set stuff from run time environment
    # AWS_REGION
    configure_api_token()
    configure_neuron()

    run_groups = Application.get_env(:orchestrator, :run_groups, ["AWS Lambda"])
    config_fetch_fun = fn -> Orchestrator.GraphQLConfig.get_config(run_groups) end

    children = [
      {Orchestrator.ConfigFetcher, [config_fetch_fun: config_fetch_fun]}
    ]
    opts = [strategy: :one_for_one, name: Orchestrator.Supervisor, max_restarts: 5]
    Supervisor.start_link(children, opts)
  end

  defp configure_api_token do
    token =
      case System.get_env("SECRETS_NAMESPACE") do
        nil ->
          "fake-token-for-dev"

        env ->
          get_secret("canary-internal/api-token", env)
          |> Jason.decode!()
          |> Map.get("token")
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
end
