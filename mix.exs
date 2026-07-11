defmodule Quickbase.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mattijevi/quickbase"

  def project do
    [
      app: :quickbase,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir client for the Quickbase JSON RESTful API",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      dialyzer: [plt_core_path: "priv/plts", plt_local_path: "priv/plts"]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:plug, "~> 1.15", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Quickbase API" => "https://developer.quickbase.com/"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
