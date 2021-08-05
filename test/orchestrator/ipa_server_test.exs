defmodule Orchestrator.IPAServerTest do
  use ExUnit.Case, async: true

  test "valid configuration parser" do
    cfg = """
    patterns:
      braintree.Transaction:
        method: any
        host: api.*.braintreegateway.com
        url: /transaction$
    """

    expected = %{
      {"braintree", "Transaction"} => %{
        "method" => ~r/.*/,
        "host" => ~r/api.*.braintreegateway.com/,
        "url" => ~r/\/transaction$/
      }
    }

    parsed = Orchestrator.IPAServer.parse_config_string(cfg)

    assert expected == parsed
  end

  test "defaults are provided" do
    cfg = """
    patterns:
      braintree.Transaction:
    """

    expected = %{
      {"braintree", "Transaction"} => %{
        "method" => ~r/.*/,
        "host" => ~r/.*/,
        "url" => ~r/.*/
      }
    }

    parsed = Orchestrator.IPAServer.parse_config_string(cfg)

    assert expected == parsed
  end
end
