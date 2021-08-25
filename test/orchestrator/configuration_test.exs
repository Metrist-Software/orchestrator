defmodule Orchestrator.ConfigurationTest do
  use ExUnit.Case, async: true

  import Orchestrator.Configuration

  test "Adding new monitor returns :add delta" do
    old = %{}

    new = %{
      monitors: [
        %{
          extra_config: %{},
          interval_secs: 120,
          last_run_time: nil,
          monitor_logical_name: "datadog",
          run_spec: nil,
          steps: [
            %{check_logical_name: "StepOne"}
          ]
        }
      ]
    }

    deltas = diff_config(new, old)
    assert length(deltas.add) == 1
    assert length(deltas.delete) == 0
    assert length(deltas.change) == 0
  end

  test "Deleting a monitor returns :delete delta" do
    new = %{}

    old = %{
      monitors: [
        %{
          extra_config: %{},
          interval_secs: 120,
          last_run_time: nil,
          monitor_logical_name: "datadog",
          run_spec: nil,
          steps: [
            %{check_logical_name: "StepOne"}
          ]
        }
      ]
    }

    deltas = diff_config(new, old)
    assert length(deltas.add) == 0
    assert length(deltas.delete) == 1
    assert length(deltas.change) == 0
  end

  test "Changing something returns a :change delta" do
    new = %{
      monitors: [
        %{
          monitor_logical_name: "foodog",
          interval_secs: 120
        }
      ]
    }

    old = %{
      monitors: [
        %{
          monitor_logical_name: "foodog",
          interval_secs: 60
        }
      ]
    }

    deltas = diff_config(new, old)
    assert length(deltas.add) == 0
    assert length(deltas.delete) == 0
    assert length(deltas.change) == 1

    # Extra assert as the orchestrator was successfully determining the delta previously
    # but was returning the same old config as the delta
    [change_config | _] = deltas.change
    [new_config | _] = Map.get(new, :monitors)
    assert change_config === new_config
  end

  test "Changing the last run time does not produce a delta" do
    new = %{
      monitors: [
        %{
          monitor_logical_name: "foodog",
          interval_secs: 120,
          last_run_time: ~N[2020-01-02 03:04:05],
          extra_config: %{ "test" => "value" }
        }
      ]
    }

    old = %{
      monitors: [
        %{
          monitor_logical_name: "foodog",
          interval_secs: 120,
          last_run_time: ~N[2020-12-11 10:09:08],
          extra_config: %{ "test" => "value" }
        }
      ]
    }

    deltas = diff_config(new, old)
    assert length(deltas.add) == 0
    assert length(deltas.delete) == 0
    assert length(deltas.change) == 0
  end
end
