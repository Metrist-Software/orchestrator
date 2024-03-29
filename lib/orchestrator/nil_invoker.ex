defmodule Orchestrator.NilInvoker do
  @moduledoc """
  Invoker to use for testing or to temporarily disable monitors, it'll just log the invocation and then return a dummy task.
  """
  require Logger

  @behaviour Orchestrator.Invoker

  @impl true
  def invoke(config, _opts \\ []) do
    Task.async(fn ->
      Logger.info("Nil invocation on #{Orchestrator.Configuration.inspect config}")
      :nil_invoke_complete
    end)
  end
end
