defmodule Goth.Mixfile do
  use Mix.Project

  def project do
    [app: :goth,
     version: "0.2.1",
     description: description,
     package: package,
     elixir: "~> 1.2",
     deps: deps]
  end

  def application do
    [
      mod: {Goth, []},
      applications: [:json_web_token, :logger, :httpoison]
    ]
  end

  defp deps do
    [{:json_web_token, "~> 0.2.5"},
     {:httpoison, "~> 0.9.0"},
     {:poison, "~> 2.1"},
     {:bypass, "~> 0.1", only: :test},
     {:mix_test_watch, "~> 0.2", only: :dev},
     {:ex_doc, "~> 0.11.3", only: [:dev]},
     {:earmark, "~> 0.2", only: [:dev]},
     {:credo, "~> 0.4", only: [:test, :dev]}
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
