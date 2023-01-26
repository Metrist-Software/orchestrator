defmodule Orchestrator.Invoker do
  @moduledoc """
  Behaviour definition for modules that can act as a monitor invoker.
  """
  require Logger

  @doc """
  Invoke the monitor. `config` is the monitor configuration as stored server-side, and `region` is the
  region (or instance, host, ...) we are running in. Must return a task, `Orchestrator.MonitorScheduler`
  will then have its hands free to keep an eye on the clock, etcetera.
  """
  @callback invoke(config :: map(), opts :: []) :: Task.t()

  @doc """
  Starts a monitor on a port and runs the protocol.
  """
  def run_monitor(config, opts, start_function) do
    tmpname = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    tmpdir = Path.join(Orchestrator.Application.temp_dir(), "orchtmp-#{tmpname}")
    File.mkdir_p!(tmpdir)

    parent = self()

    Task.Supervisor.async_nolink(Orchestrator.TaskSupervisor, fn ->
      Orchestrator.Application.set_monitor_logging_metadata(config)

      # Whatever happens, we must be able to cleanup tmpdir. So that's
      # why we trap exits here. ProtocolHandler will stop recursing on
      # receiving the EXIT signal.
      Process.flag(:trap_exit, true)

      os_pid = start_function.(tmpdir)
      GenServer.cast(parent, {:monitor_pid, os_pid})

      Logger.info("Started monitor with OS pid #{os_pid}")
      Logger.metadata(os_pid: os_pid)

      result = Orchestrator.ProtocolHandler.run_protocol(config, os_pid, opts)

      File.rm_rf!(tmpdir)
      Logger.info("Monitor complete, cleanup done")

      result
    end)
  end

  @doc """
  Configures the monitoring executable. Basically a light wrapper around Erlexec that ensures we
  have the correct options.
  """
  def start_monitor(cmd_line, extra_opts, tmp_dir) do
    opts =
      Keyword.put(extra_opts, :env, [
        # Yes, all three variations have been seen in the wild.
        {"TMPDIR", tmp_dir},
        {"TEMP", tmp_dir},
        {"TMP", tmp_dir},

      ])

    # The bi-directional linking only works if the subprocess exits with an error state.
    # On the protocol level, we don't care too much about process exit states, so the
    # easiest work-around is to have a success exit code that will trigger the linked error
    # exit.
    opts = opts ++ [:stdin, :stdout, :stderr, :monitor, :kill_group, success_exit_code: 1, group: 0]

    {:ok, _pid, os_pid} = :exec.run_link(cmd_line, opts)
    os_pid
  end

  # Download/caching support.

  @monitor_distributions_url "https://monitor-distributions.metrist.io/"

  @doc """
  Download the archive for the monitor with name `name` and unpack it. Unless disabled
  through a `METRIST_EXE_DISABLE_CACHE` this will check whether the most recent version
  is already available and just return a cache location instead.

  Full list of environment variables that influence the behaviour of this function:

  * `METRIST_EXE_DISABLE_CACHE` - disable cache lookup, will always download the archive.
  * `METRIST_EXE_LOCAL_PATH` - override download, use the indicated local path instead. Will not
    talk to external servers.
  * `METRIST_CACHE_DIR` - where to store downloaded archives. By default `~/.cache/metrist/monitors`

  Unless disabled by setting the local path, it will always fetch the most recent version for the
  monitor from `@monitor_distributions_url`.

  Returns the path to the unpacked archive.
  """
  @spec maybe_download(name :: String.t()) :: String.t()
  def maybe_download(name) do
    if local_mode?() do
      Logger.warn("Using local mode, not downloading")
      Path.join([local_path(), name])
    else
      cache_or_download(name)
    end
  end

  defp cache_or_download(name) do
    latest = get_latest_version(name, Orchestrator.Application.preview_mode?())

    if cache_disabled?() or not available?(name, latest) do
      fetch_and_unpack_zip(name, latest)
    end

    cache_location(name, latest)
  end

  defp get_latest_version(name, _preview_mode = true) do
    try do
      String.trim(download("#{name}-latest-preview.txt"))
    rescue
      _ -> get_latest_version(name, false)
    end
  end

  defp get_latest_version(name, _preview_mode = false) do
    String.trim(download("#{name}-latest.txt"))
  end

  defp fetch_and_unpack_zip(name, version) do
    Logger.info("Fetching monitor #{name} version #{version}")

    zip = download(zip_name(name, version))
    tmp = Path.join([System.tmp_dir(), "#{name}-#{version}.zip"])
    File.write!(tmp, zip, [:binary])

    target = ensure_cache_dir(name, version)

    {:ok, files} = :zip.extract(String.to_charlist(tmp), cwd: String.to_charlist(target))
    Enum.map(files, &ensure_x_bit/1)
    File.rm(tmp)
  end

  defp ensure_cache_dir(name, version) do
    top_level_cache = cache_location(name)

    # Delete the old version if it exists as we've now downloaded a new one
    if File.dir?(top_level_cache) do
      File.rm_rf(top_level_cache)
    end

    version_specific_cache = cache_location(name, version)
    File.mkdir_p(version_specific_cache)

    version_specific_cache
  end

  # A bit dirty, but Erlang's unzip does not preserve the execute bit. It does not hurt to
  # have it on and it must be on for executables, so we set it for everything. This allows us
  # to use the built-in zip library. Alternative would be gzip+tar.
  defp ensure_x_bit(path) do
    import Bitwise
    {:ok, stat} = File.stat(path)
    File.chmod(path, stat.mode ||| 0o110)
  end

  defp available?(name, version) do
    loc = cache_location(name, version)
    File.dir?(loc) and File.exists?(Path.join(loc, name))
  end

  def download(path) do
    {:ok, %HTTPoison.Response{body: body}} = HTTPoison.get(@monitor_distributions_url <> path)
    body
  end

  # A bunch of path/env helpers.

  defp cache_location(name), do: Path.join([cache_path(), name])
  defp cache_location(name, version), do: Path.join([cache_path(), name, version])

  defp zip_name(name, version), do: "#{name}-#{version}-linux-x64.zip"

  defp cache_disabled?, do: System.get_env("METRIST_EXE_DISABLE_CACHE") != nil

  defp local_mode?, do: local_path() != nil

  defp local_path, do: System.get_env("METRIST_EXE_LOCAL_PATH")

  defp cache_path, do: System.get_env("METRIST_CACHE_DIR") || default_cache_path()

  defp default_cache_path, do: Path.join([System.user_home(), ".cache/metrist/monitors"])
end
