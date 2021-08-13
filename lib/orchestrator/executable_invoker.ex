defmodule Orchestrator.ExecutableInvoker do
  @moduledoc """
  Standard invocation method: download and run the monitor and talk to it through stdio.

  Monitors are to be distributed as ZIP files.
  """
  require Logger

  @monitor_distributions_url "https://monitor-distributions.canarymonitor.com/"

  @behaviour Orchestrator.Invoker

  @impl true
  def invoke(config) do
    Logger.debug("Invoking #{inspect(config)}")
    {dir, executable} = maybe_download(config.run_spec.name)
    # executable is relative to dir, make it absolute
    executable = Path.join(dir, executable)
    executable = Path.expand(executable)
    Logger.debug("Running #{executable} from #{dir}")
    if not File.exists?(executable) do
      raise "Executable #{executable} does not exist, exiting!"
    end
    Task.async(fn ->
      port = Port.open({:spawn_executable, executable}, [
                         :binary,
                         :stderr_to_stdout,
                         cd: dir
                       ])
      Orchestrator.ProtocolHandler.start_protocol(config, port)
    end)
  end

  defp maybe_download(name) do
    if local_mode?() do
      Logger.warn("Using local mode, not downloading")
      {Path.join([local_path(), name]), name}
    else
      cache_or_download(name)
    end
  end

  defp cache_or_download(name) do
    latest = String.trim(download("#{name}-latest.txt"))

    if cache_disabled?() or not available?(name, latest) do
      fetch_and_unpack_zip(name, latest)
    end

    dir_and_exe_of(name, latest)
  end

  defp fetch_and_unpack_zip(name, version) do
    Logger.info("Fetching monitor #{name} version #{version}")

    zip = download(zip_name(name, version))
    tmp = Path.join([System.tmp_dir(), "#{name}-#{version}.zip"])
    File.write!(tmp, zip, [:binary])
    target = cache_location(name, version)
    File.mkdir_p(target)
    {:ok, files} = :zip.extract(String.to_charlist(tmp), cwd: String.to_charlist(target))
    Enum.map(files, &ensure_x_bit/1)
    File.rm(tmp)
  end

  # A bit dirty, but Erlang's unzip does not preserve the execute bit. It does not hurt to
  # have it on and it must be on for executables, so we set it for everything. This allows us
  # to use the built-in zip library. Alternative would be gzip+tar.
  defp ensure_x_bit(path) do
    use Bitwise
    {:ok, stat} = File.stat(path)
    File.chmod(path, stat.mode ||| 0o110)
  end

  defp available?(name, version) do
    loc = cache_location(name, version)
    File.dir?(loc) and File.exists?(Path.join(loc, name))
  end

  defp download(path) do
    {:ok, %HTTPoison.Response{body: body}} = HTTPoison.get(@monitor_distributions_url <> path)
    body
  end

  # A bunch of path/env helpers.

  defp cache_location(name, version), do: Path.join([cache_path(), name, version])

  defp zip_name(name, version), do: "#{name}-#{version}-linux-x64.zip"

  defp dir_and_exe_of(name, version), do: {cache_location(name, version), name}

  defp cache_disabled?, do: System.get_env("CANARY_EXE_DISABLE_CACHE") != nil

  defp local_mode?, do: local_path() != nil

  defp local_path, do: System.get_env("CANARY_EXE_LOCAL_PATH")

  defp cache_path, do: System.get_env("CANARY_CACHE_DIR") || default_cache_path()

  defp default_cache_path, do: Path.join([System.user_home(), ".cache/canary/monitors"])
end