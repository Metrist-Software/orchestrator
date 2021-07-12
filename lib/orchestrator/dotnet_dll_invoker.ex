defmodule Orchestrator.DotNetDLLInvoker do
  @moduledoc """
  Invocation method for monitors that are written in .NET and get distributed as DLLs. We bundle a C#-based monitor
  runner to this end - this lets us get away with just one copy of the whole .NET runtime so monitor downloads are
  fast.

  Binary ZIP files containing the monitors are distributed from the well-known location s3://canary-public-assets/dist/monitors/
  which is a location hard-coded in the runner. The runner is expected to live in the `:orchestrator` application's `priv`
  directory and therefore should be bundled there when a distribution package is built.
  """
  require Logger

  @max_monitor_runtime 15 * 60 * 1_000

  @behaviour Orchestrator.Invoker

  @impl true
  def invoke(config, _region) do
    Logger.info("So now what? I'm supposed to invoke #{inspect config} how?")
    Task.async(fn -> do_invoke(config) end)
  end

  defp do_invoke(config) do
    # Pretty much everything is handled by the runner for now, so all we need to do
    # is call it.
    runner_dir = Application.app_dir(:orchestrator, "priv/runner")
    runner = Path.join(runner_dir, "Canary.Shared.Monitoring.Runner")
    port = Port.open({:spawn_executable, runner}, [:binary, args: [config.monitorName]])
    ref = Port.monitor(port)
    Logger.debug("Opened port for #{config.monitorName} as #{inspect port}")
    wait_for_complete(port, ref, config.monitorName)
  end

  defp wait_for_complete(port, ref, monitorName) do
    receive do
	  {:DOWN, ^ref, :port, ^port, reason} ->
        Logger.debug("Monitor #{monitorName}: Received DOWN message, reason: #{inspect reason}, completing invocation.")
      msg ->
        Logger.debug("Monitor #{monitorName}: Ignoring message #{inspect msg}")
        wait_for_complete(port, ref, monitorName)
    after
      @max_monitor_runtime ->
        Logger.info("Monitor #{monitorName}: Monitor did not complete in time, killing it")
        Port.close(port)
    end
  end
end
