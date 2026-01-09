defmodule Flex.MixProject do
  use Mix.Project

  def project do
    [
      app: :flex,
      version: "1.0.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Flex",
      source_url: "https://github.com/kim-company/flex"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: []

  defp description do
    "A high-level Elixir library for managing AWS ECS Fargate and managed instance tasks with support for running, monitoring, and controlling containerized workloads."
  end

  defp package do
    [
      maintainers: ["KIM Keep In Mind GmbH"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/kim-company/flex"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:aws, "~> 1.0.9"}
    ]
  end
end
