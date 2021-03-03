defmodule Goth.Mixfile do
  use Mix.Project

  def project do
    [
      app: :goth,
      version: "1.3.0-dev",
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.10",
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Goth.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jose, "~> 1.10"},
      {:jason, "~> 1.1"},
      {:hackney, "~> 1.0", optional: true},
      {:bypass, "~> 2.1", only: :test},
      {:mix_test_watch, "~> 0.2", only: :dev},
      {:ex_doc, "~> 0.19", only: :dev},
      {:credo, "~> 0.8", only: [:test, :dev]},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false}
    ]
  end

  defp description do
    """
    A simple library to generate and retrieve Oauth2 tokens for use with Google Cloud Service accounts.
    """
  end

  defp package do
    [
      maintainers: ["Phil Burrows"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/peburrows/goth"}
    ]
  end
end
