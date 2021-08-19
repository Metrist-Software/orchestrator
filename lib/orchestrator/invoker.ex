defmodule Orchestrator.Invoker do
  @moduledoc """
  Behaviour definition for modules that can act as a monitor invoker.
  """

  @doc """
  Invoke the monitor. `config` is the monitor configuration as stored server-side, and `region` is the
  region (or instance, host, ...) we are running in. Must return a task, `Orchestrator.MonitorScheduler`
  will then have its hands free to keep an eye on the clock, etcetera.
  """
  @callback invoke(config :: map(), opts :: []) :: Task.t()
end
