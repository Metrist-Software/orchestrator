defmodule Orchestrator.ProtocolHandlerTest do
  use ExUnit.Case, async: true
  require Logger
  import ExUnit.CaptureLog

  alias Orchestrator.ProtocolHandler

  test "Incomplete single message returns {:incomplete, message}" do
    {result, _message} = ProtocolHandler.handle_message(self(), "testmonitor", "00041 Log Info Created card 6102e3cd")
    assert result == :incomplete
  end

  test "Multiple messages where last is incomplete returns last message and :incomplete message returns {:incomplete, message}" do
    {result, message} = ProtocolHandler.handle_message(self(), "testmonitor", "00041 Log Info Created card 6102e3cde5a2f61a44700041 Log Second Created")
    assert result == :incomplete
    assert message == "00041 Log Second Created"
  end

  test "Multiple complete messages will succeed with {:ok, nil}" do
    {result, message} = ProtocolHandler.handle_message(self(), "testmonitor", "00041 Log Info Created card 6102e3cde5a2f61a44700041 Log Info Create card 6102e3cde5a2f61a4478")
    assert result == :ok
    assert message == :nil
  end

  test "Empty log message works" do
    result = ProtocolHandler.handle_message(self(), "testmonitor", "00010 Log Debug ")
    assert {:ok, :nil} == result
  end

  describe "Metadata handling in monitor results" do
    defp mkstate do
      %ProtocolHandler.State{
        step_start_time: 0,
        monitor_logical_name: "mon",
        current_step: %{
          check_logical_name: "check",
        },
        step_timeout_timer: nil,
        telemetry_report_fun: fn m, c, t, meta -> send self(), {:telemetry, m, c, t, meta} end,
        error_report_fun: fn m, c, e, meta -> send self(), {:error, m, c, e, meta} end,
        io_handler: self()
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
      assert_received {:telemetry, "mon", "check", 12.34, [metadata: %{"key1" => "value1", "key2" => 42.0}]}
    end

    test "Metadata is handled correctly for errored steps" do
      state = mkstate()
      capture_log(fn ->

        ProtocolHandler.handle_cast({:message, "Step Error The cake is a lie"}, state)
        assert_received {:error, "mon", "check", "The cake is a lie", [metadata: %{}, blocked_steps: _]}

        ProtocolHandler.handle_cast({:message, "Step Error key=value The cake really is a lie"}, state)
        assert_received {:error, "mon", "check", "The cake really is a lie", [metadata: %{"key" => "value"}, blocked_steps: _]}

        ProtocolHandler.handle_cast({:message, "Step Error key=value,candle The cake still is a lie"}, state)
        assert_received {:error, "mon", "check", "key=value,candle The cake still is a lie", [metadata: %{}, blocked_steps: _]}
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
      log = capture_log(fn ->
        assert %{} = parse_metadata("garbage")
      end)
      assert String.contains?(log, "Could not parse as metadata: 'garbage', ignoring")
      assert String.contains?(log, "[warn") # It can be "warn" or "warning", so be lenient.
    end

    test "Basic single value works" do
      assert %{"key" => "value"} == parse_metadata("key=value")
      assert %{"key1" => "value1", "key2" => "value2"} == parse_metadata("key1=value1,key2=value2")
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
