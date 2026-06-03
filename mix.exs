defmodule CartEngine.MixProject do
  use Mix.Project

  def project do
    [
      app: :cart_engine,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CartEngine.Application, []}
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.38.0", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.3", only: :dev},
      {:libcluster, "~> 3.4"},
      {:horde, "~> 0.10.0"}
    ]
  end
end
