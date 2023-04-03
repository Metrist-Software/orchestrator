defmodule Orchestrator.MetristAPI do
  require Logger
  use HTTPoison.Base

  @impl true
  def process_url(url = <<"webhook", _rest>>) do
    host = System.get_env("METRIST_WEBHOOK_HOST", nil)
    "https://#{host}/api/#{url}"
  end

  def process_url(url) do
    host = System.get_env("METRIST_API_HOST", "app.metrist.io")
    "https://#{host}/api/#{url}"
  end

  @impl true
  def process_request_options(opts) do
    # This is mainly so we can run against the "fake" CA that a local backend will use. Another option
    # is to actually install the CA system-wide but that comes with its own set of risks.
    opts = case System.get_env("METRIST_DISABLE_TLS_VERIFICATION") do
      nil -> opts
      _ -> Keyword.put_new(opts, :ssl, [verify: :verify_none])
    end

    # This works for the most part as long as the appropriate HTTP status codes are returned
    # See https://hexdocs.pm/httpoison/HTTPoison.MaybeRedirect.html for details
    opts
    |> Keyword.put_new(:follow_redirect, true)
    |> Orchestrator.Application.with_proxy()
  end

  @impl true
  def process_request_headers(headers) do
    auth_headers = if Enum.any?(headers, fn {header, _value} -> header == "Authorization" end) do
      headers
    else
      api_token = Orchestrator.Application.api_token()
      [{"Authorization", "Bearer #{api_token}"} | headers]
    end

    # replace new lines in build info with semicolons
    formatted_build_id =
      Orchestrator.Application.build_id()
      |> String.replace("\r\n", ";")
      |> String.replace("\n", ";")

    [
       {"User-Agent", "Orchestrator/#{formatted_build_id}"}
      | auth_headers
    ]
  end
end
