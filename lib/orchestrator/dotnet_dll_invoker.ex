defmodule Orchestrator.DotNetDLLInvoker do
  @moduledoc """
  Invocation method for monitors that are written in .NET and get distributed as DLLs. We bundle a C#-based monitor
  runner to this end - this lets us get away with just one copy of the whole .NET runtime so monitor downloads are
  fast.

  Binary ZIP files containing the monitors are distributed from the well-known location s3://metrist-public-assets/dist/monitors/
  which is a location hard-coded in the runner. The runner is expected to live in the `:orchestrator` application's `priv`
  directory and therefore should be bundled there when a distribution package is built.
  """
  require Logger

  @behaviour Orchestrator.Invoker

  @impl true
  def invoke(config, opts \\ []) do
    # Pretty much everything is handled by the runner for now, so all we need to do
    # is call it.
    runner_dir = Application.app_dir(:orchestrator, "priv/runner")
    runner = Path.join(runner_dir, "Metrist.Shared.Monitoring.Runner")

    executable_folder = Keyword.get(opts, :executable_folder, nil)
    args = [config.monitor_logical_name]
    args = if executable_folder, do: [executable_folder | args] |> Enum.reverse(), else: args
    Logger.debug("#{inspect args}")

    Orchestrator.Invoker.run_monitor(config, opts, fn ->
        Port.open({:spawn_executable, runner}, [
                    :binary,
                    :stderr_to_stdout,
                    args: args
                  ])
    end)
  end
end
