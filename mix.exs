defmodule Kokoro.MixProject do
  use Mix.Project

  def project do
    [
      app: :kokoro,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ortex, "~> 0.1.10"},
      {:nx, "~> 0.9.2"}
    ]
  end
end
