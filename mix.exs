defmodule UblEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Octarion/ubl_ex"

  def project do
    [
      app: :ubl_ex,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "UblEx",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:sweet_xml, "~> 0.7"},
      {:decimal, "~> 2.0"},
      {:phoenix_html, "~> 4.0"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    UBL (Universal Business Language) document generation and parsing for Elixir.
    Supports Peppol BIS Billing 3.0 compliant invoices, credit notes, and application responses with SBDH support.
    """
  end

  defp package do
    [
      name: "ubl_ex",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "UblEx",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        Generators: [
          UblEx.Generator.Invoice,
          UblEx.Generator.CreditNote,
          UblEx.Generator.ApplicationResponse,
          UblEx.Generator.SBDH,
          UblEx.Generator.Helpers
        ],
        Parsers: [
          UblEx.Parser.Parser,
          UblEx.Parser.SchemaRegistry,
          UblEx.Parser.Importer
        ]
      ]
    ]
  end
end
