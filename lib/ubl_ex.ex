defmodule UblEx do
  @moduledoc """
  UBL (Universal Business Language) document generation and parsing for Elixir.

  This library provides:
  - Peppol BIS Billing 3.0 compliant invoice, credit note, and application response generation
  - SBDH (Standard Business Document Header) support for Peppol network transmission
  - Fast SAX-based XML parsing using Saxy (1.4-4x faster than xmerl)
  - Full round-trip support (parse → generate → parse without data loss)

  ## Quick Start

  ### Generating a UBL Invoice

      document_data = %{
        type: :invoice,
        number: "F2024001",
        date: ~D[2024-01-15],
        expires: ~D[2024-02-14],
        supplier: %{
          endpoint_id: "0797948229",
          scheme: "0208",
          name: "Company Name",
          street: "Street 40",
          city: "City",
          zipcode: "2180",
          country: "BE",
          vat: "BE0797948229",
          email: "invoice@company.com"
        },
        customer: %{
          endpoint_id: "0012345625",
          scheme: "0208",
          name: "Customer Name",
          vat: "BE0012345625",
          street: "Customer Street",
          housenumber: "10",
          city: "Brussels",
          zipcode: "1000",
          country: "BE"
        },
        details: [
          %{
            name: "Service",
            quantity: Decimal.new("1.00"),
            price: Decimal.new("100.00"),
            vat: Decimal.new("21.00"),
            discount: Decimal.new("0.00")
          }
        ]
      }

      xml = UblEx.generate(document_data)

  ### Parsing a UBL Document

      {:ok, parsed} = UblEx.parse(xml_content)

      # Document type is in the data
      case parsed.type do
        :invoice -> handle_invoice(parsed)
        :credit -> handle_credit_note(parsed)
        :application_response -> handle_response(parsed)
      end

  ## Tax Categories

  Line items support all Peppol BIS 3.0 tax categories via the optional `tax_category` field:

  | Atom | Peppol Code | Use Case |
  |------|-------------|----------|
  | `:standard` | S | Standard rated VAT (default for 6/12/21%) |
  | `:zero_rated` | Z | Zero rated goods (default for 0% VAT) |
  | `:exempt` | E | Exempt from tax |
  | `:reverse_charge` | AE | Domestic reverse charge |
  | `:intra_community` | K | EU cross-border B2B (intra-community supply) |
  | `:export` | G | Export outside EU |
  | `:outside_scope` | O | Services outside scope of tax |

  If `tax_category` is not specified, it defaults to `:standard` for non-zero VAT
  and `:zero_rated` for 0% VAT.

  ### Example with Tax Categories

      details: [
        %{
          name: "Standard Service",
          quantity: Decimal.new("1.00"),
          price: Decimal.new("100.00"),
          vat: Decimal.new("21.00"),
          discount: Decimal.new("0.00")
          # tax_category defaults to :standard
        },
        %{
          name: "EU Cross-Border Service",
          quantity: Decimal.new("1.00"),
          price: Decimal.new("500.00"),
          vat: Decimal.new("0.00"),
          discount: Decimal.new("0.00"),
          tax_category: :intra_community
        }
      ]

  ## Usage Pattern

  Parse documents and handle them in your own code:

      {:ok, parsed} = UblEx.parse(xml)
      MyApp.save_invoice(parsed)
      MyApp.send_notification(parsed)
  """

  alias UblEx.Parser
  alias UblEx.Generator.{Invoice, CreditNote, ApplicationResponse, SBDH}

  @doc """
  Parse UBL XML with automatic schema detection.

  Returns `{:ok, parsed_data}` or `{:error, reason}`.

  The document type is available in `parsed_data.type` (`:invoice`, `:credit`, or `:application_response`).

  ## Example

      {:ok, parsed} = UblEx.parse(xml_content)
      IO.inspect(parsed.type)  # :invoice, :credit, or :application_response
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(xml_content) do
    Parser.SimpleParser.parse(xml_content)
  end

  @doc """
  Generate a Peppol-compliant UBL document based on the type field.

  Routes to the appropriate generator based on `document_data.type`:
  - `:invoice` → Invoice generator
  - `:credit` → CreditNote generator
  - `:application_response` → ApplicationResponse generator

  ## Examples

      # Parse and regenerate
      {:ok, parsed} = UblEx.parse(xml)
      regenerated_xml = UblEx.generate(parsed)

      # Generate invoice
      document_data = %{type: :invoice, number: "F001", ...}
      xml = UblEx.generate(document_data)

      # Generate application response
      response_data = %{type: :application_response, id: "RESP-001", ...}
      xml = UblEx.generate(response_data)
  """
  @spec generate(map()) :: String.t() | {:error, String.t()}
  def generate(%{type: :invoice} = document_data) do
    Invoice.generate(document_data)
  end

  def generate(%{type: :credit} = document_data) do
    CreditNote.generate(document_data)
  end

  def generate(%{type: :application_response} = document_data) do
    ApplicationResponse.generate(document_data)
  end

  def generate(%{type: type}) do
    {:error,
     "Unknown document type: #{inspect(type)}. Expected :invoice, :credit, or :application_response"}
  end

  def generate(_document_data) do
    {:error,
     "Missing :type field in document_data. Expected :invoice, :credit, or :application_response"}
  end

  @doc """
  Generate a UBL document wrapped in SBDH (Standard Business Document Header).

  SBDH is used in Peppol networks for routing and identification. This function
  generates the standard UBL document and wraps it with the SBDH header.

  ## Example

      document_data = %{type: :invoice, number: "F001", ...}
      sbdh_xml = UblEx.generate_with_sbdh(document_data)
  """
  @spec generate_with_sbdh(map()) :: String.t() | {:error, String.t()}
  def generate_with_sbdh(document_data) do
    case generate(document_data) do
      {:error, _} = error -> error
      ubl_xml -> SBDH.wrap(ubl_xml, document_data)
    end
  end
end
