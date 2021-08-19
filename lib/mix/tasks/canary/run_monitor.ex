defmodule Mix.Tasks.Canary.RunMonitor do
  use Mix.Task
  alias Mix.Tasks.Canary.Helpers

  require Logger
  @moduledoc """
  Uses the existing protocols & invokers to run montiors locally

  Requires that ./priv/runner be linked to the runner output dir * via

  cd priv/runner
  ln -s ../../aws-serverless/shared/Canary.Shared.Monitoring.Runner/bin/Debug/netcoreapp3.1/* . (paths may be different)

  Supports absolute and relative paths for -m

  Supports "rundll" & "exe" for -t

  Can be run completely isolated as it does not send telemetry/errors just outputs the values to the :stdout via [TELEMETRY_REPORT] & [ERROR]

  Examples:
    dotnet dll invoker run with 3 steps and 2 extra config values
    mix canary.run_monitor -t rundll -m "../aws-serverless/shared/Canary.Shared.Monitors.TestSignal/bin/Release/netcoreapp3.1/linux-x64/publish" -l testsignal -s Zero -s Normal -s Poisson -e test1=1 -e test2=2

    exe invoker with 1 step and no extra_config
    mix canary.run_monitor -t "exe" -m "../aws-serverless/shared/zoomclient/zoomclient" -l Zoom -s JoinCall
  """
  @shortdoc "Run a monitor locally from any location via exe invoker or runner invoker utilizing the full protocol"

  def run(args) do
    Mix.Task.run("app.config")

    {opts, []} =
      Helpers.do_parse_args(
        args, [
          run_type: :string,
          monitor_location: :string,
          monitor_logical_name: :string,
          extra_config: :keep,
          steps: :keep
        ],[
          t: :run_type,
          m: :monitor_location,
          l: :monitor_logical_name,
          e: :extra_config,
          s: :steps
        ],[
          :run_type,
          :monitor_location,
          :monitor_logical_name,
          :steps
        ]
      )

    extra_config_mapping = Keyword.get_values(opts, :extra_config) |> Enum.map(fn x -> String.split(x, "=") |> List.to_tuple() end) |> Map.new()

    cfg = %{
      :extra_config => extra_config_mapping,
      :interval_secs => -1,
      :last_run_time => nil,
      :monitor_logical_name => opts[:monitor_logical_name],
      :run_spec => opts[:run_type],
      :steps => Keyword.get_values(opts, :steps) |> Enum.map(fn step -> %{ :check_logical_name => step } end)
    }

    Logger.info("Running with config #{inspect cfg}")

    telemetry_fun = fn (logical_name, step, time) -> Logger.info("#{logical_name} - [TELEMETRY_REPORT] Step: #{step} - Value: #{time}") end
    error_fun = fn (logical_name, step, rest) -> Logger.info("Error #{logical_name} - [ERROR] Step: #{step} - Error: #{rest}") end

    run_fun = case opts[:run_type] do
      "exe" ->
        &Orchestrator.ExecutableInvoker.invoke/2
      "rundll" ->
        &Orchestrator.DotNetDLLInvoker.invoke/2
    end

    run_fun.
    (
      cfg,
      [executable: Path.expand(opts[:monitor_location]),
      error_report_fun: error_fun,
      telemetry_report_fun: telemetry_fun]
    )
    |> Task.await(600_000)

    Logger.info("Run complete")
  end
end
