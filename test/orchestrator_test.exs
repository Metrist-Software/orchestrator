defmodule OrchestratorTest do
  use ExUnit.Case
  doctest Orchestrator

  test "greets the world" do
    assert Orchestrator.hello() == :world
  end
end
