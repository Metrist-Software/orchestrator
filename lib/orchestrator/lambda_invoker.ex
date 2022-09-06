defmodule Orchestrator.LambdaInvoker do
  @moduledoc """
  Invocation method for our shared monitoring functions in AWS Lambda. This is currently very Metrist specific, if others
  want to reuse it we probably want to add an explicit Lambda function name to the config.
  """
  require Logger

  @behaviour Orchestrator.Invoker

  # TODO this is very Metrist specific, especially the naming. Remove completely after
  # we're off Lambda? Would anyone else want this over the simpler exe/dll options?

  @impl true
  def invoke(config, _opts \\ []) do
    region = Orchestrator.Application.aws_region()
    name = lambda_function_name(config)
    req = ExAws.Lambda.invoke(name, %{}, %{}, invocation_type: :request_response)
    Logger.debug("About to spawn request #{inspect req}")
    # We spawn this as a task, so that we can keep receiving messages and do things like handle timeouts eventually.
    Task.async(fn -> ExAws.request(req, region: region, http_opts: [recv_timeout: 1_800_000], retries: [max_attempts: 1]) end)
  end

  defp lambda_function_name(%{run_spec: %{name: name}}), do: lambda_function_name(name)
  defp lambda_function_name(%{monitor_logical_name: monitor_logical_name}), do: lambda_function_name(monitor_logical_name)
  defp lambda_function_name(name) when is_binary(name), do: "monitor-#{name}-#{env()}-#{name}Monitor"

  defp env, do: System.get_env("ENVIRONMENT_TAG", "local-development")
end
