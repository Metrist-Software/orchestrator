defmodule Orchestrator.PingInvoker do
  @moduledoc """
  A built-in invoker type that just does an ICMP Ping to an endpoint. Can be used as a very basic
  check for new monitors.

  The check name is hardcoded, any steps configured are ignored.

  There is only one configuration setting:
  - `target` - the name/IP of the host to ping.

  """

  require Logger

  @behaviour Orchestrator.Invoker

  @impl true
  def invoke(config, opts \\ []) do
    Task.async(fn ->
      target = Map.get(config.extra_config, :"Target")

      error_report_fun =
        Keyword.get(opts, :error_report_fun, &Orchestrator.APIClient.write_error/4)

      telemetry_report_fun =
        Keyword.get(opts, :telemetry_report_fun, &Orchestrator.APIClient.write_telemetry/4)

      report_error = fn error ->
        Logger.error("Ping of #{target} resulted in error: #{error}")
        error_report_fun.(config.monitor_logical_name, "Ping", error, [])
      end

      report_telem = fn telem ->
        Logger.info("Ping of #{target} complete, average time is #{telem}ms.")
        telemetry_report_fun.(config.monitor_logical_name, "Ping", telem, [])
      end

      Logger.info("Invoking ping #{target}")
      {output, exit_code} = System.cmd("ping", ["-c5", "-W5", target], stderr_to_stdout: true)
      Logger.info("Ping exited with #{exit_code}, output: #{output}")

      case exit_code do
        0 ->
          case parse_output(output) do
            {:ok, telem} ->
              report_telem.(telem)

            :error ->
              # We don't report an error, as it is not the target's fault that something seems to be
              # off with the environment where Orchestrator is running.
              Logger.error(
                "Ping of #{target} could not parse output, unknown version of ping command on system?"
              )
          end

        other ->
          report_error.("Ping command exited with error status #{other}.")
      end

      :ping_complete
    end)
  end

  def parse_output(output) do
    # "rtt min/avg/max/mdev = 46.799/53.179/59.289/4.423 ms"

    stats_line =
      output
      |> String.trim()
      |> String.split("\n")
      |> List.last()

    parse_line = fn line ->
      {value, _} =
        line
        |> String.split("/")
        |> Enum.at(1)
        |> Float.parse()

      value
    end

    case stats_line do
      # Regular iputils ping
      "rtt min/avg/max/mdev = " <> rest ->
        {:ok, parse_line.(rest)}

      # Busybox
      "round-trip min/avg/max = " <> rest ->
        {:ok, parse_line.(rest)}

      other ->
        :error
    end
  end
end
