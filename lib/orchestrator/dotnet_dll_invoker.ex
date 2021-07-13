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
  def invoke(config, _region) do
    Task.async(fn -> do_invoke(config) end)
  end

  defp do_invoke(config) do
    # Pretty much everything is handled by the runner for now, so all we need to do
    # is call it.
    runner_dir = Application.app_dir(:orchestrator, "priv/runner")
    runner = Path.join(runner_dir, "Canary.Shared.Monitoring.Runner")

    port =
      Port.open({:spawn_executable, runner}, [
        :binary,
        :stderr_to_stdout,
        args: [config.monitor_name]
      ])

    ref = Port.monitor(port)
    Logger.info("Opened port for #{config.monitor_name} as #{inspect(port)}")
    :ok = handle_handshake(port, config)
    wait_for_complete(port, ref, config.monitor_name)
  end

  defp wait_for_complete(port, ref, monitor_name) do
    receive do
      {:DOWN, ^ref, :port, ^port, reason} ->
        Logger.debug(
          "Monitor #{monitor_name}: Received DOWN message, reason: #{inspect(reason)}, completing invocation."
        )

      {^port, {:data, data}} ->
        Logger.debug("Monitor #{monitor_name}: stdout: #{data}")
        wait_for_complete(port, ref, monitor_name)

      msg ->
        Logger.debug("Monitor #{monitor_name}: Ignoring message #{inspect(msg)}")
        wait_for_complete(port, ref, monitor_name)
    after
      @max_monitor_runtime ->
        Logger.error("Monitor #{monitor_name}: Monitor did not complete in time, killing it")
        Port.close(port)
    end
  end

  # Protocol bits. This probably should move to a different module

  defp handle_handshake(port, config) do
    matches = expect(port, ~r/Started ([0-9]+)\.([0-9]+)/)
    major = Integer.parse(Enum.at(matches, 1))
    minor = Integer.parse(Enum.at(matches, 3))
    assert_compatible(config.monitor_name, major, minor)
    write(port, "Version #{@major}.#{@minor}")
    expect(port, ~r/Ready/)
    json = Jason.encode!(config.extra_config)
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
        {len, rest} = Integer.parse(data)
        if len + 1 != String.length(rest), do: raise "Unexpected message, expected #{len} bytes, got #{rest}"
        String.trim_leading(rest)
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
    Port.command(port, len <> " " <> msg)
  end

  defp assert_compatible(monitor_name, major, _minor) when major != @major,
    do: raise("#{monitor_name}: Incompatible major version, got #{major}, want #{@major}")
  defp assert_compatible(monitor_name, _major, minor) when minor > @minor,
    do: raise("#{monitor_name}: Incompatible minor version, got #{minor}, want >= #{@minor}")
  defp assert_compatible(_monitor_name, _major, _minor), do: :ok
end
