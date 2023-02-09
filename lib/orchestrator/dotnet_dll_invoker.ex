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

  alias Orchestrator.Invoker
  @behaviour Invoker

  @impl true
  def invoke(config, opts \\ []) do
    runner_dir = Application.app_dir(:orchestrator, "priv/runner")
    runner = Path.join(runner_dir, "Metrist.Runner")

    # :executable_folder is set for a manual monitor run
    executable_folder =
      case Keyword.get(opts, :executable_folder, nil) do
        nil -> get_executable_folder(config)
        executable_folder -> executable_folder
      end

    cmd = "#{runner} #{config.monitor_logical_name} #{executable_folder}"
    Logger.debug("#{inspect(cmd)}")

    Invoker.run_monitor(config, opts, fn tmp_dir ->
      Invoker.start_monitor(cmd, [], tmp_dir)
    end)
  end

  def get_executable_folder(config) do
    Invoker.maybe_download(config.run_spec.name)
  end
end
