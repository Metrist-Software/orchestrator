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

  test "Changing the interval returns a :change delta" do
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
  end

  test "Monitors that have different checks are different monitors" do
    new = %{
      monitors: [
        %{
          monitor_logical_name: "foodog",
          steps: [
            %{check_logical_name: "check_two"}
          ],
          interval_secs: 120
        },
        %{
          monitor_logical_name: "foodog",
          steps: [
            %{check_logical_name: "check_one"}
          ],
          interval_secs: 60
        }
      ]
    }

    old = %{
      monitors: [
        %{
          monitor_logical_name: "foodog",
          steps: [
            %{check_logical_name: "check_one"}
          ],
          interval_secs: 60
        }
      ]
    }

    deltas = diff_config(new, old)
    assert length(deltas.add) == 1
    assert length(deltas.delete) == 0
    assert length(deltas.change) == 0
  end
end
