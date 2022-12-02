defmodule Mix.Tasks.Metrist.RunMonitor do
  use Mix.Task
  alias Mix.Tasks.Metrist.Helpers

  require Logger
  @moduledoc """
  Uses the existing protocols & invokers to run montiors locally

  Rundll requires that ./priv/runner be linked to the runner output dir * via

      cd priv/runner
      ln -s ../../aws-serverless/shared/Metrist.Shared.Monitoring.Runner/bin/Debug/netcoreapp3.1/* . (paths may be different)

  Note, you should use the dotnet publish dirs for the location.
  If the monitor has any nuget dependencies they will not be in your Debug/Release dirs but will be in the publish dir.

  Supports "rundll" & "exe" for -t and the development-time "cmd" to run an arbitrary command line.

  Can be run completely isolated as it does not send telemetry/errors to API's, it just outputs the values to
  stdout flagged with `[TELEMETRY_REPORT]` and `[ERROR]`.

  "=" signs in extra_config keys are not supported.

  Examples:

  * dotnet dll invoker run with 3 steps and 2 extra config values (in this case the extra_config values aren't used)
    For run dll the -m value should be the published directory

      mix metrist.run_monitor -t rundll -l ../aws-serverless/shared/Canary.Shared.Monitors.TestSignal/bin/Release/netcoreapp3.1/linux-x64/publish -s Zero -s Normal -s Poisson -e test1=1 -e test2=2

  * exe invoker with 1 step and no extra_config.
    For exe invokers the -m value should be an executable file

      mix metrist.run_monitor -t exe -l ../aws-serverless/shared/zoomclient/zoomclient -s JoinCall

  * cmd invoker with 1 step invoking the zoom client monitor.any()

      mix metrist.run_monitor -t cmd -l 'cd ../aws-serverless/shared/zoomclient; node index.js' -s JoinCall
  """
  @shortdoc "Run a monitor locally from any location via exe invoker or runner invoker utilizing the full protocol"

  def run(args) do
    Mix.Task.run("app.config")
    Application.ensure_started(:erlexec)
    setup_hackney_for_external_webhook_processing()

    {opts, []} =
      Helpers.do_parse_args(
        args, [
          run_type: :string,
          monitor_location: :string,
          extra_config: :keep,
          steps: :keep,
          timeout: :float,
          monitor_name: :string
        ],[
          t: :run_type,
          l: :monitor_location,
          e: :extra_config,
          s: :steps,
          m: :monitor_name
        ],[
          :run_type,
          :monitor_location,
          :steps
        ]
      )

    extra_config_mapping =
      Keyword.get_values(opts, :extra_config)
      |> Enum.map(fn x -> String.split(x, "=", parts: 2)
      |> List.to_tuple() end)
      |> Map.new()

    cfg = %{
      :extra_config => extra_config_mapping,
      :interval_secs => -1,
      :last_run_time => nil,
      :monitor_logical_name => opts[:monitor_name] || 'mix task run',
      :run_spec => opts[:run_type],
      :steps =>
        opts
        |> Keyword.get_values(:steps)
        |> Enum.map(fn step ->
          %{check_logical_name: step,
            timeout_secs: (opts[:timeout] || 60.0)}
        end)
    }
    |> Orchestrator.Configuration.translate_config()

    Logger.info("Running #{cfg.monitor_logical_name} with config #{inspect cfg}")

    get_invoker(opts[:run_type]).
    (
      cfg,
      get_args(opts)
    )
    |> Task.await(:infinity)

    Logger.info("Run complete")
  end

  defp get_args(opts) do
    telemetry_fun = fn (logical_name, step, time, metadata) -> Logger.info("#{logical_name} - [TELEMETRY_REPORT] Step: #{step} - Value: #{time}. Metadata #{inspect metadata}") end
    error_fun = fn (logical_name, step, rest, metadata) -> Logger.info("Error #{logical_name} - [ERROR] Step: #{step} - Error: #{rest}. Metadata #{inspect metadata}") end

    [
    error_report_fun: error_fun,
    telemetry_report_fun: telemetry_fun
    ]
    |> add_executable_arg(opts[:monitor_location], opts[:run_type])
  end

  defp get_invoker("exe"), do: &Orchestrator.ExecutableInvoker.invoke/2
  defp get_invoker("rundll"), do: &Orchestrator.DotNetDLLInvoker.invoke/2
  defp get_invoker("cmd"), do: &Orchestrator.CommandInvoker.invoke/2

  defp add_executable_arg(args, monitor_location, "exe"), do: Keyword.put(args, :executable, Path.expand(monitor_location))
  defp add_executable_arg(args, monitor_location, "rundll"), do: Keyword.put(args, :executable_folder, Path.expand(monitor_location))
  defp add_executable_arg(args, monitor_location, "cmd"), do: Keyword.put(args, :command_line, monitor_location)

  defp setup_hackney_for_external_webhook_processing() do
    # Needed if you are going to test external webhook processing
    Application.ensure_all_started(:hackney)
    Application.put_env(:orchestrator, :api_token, System.get_env("METRIST_API_TOKEN", "fake-token"))
  end
end
