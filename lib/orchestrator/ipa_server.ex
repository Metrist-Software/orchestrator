defmodule Orchestrator.IPAServer do
  @moduledoc """
  Server module for the in-process agent. It opens a UDP port and forwards any data it receives
  to the backend as monitoring measurements. It also employs a tiny DSL-like configuration language
  to allow selectivity in this forwarding process.
  """
  use GenServer
  require Logger

  @port 51712

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_args) do
    {:ok, _sock} = :gen_udp.open(@port, [{:active, true}, :inet, {:ip, :loopback}])
    # IPv6 is optional for now, so we ignore what is returned on purpose.
    :gen_udp.open(@port, [{:active, true}, :inet6, {:ip, :loopback}])

    # This is currently IPA specific, but at one point can grow more generic agent stuff at which
    # point it should move elsewhere.
    config =
      case Orchestrator.Application.cma_config() do
        nil ->
          %{}

        file ->
          YamlElixir.read_from_file!(file)
      end
      |> IO.inspect(label: "Parsed config")

    Logger.info("Started listening on port #{@port} for IPA messages")

    {:ok, config}
  end

  def handle_info({:udp, _socket, _host, _port, msg}, config) do
    Logger.debug("Has message! #{inspect(msg)}")
    cleaned_msg = msg
    |> List.to_string()
    |> String.trim()
    try do
      handle_message(cleaned_msg, config)
    rescue
      e ->
        Logger.error("Got error processing #{inspect msg}: #{Exception.format(:error, e, __STACKTRACE__)}")
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
    |> IO.inspect(label: "split")

    uri = URI.parse(url)
    |> IO.inspect(label: "uri")
    maybe_send(method, uri.host, uri.path, value, config)
  end

  def handle_message(other, _config) do
    Logger.error("Unknown message <<#{inspect(other)}>>, skipping")
  end

  def maybe_send(method, host, path, value, config) do
    Enum.any?(config["patterns"], fn {k, v} ->
      case matches?(method, host, path, v) do
        true ->
          {value, _} = Float.parse(value)
          Logger.info(
            "We are sending #{method}/#{host}/#{path}/#{value} as #{k} because #{inspect(v)} matches"
          )

          true

        false ->
          false
      end
    end)
  end

  def matches?(method, host, path, pats) do
    # TODO pre-compile when we're reading this in
    # Code is a bit ugly for now but saves compiling.
    method_re = Regex.compile!(pats["method"] || ".*")

    if Regex.match?(method_re, method) do
      host_re = Regex.compile!(pats["host"] || ".*")

      if Regex.match?(host_re, host) do
        path_re = Regex.compile!(pats["url"] || ".*")

        if Regex.match?(path_re, path) do
          true
        else
          false
        end
      else
        false
      end
    else
      false
    end
  end

  # parse
  # 0 method host path value
  # 1 method url value
  #
  # parse
  # patterns:
  # braintree.Transaction:
  # method: any
  # host: api.*.braintreegateway.com
  # url: /transaction$
end
