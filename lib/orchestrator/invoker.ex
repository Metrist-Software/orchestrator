defmodule Orchestrator.Invoker do
  @moduledoc """
  Behaviour definition for modules that can act as a monitor invoker.
  """
  require Logger

  defmodule(TmpName, do: use(Puid, charset: :safe64, bits: 64))

  @doc """
  Invoke the monitor. `config` is the monitor configuration as stored server-side, and `region` is the
  region (or instance, host, ...) we are running in. Must return a task, `Orchestrator.MonitorScheduler`
  will then have its hands free to keep an eye on the clock, etcetera.
  """
  @callback invoke(config :: map(), opts :: []) :: Task.t()

  @doc """
  Starts a monitor on a port and runs the protocol.
  """
  def run_monitor(config, opts, port_fn) do
    tmpdir = Path.join(Orchestrator.Application.temp_dir(), "orchtmp-#{TmpName.generate()}")
    File.mkdir_p!(tmpdir)

    parent = self()

    Task.async(fn ->
      Orchestrator.Application.set_monitor_metadata(config)

      # A bit dirty, the OTP way is to serialize using processes, not locks. But it is infrequent enough
      # that the difference is going to be more theoretical than practical. We keep the lock just long enough
      # to start the child process, at which point the environment will have been copied and we can safely continue.
      port = :global.trans({__MODULE__, self()}, fn ->
        System.put_env("TMPDIR", tmpdir)
        System.put_env("TEMP", tmpdir)
        System.put_env("TMP", tmpdir)
        port_fn.()
      end)
      pid = Keyword.get(Port.info(port), :os_pid)
      GenServer.cast(parent, {:monitor_pid, pid})

      Logger.info("Started monitor with OS pid #{pid}")
      Logger.metadata(os_pid: pid)

      result = Orchestrator.ProtocolHandler.run_protocol(config, port, opts)

      File.rm_rf!(tmpdir)

      result
    end)
  end
end
