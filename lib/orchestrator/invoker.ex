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

  # Download/caching support.

  @monitor_distributions_url "https://monitor-distributions.metrist.io/"

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
    import  Bitwise
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
