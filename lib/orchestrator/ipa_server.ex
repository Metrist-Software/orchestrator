defmodule Orchestrator.IPAServer do
  @moduledoc """
  Server module for the in-process agent. It opens a UDP port and forwards any data it receives
  to the backend as monitoring measurements. It also employs a tiny DSL-like configuration language
  to allow selectivity in this forwarding process.
  """
  use GenServer
  require Logger

  @port 51712
  @any ~r/.*/
  # The default config forwards some internal data
  # You can choose whether to include this in your config or not.
  # For now we support both our old and new domains, we need to make sure that
  # we have properly cleaned up old config before removing the rules here.
  @default_config %{
    {"metrist", "GetRunConfig"} => %{
      "method" => ~r(GET),
      "host" => ~r(app.*\.metrist\.io),
      "url" => ~r(api/agent/run-config)
    },
    {"metrist", "GetRunConfig"} => %{
      "method" => ~r(GET),
      "host" => ~r(app.*\.canarymonitor\.com),
      "url" => ~r(api/agent/run-config)
    },
    # Note that this has special support in the IPA agent to
    # exclude the sending of our own telemetry
    {"metrist", "SendTelemetry"} => %{
      "method" => ~r(POST),
      "host" => ~r(app.*\.metrist\.io),
      "url" => ~r(api/agent/telemetry)
    },
    {"metrist", "SendTelemetry"} => %{
      "method" => ~r(POST),
      "host" => ~r(app.*\.canarymonitor\.com),
      "url" => ~r(api/agent/telemetry)
    },
    {"metrist", "GetLatestMonitorBuild"} => %{
      "method" => ~r(GET),
      "host" => ~r(monitor-distributions.canarymonitor.com),
      "url" => ~r(latest.*txt)
    }
  }


  def start_link(_args) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_args) do
    ip = if Orchestrator.Application.ipa_loopback_only?, do: :loopback, else: :any
    {:ok, _sock} = :gen_udp.open(@port, [{:active, true}, :inet, {:ip, ip}])
    # IPv6 is optional for now, so we ignore what is returned on purpose.
    :gen_udp.open(@port, [{:active, true}, :inet6, {:ip, ip}])

    # This is currently IPA specific, but at one point can grow more generic agent stuff at which
    # point it should move elsewhere.
    config =
      case Orchestrator.Application.cma_config() do
        nil ->
          @default_config

        file ->
          parse_config_file(file)
      end

    Logger.info("IPA: Started listening on port #{@port} for messages")

    {:ok, config}
  end

  def handle_info({:udp, _socket, _host, _port, msg}, config) do
    cleaned_msg =
      msg
      |> List.to_string()
      |> String.trim()

    try do
      handle_message(cleaned_msg, config)
    rescue
      e -> Logger.error("IPA: Got error processing #{inspect(msg)}: #{Exception.format(:error, e, __STACKTRACE__)}")
    end

    {:noreply, config}
  end

  def handle_message(<<"0", rest::binary>>, config) do
    [method, host, path, value] =
      rest
      |> String.trim()
      |> String.split(~r/[[:space:]]+/, parts: 4)

    maybe_send(method, host, path, value, config)
  end

  def handle_message(<<"1", rest::binary>>, config) do
    [method, url, value] =
      rest
      |> String.trim()
      |> String.split(~r/[[:space:]]+/, parts: 3)

    uri =
      URI.parse(url)

    maybe_send(method, uri.host, uri.path, value, config)
  end

  def handle_message(other, _config) do
    Logger.error("IPA: Unknown message <<#{inspect(other)}>>, skipping")
  end

  def maybe_send(method, host, path, value, config) do
    case Enum.find(config, fn {_, v} -> matches?(method, host, path, v) end) do
      {{m, c}, v} ->
        {value, _} = Float.parse(value)
        Logger.info("IPA: We are sending (m=#{method} h=#{host} p=#{path} δt=#{value}) as (mon=#{m} chk=#{c}) because #{inspect(v)} matches")
        Orchestrator.APIClient.write_telemetry(m, c, value, [])
      _ ->
        Logger.info("IPA: #{method}/#{host}/#{path} does not match anything in our configuration")
    end
  end

  def matches?(method, host, path, pats) do
    Regex.match?(pats["method"], method) &&
      Regex.match?(pats["host"], host) &&
      Regex.match?(pats["url"], path)
  end

  def parse_config_file(file) do
    file
    |> YamlElixir.read_from_file!()
    |> parse_config()
  end

  def parse_config_string(string) do
    string
    |> YamlElixir.read_from_string!()
    |> parse_config()
  end

  def parse_config(raw_config) do
    raw_config
    |> Map.put_new("patterns", %{})
    |> Map.get("patterns")
    |> Enum.map(fn {mc, pats} ->
      [monitor, check] = String.split(mc, ".", parts: 2)
      pats =
        Enum.map(pats || %{}, fn {type, pat} ->
          pat =
            case pat do
              "any" -> @any
              pat -> Regex.compile!(pat)
            end

          {type, pat}
        end)
        |> Map.new()
        |> Map.put_new("host", @any)
        |> Map.put_new("method", @any)
        |> Map.put_new("url", @any)

      {{monitor, check}, pats}
    end)
    |> Map.new()
  end
end
