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
    Logger.debug(message)
    assert result == :incomplete
    assert message == "00041 Log Second Created"
  end

  test "Multiple complete messages will succeed with {:ok, nil}" do
    {result, message} = ProtocolHandler.handle_message(self(), "testmonitor", "00041 Log Info Created card 6102e3cde5a2f61a44700041 Log Info Create card 6102e3cde5a2f61a4478")
    assert result == :ok
    assert message == :nil
  end

  test "Single complete message with leading/trailing zero's will succeed with {:ok, nil}" do
    {result, message} = ProtocolHandler.handle_message(self(), "testmonitor", " 00041 Log Info Created card 6102e3cde5a2f61a447 ")
    assert result == :ok
    assert message == :nil
  end
end
