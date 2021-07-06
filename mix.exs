defmodule Flex.MixProject do
  use Mix.Project

  def project do
    [
      app: :flex,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: []

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tesla, "~> 1.4.1"},
      {:jason, "~> 1.2"},
      {:mint, "~> 1.0"},
      {:composex, git: "https://git.keepinmind.info/extra/composex.git", tag: "v0.1.3"}
    ]
  end
end
