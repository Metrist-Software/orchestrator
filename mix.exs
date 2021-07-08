defmodule Orchestrator.MixProject do
  use Mix.Project

  def project do
    [
      app: :orchestrator,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        orchestrator: [
          steps: [:assemble, &Bakeware.assemble/1]
        ]
      ]
    ]
  end

  def application do
    [
      mod: {Orchestrator.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Generic dependencies
      {:jason, "~> 1.2"},
      {:bakeware, "~> 0.2.0"},

      # Canary Orchestrator specific dependencies (for now)
      {:neuron, "~> 5.0"},         # Until(?) we ditch GraphQL
      {:ex_aws_lambda, "~> 2.0"},
      {:ex_aws_secretsmanager, "~> 2.0"}
    ]
  end
end
