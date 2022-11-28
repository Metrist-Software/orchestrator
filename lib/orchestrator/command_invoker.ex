defmodule Orchestrator.CommandInvoker do
  @moduledoc """
  Invocation method: execute a command line.

  This is mostly meant for development. For example, a Node or Python monitor will be
  normally distributed as a single executable, but this takes an extra step after making
  source code changes to package up the monitor so it can be handed to `Orchestrator.ExecutableInvoker`.

  Arbitrary command lines may be passed in, they are invoked through `bash -c 'command_line'`
  """

  require Logger

  alias Orchestrator.Invoker
  @behaviour Invoker

  @impl true
  def invoke(config, opts \\ []) do
    command_line = Keyword.get(opts, :command_line, nil)
    command_line = "bash -c '#{command_line}'"

    Logger.debug("Running #{command_line}")

    Invoker.run_monitor(config, opts, fn tmp_dir ->
      Invoker.start_monitor(command_line, [], tmp_dir)
    end)
  end
end
