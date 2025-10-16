defmodule UblEx.Parser.SchemaRegistry do
  @moduledoc """
  Registry for XML schema configurations with round-trip support.

  This module provides schema definitions that enable full round-trip parsing,
  meaning the parser output matches the generator input format exactly.
  """

  use UblEx.Parser.SweetXmlCompat
  alias UblEx.Parser.Parser

  @type schema_id :: atom()
  @type schema_config :: Parser.schema_config()

  defp schemas do
    %{
      ubl_peppol: %{
        document_type_selector: ~x"local-name(/*)"s,
        document_types: %{
          "Invoice" => %{
            type: %{transform: fn _ -> :invoice end},
            number: %{path: ~x"./cbc:ID/text()"s, transform: &__MODULE__.parse_document_id/1},
            date: %{path: ~x"//cbc:IssueDate/text()"s, transform: &__MODULE__.parse_date/1},
            expires: %{path: ~x"//cbc:DueDate/text()"s, transform: &__MODULE__.parse_date/1},
            order_reference: %{path: ~x"//cac:OrderReference/cbc:ID/text()"s},
            billing_references: %{
              path: ~x"//cac:BillingReference/cac:InvoiceDocumentReference/cbc:ID/text()"sl,
              transform: &__MODULE__.parse_billing_references/1
            },
            reverse_charge: %{
              path: ~x"//cac:TaxCategory/cbc:ID/text()"s,
              transform: &__MODULE__.detect_intra/1
            },
            supplier: %{
              path: ~x"//cac:AccountingSupplierParty/cac:Party",
              transform: &__MODULE__.extract_supplier/1
            },
            customer: %{
              path: ~x"//cac:AccountingCustomerParty/cac:Party",
              transform: &__MODULE__.extract_customer/1
            },
            details: %{
              path: ~x"//cac:InvoiceLine"l,
              transform: &__MODULE__.extract_invoice_lines/1
            },
            attachments: %{
              path: ~x"//cac:AdditionalDocumentReference[cac:Attachment]"l,
              transform: &__MODULE__.extract_attachments/1
            }
          },
          "CreditNote" => %{
            type: %{transform: fn _ -> :credit end},
            number: %{path: ~x"./cbc:ID/text()"s, transform: &__MODULE__.parse_document_id/1},
            date: %{path: ~x"//cbc:IssueDate/text()"s, transform: &__MODULE__.parse_date/1},
            expires: %{path: ~x"//cbc:DueDate/text()"s, transform: &__MODULE__.parse_date/1},
            order_reference: %{path: ~x"//cac:OrderReference/cbc:ID/text()"s},
            billing_references: %{
              path: ~x"//cac:BillingReference/cac:InvoiceDocumentReference/cbc:ID/text()"sl,
              transform: &__MODULE__.parse_billing_references/1
            },
            reverse_charge: %{
              path: ~x"//cac:TaxCategory/cbc:ID/text()"s,
              transform: &__MODULE__.detect_intra/1
            },
            supplier: %{
              path: ~x"//cac:AccountingSupplierParty/cac:Party",
              transform: &__MODULE__.extract_supplier/1
            },
            customer: %{
              path: ~x"//cac:AccountingCustomerParty/cac:Party",
              transform: &__MODULE__.extract_customer/1
            },
            details: %{
              path: ~x"//cac:CreditNoteLine"l,
              transform: &__MODULE__.extract_credit_note_lines/1
            },
            attachments: %{
              path: ~x"//cac:AdditionalDocumentReference[cac:Attachment]"l,
              transform: &__MODULE__.extract_attachments/1
            }
          },
          "ApplicationResponse" => %{
            type: %{transform: fn _ -> :application_response end},
            id: %{path: ~x"./cbc:ID/text()"s},
            date: %{path: ~x"./cbc:IssueDate/text()"s, transform: &__MODULE__.parse_date/1},
            response_code: %{path: ~x"//cbc:ResponseCode/text()"s},
            status_reason: %{path: ~x"//cbc:StatusReason/text()"s},
            document_reference: %{
              path: ~x"//cac:DocumentReference/cbc:ID/text()"s,
              transform: &__MODULE__.parse_document_id/1
            },
            note: %{path: ~x"//cbc:Note/text()"s},
            sender: %{
              path: ~x"//cac:SenderParty",
              transform: &__MODULE__.extract_response_party/1
            },
            receiver: %{
              path: ~x"//cac:ReceiverParty",
              transform: &__MODULE__.extract_response_party/1
            }
          },
          "StandardBusinessDocument" => %{
            delegate_to_inner: true
          }
        },
        party_extraction: %{
          supplier: %{
            base_path: ~x"//cac:AccountingSupplierParty/cac:Party",
            fields: %{
              endpoint: %{path: ~x"./cbc:EndpointID/text()"s},
              scheme: %{path: ~x"./cbc:EndpointID/@schemeID"s},
              name: %{path: ~x"./cac:PartyName/cbc:Name/text()"s},
              street: %{path: ~x"./cac:PostalAddress/cbc:StreetName/text()"s},
              city: %{path: ~x"./cac:PostalAddress/cbc:CityName/text()"s},
              zipcode: %{path: ~x"./cac:PostalAddress/cbc:PostalZone/text()"s},
              country: %{path: ~x"//cbc:IdentificationCode/text()"s},
              vat: %{path: ~x"./cac:PartyTaxScheme/cbc:CompanyID/text()"s},
              email: %{path: ~x"//cbc:ElectronicMail/text()"s}
            }
          },
          customer: %{
            base_path: ~x"//cac:AccountingCustomerParty/cac:Party",
            fields: %{
              name: %{path: ~x"./cac:PartyName/cbc:Name/text()"s},
              street: %{path: ~x"./cac:PostalAddress/cbc:StreetName/text()"s},
              city: %{path: ~x"./cac:PostalAddress/cbc:CityName/text()"s},
              zipcode: %{path: ~x"./cac:PostalAddress/cbc:PostalZone/text()"s},
              vat: %{path: ~x"./cac:PartyTaxScheme/cbc:CompanyID/text()"s}
            }
          }
        },
        namespaces: %{
          cbc: "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2",
          cac: "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
        }
      }
    }
  end

  @doc """
  Get a schema configuration by ID.
  """
  @spec get_schema(schema_id()) :: {:ok, schema_config()} | {:error, :not_found}
  def get_schema(schema_id) when is_atom(schema_id) do
    case Map.get(schemas(), schema_id) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema}
    end
  end

  @doc """
  Register a new schema configuration.
  """
  @spec register_schema(schema_id(), schema_config()) :: :ok
  def register_schema(schema_id, schema_config) when is_atom(schema_id) do
    Process.put({:xml_schema, schema_id}, schema_config)
    :ok
  end

  @doc """
  Get all available schema IDs.
  """
  @spec list_schemas() :: [schema_id()]
  def list_schemas do
    Map.keys(schemas()) ++
      (Process.get_keys()
       |> Enum.filter(&match?({:xml_schema, _}, &1))
       |> Enum.map(fn {:xml_schema, id} -> id end))
  end

  @doc """
  Check if a schema exists.
  """
  @spec schema_exists?(schema_id()) :: boolean()
  def schema_exists?(schema_id) do
    Map.has_key?(schemas(), schema_id) ||
      Process.get({:xml_schema, schema_id}) != nil
  end

  @doc """
  Auto-detect the best schema for a given XML document.
  """
  @spec auto_detect_schema(String.t()) :: {:ok, schema_id()} | {:error, :no_matching_schema}
  def auto_detect_schema(xml_content) do
    schemas_to_try = list_schemas()

    Enum.find_value(schemas_to_try, {:error, :no_matching_schema}, fn schema_id ->
      with {:ok, schema} <- get_schema(schema_id),
           {:ok, _doc_type} <- Parser.get_document_type(xml_content, schema),
           true <- has_parseable_content?(xml_content, schema) do
        {:ok, schema_id}
      else
        _ -> nil
      end
    end)
  end

  @doc """
  Parse document ID, removing V01/ prefix.
  """
  def parse_document_id(id) when is_number(id), do: to_string(id)

  def parse_document_id(id) when is_binary(id) do
    id
    |> String.split("/", trim: true)
    |> List.last()
  end

  def parse_document_id(id), do: to_string(id)

  @doc """
  Parse ISO date string to Date struct.
  """
  def parse_date(date_string) when is_binary(date_string) and date_string != "" do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  def parse_date(_), do: nil

  @doc """
  Parse list of billing reference IDs.
  """
  def parse_billing_references(refs) when is_list(refs) do
    Enum.map(refs, &parse_document_id/1)
  end

  def parse_billing_references(_), do: []

  @doc """
  Detect reverse charge from tax category ID.
  Tax category "K" indicates intra-community reverse charge.
  """
  def detect_intra("K"), do: true
  def detect_intra(_), do: false

  @doc """
  Map SBDH document type to keep for debugging.
  """
  def map_sbdh_document_type("Invoice"), do: "Invoice"
  def map_sbdh_document_type("CreditNote"), do: "CreditNote"
  def map_sbdh_document_type("ApplicationResponse"), do: "ApplicationResponse"
  def map_sbdh_document_type(other), do: other

  @doc """
  Map document type string to atom for type field.
  """
  def map_document_type_to_atom("Invoice"), do: :invoice
  def map_document_type_to_atom("CreditNote"), do: :credit
  def map_document_type_to_atom("ApplicationResponse"), do: :application_response
  def map_document_type_to_atom(_), do: :unknown

  @doc """
  Extract supplier information from party node.
  """
  def extract_supplier(nil), do: nil

  def extract_supplier(party_node) do
    %{
      endpoint_id: xpath(party_node, ~x"./cbc:EndpointID/text()"s),
      scheme: xpath(party_node, ~x"./cbc:EndpointID/@schemeID"s),
      name: xpath(party_node, ~x"./cac:PartyName/cbc:Name/text()"s),
      street: xpath(party_node, ~x"./cac:PostalAddress/cbc:StreetName/text()"s),
      city: xpath(party_node, ~x"./cac:PostalAddress/cbc:CityName/text()"s),
      zipcode: xpath(party_node, ~x"./cac:PostalAddress/cbc:PostalZone/text()"s),
      country: xpath(party_node, ~x".//cac:Country/cbc:IdentificationCode/text()"s),
      vat: xpath(party_node, ~x"./cac:PartyTaxScheme/cbc:CompanyID/text()"s),
      email: xpath(party_node, ~x".//cac:Contact/cbc:ElectronicMail/text()"s)
    }
    |> Enum.reject(fn {_k, v} -> v == nil or v == "" end)
    |> Enum.into(%{})
  end

  @doc """
  Extract customer information from party node.
  """
  def extract_customer(nil), do: nil

  def extract_customer(party_node) do
    street_full = xpath(party_node, ~x"./cac:PostalAddress/cbc:StreetName/text()"s)
    {street, housenumber} = parse_street_housenumber(street_full)

    %{
      name: xpath(party_node, ~x"./cac:PartyName/cbc:Name/text()"s),
      vat: xpath(party_node, ~x"./cac:PartyTaxScheme/cbc:CompanyID/text()"s),
      street: street,
      housenumber: housenumber,
      city: xpath(party_node, ~x"./cac:PostalAddress/cbc:CityName/text()"s),
      zipcode: xpath(party_node, ~x"./cac:PostalAddress/cbc:PostalZone/text()"s),
      country: xpath(party_node, ~x".//cac:Country/cbc:IdentificationCode/text()"s)
    }
    |> Enum.reject(fn {_k, v} -> v == nil or v == "" end)
    |> Enum.into(%{})
  end

  @doc """
  Extract invoice line items.
  """
  def extract_invoice_lines(nil), do: []
  def extract_invoice_lines([]), do: []

  def extract_invoice_lines(line_nodes) when is_list(line_nodes) do
    Enum.map(line_nodes, fn line ->
      quantity = xpath(line, ~x"./cbc:InvoicedQuantity/text()"f)
      price = xpath(line, ~x"./cac:Price/cbc:PriceAmount/text()"f)
      vat_percent = xpath(line, ~x".//cac:ClassifiedTaxCategory/cbc:Percent/text()"f)
      line_total = xpath(line, ~x"./cbc:LineExtensionAmount/text()"f)

      discount = calculate_discount(quantity, price, line_total)

      %{
        name: xpath(line, ~x"./cac:Item/cbc:Name/text()"s),
        quantity: safe_decimal(quantity),
        price: safe_decimal(price),
        vat: safe_decimal(vat_percent),
        discount: discount
      }
    end)
  end

  @doc """
  Extract credit note line items.
  """
  def extract_credit_note_lines(nil), do: []
  def extract_credit_note_lines([]), do: []

  def extract_credit_note_lines(line_nodes) when is_list(line_nodes) do
    Enum.map(line_nodes, fn line ->
      quantity = xpath(line, ~x"./cbc:CreditedQuantity/text()"f)
      price = xpath(line, ~x"./cac:Price/cbc:PriceAmount/text()"f)
      vat_percent = xpath(line, ~x".//cac:ClassifiedTaxCategory/cbc:Percent/text()"f)
      line_total = xpath(line, ~x"./cbc:LineExtensionAmount/text()"f)

      discount = calculate_discount(quantity, price, line_total)

      %{
        name: xpath(line, ~x"./cac:Item/cbc:Name/text()"s),
        quantity: safe_decimal(quantity),
        price: safe_decimal(price),
        vat: safe_decimal(vat_percent),
        discount: discount
      }
    end)
  end

  @doc """
  Extract attachments.
  """
  def extract_attachments(nil), do: []
  def extract_attachments([]), do: []

  def extract_attachments(attachment_nodes) when is_list(attachment_nodes) do
    Enum.map(attachment_nodes, fn node ->
      %{
        filename: xpath(node, ~x"./cbc:ID/text()"s),
        mime_type: xpath(node, ~x".//cbc:EmbeddedDocumentBinaryObject/@mimeCode"s),
        data: xpath(node, ~x".//cbc:EmbeddedDocumentBinaryObject/text()"s)
      }
    end)
    |> Enum.reject(fn attachment -> attachment.data == nil or attachment.data == "" end)
  end

  @doc """
  Extract party information from ApplicationResponse sender/receiver nodes.
  """
  def extract_response_party(nil), do: nil

  def extract_response_party(party_node) do
    %{
      endpoint_id: xpath(party_node, ~x"./cbc:EndpointID/text()"s),
      scheme: xpath(party_node, ~x"./cbc:EndpointID/@schemeID"s),
      name: xpath(party_node, ~x"./cac:PartyLegalEntity/cbc:RegistrationName/text()"s)
    }
    |> Enum.reject(fn {_k, v} -> v == nil or v == "" end)
    |> Enum.into(%{})
  end

  defp calculate_discount(quantity, price, line_total)
       when is_number(quantity) and is_number(price) and is_number(line_total) do
    base_amount = quantity * price

    if base_amount > line_total and base_amount > 0 do
      discount_amount = base_amount - line_total
      percentage = discount_amount / base_amount * 100
      Decimal.from_float(percentage) |> Decimal.round(2)
    else
      Decimal.new("0.00")
    end
  end

  defp calculate_discount(_, _, _), do: Decimal.new("0.00")

  defp parse_street_housenumber(nil), do: {"", ""}
  defp parse_street_housenumber(""), do: {"", ""}

  defp parse_street_housenumber(street_full) when is_binary(street_full) do
    case Regex.run(~r/^(.+?)\s+(\d+.*)$/, street_full) do
      [_, street, number] -> {street, number}
      _ -> {street_full, ""}
    end
  end

  defp safe_decimal(value) when is_number(value) do
    Decimal.from_float(value)
  end

  defp safe_decimal(_), do: Decimal.new("0.00")

  defp has_parseable_content?(xml_content, schema) do
    case schema.document_types do
      types when map_size(types) > 0 ->
        {_type, fields} = Enum.at(types, 0)

        case fields do
          fields when map_size(fields) > 0 ->
            {_field, spec} = Enum.at(fields, 0)
            xml_content |> xpath(spec.path)
            true

          _ ->
            true
        end

      _ ->
        true
    end
  rescue
    _ -> false
  end
end
