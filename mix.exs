defmodule RPG.MixProject do
  use Mix.Project

  def project do
    [
      app: :rpg_bot,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {RPG.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dotenv_parser, "~> 1.2", only: [:dev, :test]},
      {:phoenix_pubsub, "~> 2.0"},
      {:polyjuice_client, "~> 0.4.4"},
      {:earmark, "~> 1.4"}
    ]
  end
end
