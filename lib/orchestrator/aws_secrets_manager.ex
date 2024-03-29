defmodule Orchestrator.AWSSecretsManager do
  @moduledoc """
  Secrets source using AWS Secrets manager. Secret names are interpreted as having one or two parts:
  if the secret name is one part, the secret is returned. If the secret name has two parts, the
  secret is fetched, JSON decoded, and the field named by the second part is returned.

  The hash sign `#` is used as a separated, because it is not an allowed part of a secret name in AWS SM
  """

  @behaviour Orchestrator.SecretsSource
  require Logger

  @impl true
  def fetch(name) do
    Logger.debug("get_secret(#{name})") 
    Logger.info("Getting secret #{name} from region #{System.fetch_env!("AWS_BACKEND_REGION")}")

    # We may be called in various stages of the life cycle, including really
    # early, so make sure that what ExAws needs is up and running.
    [:ex_aws_secretsmanager, :hackney, :jason]
    |> Enum.map(&Application.ensure_all_started/1)

    parts = String.split(name, "#")
    secret_name = hd(parts)
    result =
      secret_name
      |> ExAws.SecretsManager.get_secret_value()
      |> do_aws_request()

    case result do
      {:ok, %{"SecretString" => secret}} ->
        case parts do
          [_path] ->
            secret
          [_path, selector] ->
            secret
            |> Jason.decode!()
            |> Map.get(selector)
        end
        # For now, we only want to deal with string values because that's what the protocol expects
        |> to_string()
      {:error, message} ->
        Logger.info("Secret #{name} not found, returning nil. Got message #{inspect(message)}")
        nil
    end
  end


  defp do_aws_request(request) do
    region = System.fetch_env!("AWS_BACKEND_REGION")
    ExAws.request(request, region: region)
  end
end
