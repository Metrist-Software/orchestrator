defmodule Integration.MonitorInvocationTest do
  @moduledoc """
  This tests basic interaction with the Erlexec library, to show what kind
  of messages flow back and forth. With this in hand, we can write unit
  tests for other logic and be sure that everything will work when
  we click it together.
  """
  use ExUnit.Case, async: true
  @moduletag :external
  @sleep 1_000

  alias Orchestrator.Invoker

  test "Correctly opens and closes monitoring processes" do
    os_pid = start_monitor()
    assert_receive {:stdout, ^os_pid, "00011 Started 1.1"}, @sleep

    # Check that we get notified on exit (IOW, that we have linked processes).
    Process.flag(:trap_exit, true)
    :exec.kill(os_pid, :sigterm)
    assert_receive {:EXIT, _pid, {:exit_status, 15}}, @sleep
  end

  test "Protocol handler write wraps correct function" do
    os_pid = start_and_configure_monitor()
    # Also tests the exit handling
    Orchestrator.ProtocolHandler.write(os_pid, "Exit 0")
    Process.sleep @sleep
    refute os_pid in :exec.which_children()
  end

  test "Exits when caller exits" do
    {:ok, agent} = Agent.start_link(fn ->
      start_monitor()
    end)

    os_pid = Agent.get(agent, & &1)
    assert os_pid in :exec.which_children()

    # We stop the agent, then the children list of Erlexec should not have
    # os_pid anymore.
    Agent.stop(agent)
    Process.sleep(@sleep)
    refute os_pid in :exec.which_children()
  end

  test "Can exchange protocol messages" do
    start_and_configure_monitor()
  end

  test "Logging works correctly" do
    os_pid = start_and_configure_monitor()
    :exec.send(os_pid, "00020 Run Step TestLogging")
    assert_receive {:stdout, ^os_pid, "00029 Log Debug Test Logging: DEBUG"}, @sleep
    assert_receive {:stdout, ^os_pid, "00027 Log Info Test Logging: INFO"}, @sleep
    assert_receive {:stdout, ^os_pid, "00029 Log Error Test Logging: ERROR"}, @sleep
    assert_receive {:stdout, ^os_pid, "00011 Step Time 2"}, @sleep
  end

  test "Error handling" do
    os_pid = start_and_configure_monitor()
    :exec.send(os_pid, "00014 Run Step Error")
    assert_receive {:stdout, ^os_pid, "00017 Step Error Error!"}, @sleep
  end

  test "Printing to stderr" do
    os_pid = start_and_configure_monitor()
    :exec.send(os_pid, "00020 Run Step PrintStderr")
    assert_receive {:stderr, ^os_pid, "On stderr\n"}, @sleep
    assert_receive {:stdout, ^os_pid, "00007 Step OK"}, @sleep
  end

  defp start_monitor do
    Invoker.start_monitor("node main.js", [cd: "test/integration/test_monitor"], "/tmp")
  end

  defp start_and_configure_monitor do
    os_pid = start_monitor()

    assert_receive {:stdout, ^os_pid, "00011 Started 1.1"}, @sleep
    :exec.send(os_pid, "00011 Version 1.1")
    assert_receive {:stdout, ^os_pid, "00005 Ready"}, @sleep
    :exec.send(os_pid, "00009 Config {}")
    assert_receive {:stdout, ^os_pid, "00010 Configured"}, @sleep

    os_pid
  end
end
