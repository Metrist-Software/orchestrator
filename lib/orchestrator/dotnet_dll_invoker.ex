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
  @major 1
  @minor 1

  @behaviour Orchestrator.Invoker

  @impl true
  def invoke(config) do
    # Pretty much everything is handled by the runner for now, so all we need to do
    # is call it.
    runner_dir = Application.app_dir(:orchestrator, "priv/runner")
    runner = Path.join(runner_dir, "Canary.Shared.Monitoring.Runner")

    port =
      Port.open({:spawn_executable, runner}, [
        :binary,
        :stderr_to_stdout,
        args: [config.monitor_logical_name]
      ])

    ref = Port.monitor(port)
    Logger.info("Opened port for #{config.monitor_logical_name} as #{inspect(port)}")
    :ok = handle_handshake(port, config)
    wait_for_complete(port, ref, config.monitor_logical_name)
  end

  defp wait_for_complete(port, ref, monitor_logical_name) do
    receive do
      {:DOWN, ^ref, :port, ^port, reason} ->
        Logger.debug(
          "Monitor #{monitor_logical_name}: Received DOWN message, reason: #{inspect(reason)}, completing invocation."
        )

      {^port, {:data, data}} ->
        handle_message(data, monitor_logical_name)
        wait_for_complete(port, ref, monitor_logical_name)

      msg ->
        Logger.debug("Monitor #{monitor_logical_name}: Ignoring message #{inspect(msg)}")
        wait_for_complete(port, ref, monitor_logical_name)
    after
      @max_monitor_runtime ->
        Logger.error("Monitor #{monitor_logical_name}: Monitor did not complete in time, killing it")
        Port.close(port)
    end
  end

  # Protocol bits. This probably should move to a different module if/when we add multiple invocation types.

  defp handle_message("", _monitor_logical_name), do: :ok
  defp handle_message(data, monitor_logical_name) do
    case Integer.parse(data) do
      {len, rest} ->
        message = String.slice(rest, 1, len)
        parts = String.split(message, " ", parts: 2)
        if length(parts) == 2 do
          maybe_log(Enum.at(parts, 0), Enum.at(parts, 1), monitor_logical_name)
        end
        # If there's more, there's more
        handle_message(String.slice(rest, 1 + len, 100_000), monitor_logical_name)
      :error ->
        Logger.debug("#{monitor_logical_name}: stdout: #{data}")
    end
  end
  defp maybe_log("Debug", msg, monitor_logical_name), do: Logger.debug("#{monitor_logical_name}: #{msg}")
  defp maybe_log("Info", msg, monitor_logical_name), do: Logger.info("#{monitor_logical_name}: #{msg}")
  defp maybe_log("Warning", msg, monitor_logical_name), do: Logger.warning("#{monitor_logical_name}: #{msg}")
  defp maybe_log("Error", msg, monitor_logical_name), do: Logger.error("#{monitor_logical_name}: #{msg}")
  defp maybe_log(w, ws, monitor_logical_name), do: Logger.info("#{monitor_logical_name}: Unknown: #{w} #{ws}")


  defp handle_handshake(port, config) do
    matches = expect(port, ~r/Started ([0-9]+)\.([0-9]+)/)
    {major, _} = Integer.parse(Enum.at(matches, 1))
    {minor, _} = Integer.parse(Enum.at(matches, 2))
    assert_compatible(config.monitor_logical_name, major, minor)
    write(port, "Version #{@major}.#{@minor}")
    expect(port, ~r/Ready/)
    json = Jason.encode!(config.extra_config || %{})
    write(port, "Config #{json}")
    :ok
  end

  defp expect(port, regex) do
    msg = read(port)
    Regex.run(regex, msg)
  end

  defp read(port) do
    receive do
      {^port, {:data, data}} ->
        Logger.debug("Received data: #{inspect data}")
        case Integer.parse(data) do
          {len, rest} ->
            # This should not happen, but if it does, we can always make a more complex read function. For now, good enough.
            # Note that technically, we can have other stuff interfering here, or multiple messages in one go, but at this
            # part in the protocol (we only get called from the handshake) we should not be too worried about that.
            if len + 1 != String.length(rest), do: raise "Unexpected message, expected #{len} bytes, got \"#{rest}\""
            String.trim_leading(rest)
          :error ->
            Logger.info("Ignoring monitor output: #{data}")
            read(port)
        end
    after
      60_000->
        raise "Nothing read during handshake"
    end
  end

  defp write(port, msg) do
    len =
      msg
      |> String.length()
      |> Integer.to_string()
      |> String.pad_leading(5, "0")
    msg = len <> " " <> msg
    Port.command(port, msg)
    Logger.debug("Sent message: #{inspect msg}")
  end

  defp assert_compatible(monitor_logical_name, major, _minor) when major != @major,
    do: raise("#{monitor_logical_name}: Incompatible major version, got #{major}, want #{@major}")
  defp assert_compatible(monitor_logical_name, _major, minor) when minor > @minor,
    do: raise("#{monitor_logical_name}: Incompatible minor version, got #{minor}, want >= #{@minor}")
  defp assert_compatible(_monitor_logical_name, _major, _minor), do: :ok
end
