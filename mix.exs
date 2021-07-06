defmodule Flex.MixProject do
  use Mix.Project

  def project do
    [
      app: :flex,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers,
      make_targets: [
        "../priv/authorise",
        "../priv/sh/keygen",
      ],
      make_clean: ["clean"],
      make_cwd: "flexi",
      make_env: %{ "BINDIR" => "../priv" },
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
      {:composex, git: "https://git.keepinmind.info/extra/composex.git", tag: "v0.1.3"},
      {:elixir_make, "~> 0.4", runtime: false},
    ]
  end
end
