defmodule Goth.Mixfile do
  use Mix.Project

  @version "1.4.5"
  @source_url "https://github.com/peburrows/goth"

  def project do
    [
      app: :goth,
      version: @version,
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.13",
      source_url: @source_url,
      name: "Goth",
      description: description(),
      docs: docs(),
      deps: deps(),
      aliases: aliases(),
      preferred_cli_env: [
        "test.all": :test
      ]
    ]
  end

  def application do
    [
      mod: {Goth.Application, []},
      extra_applications: [:logger]
    ]
  end

  def aliases do
    ["test.all": ["test --include integration"]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jose, "~> 1.11"},
      {:jason, "~> 1.1"},
      {:finch, "~> 0.17"},
      {:castore, "~> 1.0", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:ex_doc, "~> 0.19", only: :dev},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      extras: [
        "CHANGELOG.md",
        "README.md",
        "UPGRADE_GUIDE.md",
        "LICENSE.md"
      ],
      formatters: ["html"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
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
      links: %{
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md",
        "GitHub" => @source_url
      }
    ]
  end
end
