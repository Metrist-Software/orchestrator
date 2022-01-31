defmodule Orchestrator.MonitorSchedulerTest do
  use ExUnit.Case, async: true

  import Orchestrator.MonitorScheduler

  test "time to next run when no last run should be right away" do
    assert time_to_next_run(nil, 120) == 0
  end

  test "time to next run when last run is more than interval ago should be right away" do
    now = ~N[2021-07-08 14:25:33.013591]
    last_run = ~N[2021-07-08 14:25:00.000]
    interval = 30
    assert time_to_next_run(last_run, interval, now) == 0
  end

  test "time to next run when last run is next than interval ago should be positive" do
    now = ~N[2021-07-08 14:25:33.013591]
    last_run = ~N[2021-07-08 14:25:00.013591]
    interval = 60
    assert time_to_next_run(last_run, interval, now) == 27
  end

  test "401 style errors go to Slack" do
    error = "You are talking too much, go away (HttpRequestException 401)"
    assert [_match, _capture] = Regex.run(dotnet_http_error_match(), error)
  end

  test "429 style errors go to Slack" do
    error = "You are talking too much, go away (HttpRequestException 429)"
    assert [_match, _capture] = Regex.run(dotnet_http_error_match(), error)
  end
end
