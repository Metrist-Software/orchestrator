defmodule Orchestrator.MonitorRunningAlertingTest do
  use ExUnit.Case

  @now NaiveDateTime.utc_now()
  @two_hours_ago NaiveDateTime.add(@now, -7_200)

  describe "update_monitor_states" do
    test "Should mark ok monitors with no recent data as notrunning" do
      tracked_monitors = %{{"config", "monitor"} => {:ok, @two_hours_ago}}
      updated_monitors = Orchestrator.MonitorRunningAlerting.update_monitor_states(tracked_monitors)

      assert Map.get(updated_monitors, {"config", "monitor"}) == {:notrunning, @two_hours_ago}
    end

    test "Should mark notrunning monitors withrecent data as ok" do
      tracked_monitors = %{{"config", "monitor"} => {:notrunning, @now}}
      updated_monitors = Orchestrator.MonitorRunningAlerting.update_monitor_states(tracked_monitors)

      assert Map.get(updated_monitors, {"config", "monitor"}) == {:ok, @now}
    end

    test "Should not change ok monitors with recent data" do
      tracked_monitors = %{{"config", "monitor"} => {:ok, @now}}
      updated_monitors = Orchestrator.MonitorRunningAlerting.update_monitor_states(tracked_monitors)

      assert Map.get(updated_monitors, {"config", "monitor"}) == {:ok, @now}
    end

    test "Should not change notrunning monitors with no recent data" do
      tracked_monitors = %{{"config", "monitor"} => {:notrunning, @two_hours_ago}}
      updated_monitors = Orchestrator.MonitorRunningAlerting.update_monitor_states(tracked_monitors)

      assert Map.get(updated_monitors, {"config", "monitor"}) == {:notrunning, @two_hours_ago}
    end
  end

  describe "get_changed_monitors" do
    test "should return a list of monitors with changed state" do
      old_monitors = %{
        {"config1", "monitor1"} => {:notrunning, @two_hours_ago},
        {"config2", "monitor2"} => {:ok, @now},
      }
      new_monitors = %{
        {"config1", "monitor1"} => {:ok, @now},
        {"config2", "monitor2"} => {:ok, @now}
      }

      changes = Orchestrator.MonitorRunningAlerting.get_changed_monitors(old_monitors, new_monitors)

      assert changes == [{{"config1", "monitor1"}, {:ok, @now}}]
    end

    test "should return an empty list when no changes" do
      old_monitors = %{
        {"config1", "monitor1"} => {:notrunning, @two_hours_ago},
        {"config2", "monitor2"} => {:ok, @now},
      }
      new_monitors = %{
        {"config1", "monitor1"} => {:notrunning, @two_hours_ago},
        {"config2", "monitor2"} => {:ok, @now}
      }

      changes = Orchestrator.MonitorRunningAlerting.get_changed_monitors(old_monitors, new_monitors)

      assert changes == []
    end
  end
end
