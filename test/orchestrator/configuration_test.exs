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

  test "Changing extra config produces :change delta" do
    new = %{
      monitors: [
        %{
          monitor_logical_name: "foodog",
          interval_secs: 120,
          extra_config: %{ "test" => "value" }
        }
      ]
    }

    old = %{
      monitors: [
        %{
          monitor_logical_name: "foodog",
          interval_secs: 120,
          extra_config: %{ "test" => "value", "test2" => "value2" }
        }
      ]
    }

    deltas = diff_config(new, old)
    assert length(deltas.add) == 0
    assert length(deltas.delete) == 0
    assert length(deltas.change) == 1
  end

  test "Different map orders do not produce a :change delta" do
    new = %{
      monitors: [
        %{
          interval_secs: 120,
          monitor_logical_name: "foodog",
          extra_config: %{ "test" => "value" }
        }
      ]
    }

    old = %{
      monitors: [
        %{
          monitor_logical_name: "foodog",
          interval_secs: 120,
          extra_config: %{ "test" => "value" }
        }
      ]
    }

    deltas = diff_config(new, old)
    assert length(deltas.add) == 0
    assert length(deltas.delete) == 0
    assert length(deltas.change) == 0
  end

  test "Runspec changes produce a :change delta" do
    new = %{
      monitors: [
        %{
          interval_secs: 120,
          monitor_logical_name: "foodog",
          run_spec: nil,
          extra_config: %{ "test" => "value" }
        }
      ]
    }

    old = %{
      monitors: [
        %{
          monitor_logical_name: "foodog",
          interval_secs: 120,
          run_spec: "RunDLL",
          extra_config: %{ "test" => "value" }
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
