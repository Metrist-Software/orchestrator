defmodule Orchestrator.ProtocolHandlerTest do
  use ExUnit.Case, async: true
  require Logger

  alias Orchestrator.ProtocolHandler

  test "Incomplete single message returns {:incomplete, message}" do
    {result, _message} = ProtocolHandler.handle_message(self(), "testmonitor", "00041 Log Info Created card 6102e3cd")
    assert result == :incomplete
  end

  test "Multiple messages where last is incomplete returns last message and :incomplete message returns {:incomplete, message}" do
    {result, message} = ProtocolHandler.handle_message(self(), "testmonitor", "00041 Log Info Created card 6102e3cde5a2f61a44700041 Log Second Created")
    assert result == :incomplete
    assert message == "00041 Log Second Created"
    assert_received {:"$gen_cast", {:message, "Log Info Created card 6102e3cde5a2f61a447"}}
  end

  test "Multiple complete messages will succeed with {:ok, nil}" do
    {result, message} = ProtocolHandler.handle_message(self(), "testmonitor", "00041 Log Info Created card 6102e3cde5a2f61a44700041 Log Info Create card 6102e3cde5a2f61a4478")
    assert result == :ok
    assert message == :nil
    assert_received {:"$gen_cast", {:message, "Log Info Created card 6102e3cde5a2f61a447"}}
    assert_received {:"$gen_cast", {:message, "Log Info Create card 6102e3cde5a2f61a4478"}}
  end

  test "Empty log message works" do
    result = ProtocolHandler.handle_message(self(), "testmonitor", "00010 Log Debug ")
    assert {:ok, :nil} == result
  end

  test "Messages must have at least 5 positions worth of length before we start parsing" do
    {result, message} = ProtocolHandler.handle_message(self(), "testmonitor", "000")
    assert result == :incomplete
    assert message == "000"

    {result, message} = ProtocolHandler.handle_message(self(), "testmonitor", "0000")
    assert result == :incomplete
    assert message == "0000"

    {result, message} = ProtocolHandler.handle_message(self(), "testmonitor", "00000")
    assert result == :ok
    assert message == :nil
    assert_received {:"$gen_cast", {:message, ""}}
  end
end
