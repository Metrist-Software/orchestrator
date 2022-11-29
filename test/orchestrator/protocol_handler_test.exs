defmodule Orchestrator.ProtocolHandlerTest do
  use ExUnit.Case, async: true
  require Logger
  import ExUnit.CaptureLog

  alias Orchestrator.ProtocolHandler

  # We have some tests that work with message passing between processes,
  # make sure we don't wait too long if they happen to be broken.
  @moduletag timeout: 1_000

  describe "Message handling" do
    test "Incomplete single message returns {:incomplete, message}" do
      {result, _message} =
        ProtocolHandler.handle_message(
          self(),
          "testmonitor",
          "00041 Log Info Created card 6102e3cd"
        )

      assert result == :incomplete
    end

    test "Multiple messages where last is incomplete returns last message and :incomplete message returns {:incomplete, message}" do
      {result, message} =
        ProtocolHandler.handle_message(
          self(),
          "testmonitor",
          "00041 Log Info Created card 6102e3cde5a2f61a44700041 Log Second Created"
        )

      assert result == :incomplete
      assert message == "00041 Log Second Created"
    end

    test "Multiple complete messages will succeed with {:ok, nil}" do
      {result, message} =
        ProtocolHandler.handle_message(
          self(),
          "testmonitor",
          "00041 Log Info Created card 6102e3cde5a2f61a44700041 Log Info Create card 6102e3cde5a2f61a4478"
        )

      assert result == :ok
      assert message == nil
    end

    test "Message with CRLF will succeed with {:ok, nil}" do
      log =
        "00214 Log Debug statusCode: 500, gotIp: <html>\r\n<head><title>500 Internal Server Error</title></head>\r\n<body>\r\n<center><h1>500 Internal Server Error</h1></center>\r\n</body>\r\n</html>\r\n, theIp: ip-11-1-111-111, not done yet"

      {result, message} = ProtocolHandler.handle_message(self(), "testmonitor", log)
      assert result == :ok
      assert message == nil
    end

    test "Message is complete when the number of bytes is correct" do
      {result, message} = ProtocolHandler.handle_message(self(), "testmonitor", "00007 héllo")
      assert message == nil
      assert result == :ok
    end

    test "Empty log message works" do
      result = ProtocolHandler.handle_message(self(), "testmonitor", "00010 Log Debug ")
      assert {:ok, nil} == result
    end
  end

  describe "Completion handling" do
    defp send_exit, do: send(self(), {:EXIT, nil, {:exit_status, 0}})

    test "Partial messages get collected and sent to genserver" do
      os_pid = 42
      send(self(), {:stdout, os_pid, "00014 "})
      send(self(), {:stdout, os_pid, "Log Info "})
      send(self(), {:stdout, os_pid, "Hello"})
      send_exit()
      ProtocolHandler.wait_for_complete(os_pid, "testmonitor", self())
      assert_received {:"$gen_cast", {:message, "Log Info Hello"}}
    end

    test "Mixed messages get split and sent to genserver" do
      os_pid = 42
      send(self(), {:stdout, os_pid, "00014 Log Info Hello00015 Log Error Error"})
      send_exit()
      ProtocolHandler.wait_for_complete(os_pid, "testmonitor", self())
      assert_received {:"$gen_cast", {:message, "Log Info Hello"}}
      assert_received {:"$gen_cast", {:message, "Log Error Error"}}
    end
  end

  describe "Handshake" do
    test "Basic handshake works" do
      fake_os_pid = self()

      writer = fn os_pid, msg -> send(self(), {:write, os_pid, msg}) end

      # We don't strictly need to interleave all the messages, so we fill the
      # queue with what the handshake expects, run the handshake, then test
      # whether the output is correct.

      send(self(), {:stdout, fake_os_pid, "00011 Started 1.1"})
      send(self(), {:stdout, fake_os_pid, "00005 Ready"})

      ProtocolHandler.handle_handshake(
        fake_os_pid,
        %{
          monitor_logical_name: "testmonitor",
          extra_config: %{test: "value", more: 42}
        },
        writer
      )

      assert_received {:write, ^fake_os_pid, "Version 1.1"}
      assert_received {:write, ^fake_os_pid, ~s(Config {"more":42,"test":"value"})}
    end
  end

  describe "Stepping" do
    test "If no more steps are available, monitor is asked to exit" do
      state = %ProtocolHandler.State{steps: [], owner: self()}
      {:noreply, new_state} = ProtocolHandler.handle_info(:start_step, state)
      assert state == new_state
      assert_received {:write, "Exit 0"}
    end

    test "If a step is available, monitor is asked to run step" do
      state = %ProtocolHandler.State{
        steps: [
          %{check_logical_name: "StepOne", timeout_secs: 60},
          %{check_logical_name: "StepTwo", timeout_secs: 60}
        ],
        owner: self()
      }

      {:noreply, new_state} = ProtocolHandler.handle_info(:start_step, state)

      assert new_state.steps == [%{check_logical_name: "StepTwo", timeout_secs: 60}]
      assert new_state.current_step == %{check_logical_name: "StepOne", timeout_secs: 60}
      refute is_nil(new_state.step_timeout_timer)
      assert_received {:write, "Run Step StepOne"}
    end

    test "Step timeout results in error and monitor exit" do
      state = %ProtocolHandler.State{
        monitor_logical_name: "testmonitor",
        steps: [
          %{check_logical_name: "StepTwo", timeout_secs: 60}
        ],
        current_step: %{check_logical_name: "StepOne", timeout_secs: 60},
        owner: self(),
        error_report_fun: fn m, c, msg, opts -> send(self(), {:error, m, c, msg, opts}) end
      }

      {:stop, :normal, _new_state} = ProtocolHandler.handle_info(:step_timeout, state)

      assert_received {:write, "Exit 0"}

      assert_received {:error, "testmonitor", "StepOne",
                       "Timeout: check did not complete within 60 seconds - METRIST_MONITOR_ERROR",
                       metadata: %{"metrist.source" => "monitor"}, blocked_steps: ["StepTwo"]}
    end
  end

  describe "Metadata handling in monitor results" do
    defp mkstate do
      %ProtocolHandler.State{
        step_start_time: 0,
        monitor_logical_name: "mon",
        current_step: %{
          check_logical_name: "check"
        },
        step_timeout_timer: nil,
        telemetry_report_fun: fn m, c, t, meta -> send(self(), {:telemetry, m, c, t, meta}) end,
        error_report_fun: fn m, c, e, meta -> send(self(), {:error, m, c, e, meta}) end,
        owner: self()
      }
    end

    test "Metadata is handled correctly for orchestrator-timed steps" do
      state = mkstate()

      ProtocolHandler.handle_cast({:message, "Step OK"}, state)
      assert_received {:telemetry, "mon", "check", _, [metadata: %{}]}

      ProtocolHandler.handle_cast({:message, "Step OK key1=value1"}, state)
      assert_received {:telemetry, "mon", "check", _, [metadata: %{"key1" => "value1"}]}
    end

    test "Metadata is handled correctly for monitor-timed steps" do
      state = mkstate()

      ProtocolHandler.handle_cast({:message, "Step Time 12.34"}, state)
      assert_received {:telemetry, "mon", "check", 12.34, [metadata: %{}]}

      ProtocolHandler.handle_cast({:message, "Step Time key1=value1,key2=3432 12.34"}, state)

      assert_received {:telemetry, "mon", "check", 12.34,
                       [metadata: %{"key1" => "value1", "key2" => 42.0}]}
    end

    test "Metadata is handled correctly for errored steps" do
      state = mkstate()

      capture_log(fn ->
        ProtocolHandler.handle_cast({:message, "Step Error The cake is a lie"}, state)

        assert_received {:error, "mon", "check", "The cake is a lie",
                         [metadata: %{}, blocked_steps: _]}

        ProtocolHandler.handle_cast(
          {:message, "Step Error key=value The cake really is a lie"},
          state
        )

        assert_received {:error, "mon", "check", "The cake really is a lie",
                         [metadata: %{"key" => "value"}, blocked_steps: _]}

        ProtocolHandler.handle_cast(
          {:message, "Step Error key=value,candle The cake still is a lie"},
          state
        )

        assert_received {:error, "mon", "check", "key=value,candle The cake still is a lie",
                         [metadata: %{}, blocked_steps: _]}
      end)
    end
  end

  describe "Parsing metadata conforms to protocol" do
    import Orchestrator.ProtocolHandler, only: [parse_metadata: 1]

    test "Empty or nil string parses to empty map" do
      assert %{} == parse_metadata("")
      assert %{} == parse_metadata(" ")
      assert %{} == parse_metadata(nil)
    end

    test "Garbage is ignored but logs a warning" do
      log =
        capture_log(fn ->
          assert %{} = parse_metadata("garbage")
        end)

      assert String.contains?(log, "Could not parse as metadata: 'garbage', ignoring")
      # It can be "warn" or "warning", so be lenient.
      assert String.contains?(log, "[warn")
    end

    test "Basic single value works" do
      assert %{"key" => "value"} == parse_metadata("key=value")

      assert %{"key1" => "value1", "key2" => "value2"} ==
               parse_metadata("key1=value1,key2=value2")
    end

    test "Base16 decode works" do
      assert %{"key" => "value"} == parse_metadata("key=76616C7565")
      assert %{"key" => 1.0} == parse_metadata("key=312E30")
    end

    test "Base16 decode is case-insensitive" do
      assert %{"key" => "value"} == parse_metadata("key=76616c7565")
    end

    test "Numbers do not need to be encoded if they don't look like base16 strings" do
      assert %{"key" => 1.0} == parse_metadata("key=1.0")
    end

    test "Like in JSON, there is no difference between integers and floats" do
      assert %{"key" => 1.0} == parse_metadata("key=1")
    end
  end
end
