defmodule AbsintheRelay.Mixfile do
  use Mix.Project

  @version "1.5.1"

  def project do
    [
      app: :absinthe_relay,
      version: @version,
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      package: package(),
      docs: docs(),
      deps: deps(),
      xref: [
        exclude: [:ecto]
      ]
    ]
  end

  defp package do
    [
      description: "Relay framework support for Absinthe",
      files: ["lib", "mix.exs", "README*"],
      maintainers: ["Bruce Williams", "Ben Wilson"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/absinthe-graphql/absinthe_relay"}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "Absinthe.Relay",
      source_url: "https://github.com/absinthe-graphql/absinthe_relay"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:absinthe, "~> 1.5.0 or ~> 1.6.0"},
      {:ecto, "~> 2.0 or ~> 3.0", optional: true},
      {:paginator,
        github: "duffelhq/paginator",
        branch: "master",
        optional: true},
      {:poison, ">= 0.0.0", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end
end
