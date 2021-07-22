defmodule Orchestrator.SecretsSource do
  @moduledoc """
  Behaviour definition for modules that can act as a source of secrets.
  """

  @doc """
  Fetch a secret. The name of the secret and how it is interpreted is implementation-specific.
  """
  @callback fetch(name :: String.t()) :: String.t()
end
