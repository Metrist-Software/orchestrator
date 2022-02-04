defmodule Orchestrator.ExecutableInvoker do
  @moduledoc """
  Standard invocation method: download and run the monitor and talk to it through stdio.

  Monitors are to be distributed as ZIP files.
  """
  require Logger

  @monitor_distributions_url "https://monitor-distributions.canarymonitor.com/"

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
    {dir, executable} = maybe_download(config.run_spec.name)
    # executable is relative to dir, make it absolute
    executable = Path.join(dir, executable)
    Path.expand(executable)
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
    latest = get_latest_version(name, Orchestrator.Application.preview_mode?())

    if cache_disabled?() or not available?(name, latest) do
      fetch_and_unpack_zip(name, latest)
    end

    dir_and_exe_of(name, latest)
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
    use Bitwise
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

  defp dir_and_exe_of(name, version), do: {cache_location(name, version), name}

  defp cache_disabled?, do: System.get_env("CANARY_EXE_DISABLE_CACHE") != nil

  defp local_mode?, do: local_path() != nil

  defp local_path, do: System.get_env("CANARY_EXE_LOCAL_PATH")

  defp cache_path, do: System.get_env("CANARY_CACHE_DIR") || default_cache_path()

  defp default_cache_path, do: Path.join([System.user_home(), ".cache/canary/monitors"])
end
