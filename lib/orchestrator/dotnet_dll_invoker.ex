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
  def invoke(config) do
    # Pretty much everything is handled by the runner for now, so all we need to do
    # is call it.
    runner_dir = Application.app_dir(:orchestrator, "priv/runner")
    runner = Path.join(runner_dir, "Canary.Shared.Monitoring.Runner")

    Task.async(fn ->
      port =
        Port.open({:spawn_executable, runner}, [
                    :binary,
                    :stderr_to_stdout,
                    args: [config.monitor_logical_name]
                  ])
      Logger.info("Opened port for #{config.monitor_logical_name} as #{inspect(port)}")

      ref = Port.monitor(port)
      :ok = Orchestrator.ProtocolHandler.handle_handshake(port, config)
      {:ok, pid} = Orchestrator.ProtocolHandler.start_link(config.monitor_logical_name, config.steps, self())
      wait_for_complete(port, ref, config.monitor_logical_name, pid)
      Logger.info("Monitor #{config.monitor_logical_name} is complete")
    end)
  end

  # This is strictly not DLL specific, but how things work when using a Port. So this will likely move
  # elsewhere at some time.

  defp wait_for_complete(port, ref, monitor_logical_name, protocol_handler) do
    receive do
      {:DOWN, ^ref, :port, ^port, reason} ->
        Logger.info(
          "Monitor #{monitor_logical_name}: Received DOWN message, reason: #{inspect(reason)}, completing invocation."
        )

      {^port, {:data, data}} ->
        Orchestrator.ProtocolHandler.handle_message(protocol_handler, monitor_logical_name, data)
        wait_for_complete(port, ref, monitor_logical_name, protocol_handler)

      {:write, message} ->
        Orchestrator.ProtocolHandler.write(port, message)
        wait_for_complete(port, ref, monitor_logical_name, protocol_handler)

      msg ->
        Logger.debug("Monitor #{monitor_logical_name}: Ignoring message #{inspect(msg)}")
        wait_for_complete(port, ref, monitor_logical_name, protocol_handler)
    after
      @max_monitor_runtime ->
        Logger.error("Monitor #{monitor_logical_name}: Monitor did not complete in time, killing it")
        Port.close(port)
    end
  end
end
