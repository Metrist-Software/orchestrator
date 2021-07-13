defmodule Orchestrator.ConfigurationTest do
  use ExUnit.Case, async: true

  import Orchestrator.Configuration

  test "Adding new monitor returns :add delta" do
    old = %{}
    new = %{
      "11vpT2igxMZN4fbt17yntDX" => %{
        checkName: nil,
        extraConfig: [],
        functionName: nil,
        id: "11vpT2igxMZN4fbt17yntDX",
        intervalSecs: 120,
        monitor: %{
          instance: %{
            checkLastReports: [
              %{key: "GetEvent", value: "2021-07-07T21:34:26.746185"},
              %{key: "SubmitEvent", value: "2021-07-07T21:34:26.746185"}
            ],
            lastReport: "2021-07-07T21:34:26.746185",
            name: "us-east-1"
          },
          name: "Datadog"
        },
        monitor_name: "datadog"
      }
    }

    deltas = diff_config(new, old)
    assert map_size(deltas.add) == 1
    assert map_size(deltas.delete) == 0
    assert map_size(deltas.change) == 0
  end

  test "Deleting a monitor returns :delete delta" do
    new = %{}
    old = %{
      "11vpT2igxMZN4fbt17yntDX" => %{
        checkName: nil,
        extraConfig: [],
        functionName: nil,
        id: "11vpT2igxMZN4fbt17yntDX",
        intervalSecs: 120,
        monitor: %{
          instance: %{
            checkLastReports: [
              %{key: "GetEvent", value: "2021-07-07T21:34:26.746185"},
              %{key: "SubmitEvent", value: "2021-07-07T21:34:26.746185"}
            ],
            lastReport: "2021-07-07T21:34:26.746185",
            name: "us-east-1"
          },
          name: "Datadog"
        },
        monitor_name: "datadog"
      }
    }

    deltas = diff_config(new, old)
    assert map_size(deltas.add) == 0
    assert map_size(deltas.delete) == 1
    assert map_size(deltas.change) == 0
  end

  test "Changing the interval returns a :change delta" do
    new = %{
      "11vpT2igxMZN4fbt17yntDX" => %{
        intervalSecs: 140
      }
    }
    old = %{
      "11vpT2igxMZN4fbt17yntDX" => %{
        intervalSecs: 120
      }
    }

    deltas = diff_config(new, old)
    assert map_size(deltas.add) == 0
    assert map_size(deltas.delete) == 0
    assert map_size(deltas.change) == 1
  end
end
