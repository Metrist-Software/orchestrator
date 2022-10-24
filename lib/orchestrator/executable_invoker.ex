defmodule Orchestrator.ExecutableInvoker do
  @moduledoc """
  Standard invocation method: download and run the monitor and talk to it through stdio.

  Monitors are to be distributed as ZIP files.
  """
  require Logger

  @behaviour Orchestrator.Invoker

  @impl true
  def invoke(config, opts \\ []) do
    Logger.debug("Invoking #{inspect(config)}")

    executable = Keyword.get(opts, :executable, nil)
    executable = unless executable, do: get_executable(config), else: executable

    Logger.debug("Running #{executable}")

    if not File.exists?(executable) do
      raise "Executable #{executable} does not exist, exiting!"
    end

    Orchestrator.Invoker.run_monitor(config, opts, fn ->
      Port.open({:spawn_executable, executable}, [
        :binary,
        :stderr_to_stdout,
        cd: Path.dirname(executable)
      ])
    end)
  end

  defp get_executable(config) do
    {dir, executable} =
      {Orchestrator.Invoker.maybe_download(config.run_spec.name), config.run_spec.name}

    # executable is relative to dir, make it absolute
    executable = Path.join(dir, executable)
    Path.expand(executable)
  end
end
