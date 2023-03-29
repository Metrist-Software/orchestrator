defmodule Orchestrator.ExecutableInvoker do
  @moduledoc """
  Standard invocation method: download and run the monitor and talk to it through stdio.

  Monitors are to be distributed as ZIP files.
  """
  require Logger

  alias Orchestrator.Invoker
  @behaviour Invoker

  @impl true
  def invoke(config, opts \\ []) do
    Logger.debug("Invoking #{Orchestrator.Configuration.inspect(config)}")

    # :executable is set for a manual monitor run
    executable =
      case Keyword.get(opts, :executable, nil) do
        nil -> get_executable(config)
        executable -> executable
      end

    Logger.debug("Running #{executable}")

    if not File.exists?(executable) do
      raise "Executable #{executable} does not exist, exiting!"
    end

    Invoker.run_monitor(config, opts, fn tmp_dir ->
      Invoker.start_monitor(executable, [cd: Path.dirname(executable)], tmp_dir)
    end)
  end

  defp get_executable(config) do
    name = config.run_spec.name
    dir = Invoker.maybe_download(name)

    # executable is relative to dir, make it absolute
    dir
    |> Path.join(name)
    |> Path.expand()
  end
end
