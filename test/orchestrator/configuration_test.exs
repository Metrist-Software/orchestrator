defmodule Orchestrator.ConfigurationTest do
  use ExUnit.Case, async: true

  import Orchestrator.Configuration

  test "Adding new monitor returns :add delta" do
    old = %{}

    new = %{
      monitors: [
        %{
          id: "id-1",
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

    deltas = diff_and_store_config(new, old)
    assert length(deltas.add) == 1
    assert length(deltas.delete) == 0
    assert length(deltas.change) == 0

    # Check ETS updates
    assert get_config("id-1") == hd(deltas.add)
  end

  test "Deleting a monitor returns :delete delta" do
    new = %{}

    old = %{
      monitors: [
        %{
          id: "id-2",
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

    deltas = diff_and_store_config(new, old)
    assert length(deltas.add) == 0
    assert length(deltas.delete) == 1
    assert length(deltas.change) == 0

    assert get_config("id-2") == nil
  end

  test "Changing something returns a :change delta" do
    new = %{
      monitors: [
        %{
          id: "id-3",
          monitor_logical_name: "foodog",
          interval_secs: 120,
          extra_config: %{},
          run_spec: %{}
        }
      ]
    }

    old = %{
      monitors: [
        %{
          id: "id-3",
          monitor_logical_name: "foodog",
          interval_secs: 60,
          extra_config: %{},
          run_spec: %{}
        }
      ]
    }

    deltas = diff_and_store_config(new, old)
    assert length(deltas.add) == 0
    assert length(deltas.delete) == 0
    assert length(deltas.change) == 1

    # Extra assert as the orchestrator was successfully determining the delta previously
    # but was returning the same old config as the delta
    [change_config | _] = deltas.change
    [new_config | _] = Map.get(new, :monitors)
    assert change_config === new_config

    assert get_config("id-3") == new_config
  end

  test "Changing extra_config returns a :change delta" do
    # We had an instance where this did not seem to work. Make sure we're covered
    # by a test.
    new = %{
      monitors: [
        %{
          id: "id-3",
          monitor_logical_name: "foodog",
          extra_config: %{
            "foo" => "bar"
          },
          run_spec: %{}
        }
      ]
    }

    old = %{
      monitors: [
        %{
          id: "id-3",
          monitor_logical_name: "foodog",
          extra_config: %{
            "foo" => "baz"
          },
          run_spec: %{}
        }
      ]
    }

    deltas = diff_and_store_config(new, old)
    assert length(deltas.add) == 0
    assert length(deltas.delete) == 0
    assert length(deltas.change) == 1

    assert get_config("id-3") == hd(new.monitors)
  end

  test "Changing the last run time does not produce a delta" do
    new = %{
      monitors: [
        %{
          id: "id-4",
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
          id: "id-4",
          monitor_logical_name: "foodog",
          interval_secs: 120,
          last_run_time: ~N[2020-12-11 10:09:08],
          extra_config: %{ "test" => "value" }
        }
      ]
    }

    deltas = diff_and_store_config(new, old)
    assert length(deltas.add) == 0
    assert length(deltas.delete) == 0
    assert length(deltas.change) == 0

    # Nil, because we never stored the old version in the first place, so this
    # asserts no updates were done.
    assert get_config("id-4") == nil
  end

  # Nil extra configs was throwing protocol Enumerable not implemented for nil of type Atom
  # and we do have monitors with nil configs
  test "nil extra config doens't error" do
    config = Orchestrator.Configuration.translate_config(%{extra_config: nil})
    assert config == %{extra_config: %{}, run_spec: %{}}
  end
end
