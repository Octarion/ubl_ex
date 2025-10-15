# UblEx

Parse and generate UBL (Universal Business Language) documents in Elixir with full round-trip support.

**Peppol BIS Billing 3.0 compliant** • **UBL 2.1** • **EN16931**

## Features

- **Parse** UBL Invoice, CreditNote, and ApplicationResponse XML documents
- **Generate** Peppol-compliant UBL XML
- **Round-trip support** - parse → generate → parse without data loss
- **Type-safe** - proper Elixir types (Date, Decimal, atoms)
- **Attachment support** - embed PDF files and other documents
- **Auto-detection** - automatically identify document types
- **Simple API** - no complex behaviours or callbacks

## Installation

Add `ubl_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ubl_ex, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Parsing a UBL Document

```elixir
# Simple parse with automatic schema detection
{:ok, parsed} = UblEx.parse(xml_content)

# Or be explicit about the schema
{:ok, parsed} = UblEx.parse_xml(xml_content, :ubl_peppol)

# Access the data
IO.puts("Document type: #{parsed.type}")        # :invoice, :credit, or :application_response
IO.puts("Invoice number: #{parsed.number}")
IO.puts("Supplier: #{parsed.supplier.name}")
IO.puts("Customer: #{parsed.customer.name}")
IO.puts("Total: #{length(parsed.details)} line items")
```

### Generating a UBL Invoice

```elixir
document_data = %{
  type: :invoice,
  number: "F2024001",
  date: ~D[2024-01-15],
  expires: ~D[2024-02-14],
  reverse_charge: false,

  supplier: %{
    endpoint_id: "0797948229",
    scheme: "0208",
    name: "My Company",
    street: "Main Street 123",
    city: "Brussels",
    zipcode: "1000",
    country: "BE",
    vat: "BE0797948229",
    email: "invoice@mycompany.com"
  },

  customer: %{
    endpoint_id: "0012345625",
    scheme: "0208",
    name: "Customer Corp",
    vat: "BE0012345625",
    street: "Customer Street",
    housenumber: "45",
    city: "Antwerp",
    zipcode: "2000",
    country: "BE"
  },

  details: [
    %{
      name: "Consulting Services - January 2024",
      quantity: Decimal.new("40.0"),
      price: Decimal.new("75.00"),
      vat: Decimal.new("21.00"),
      discount: Decimal.new("0.00")
    }
  ]
}

# Generate the XML
xml = UblEx.generate(document_data)
```

### Generating a Credit Note

```elixir
credit_note_data = %{
  type: :credit,
  number: "C2024001",
  date: ~D[2024-01-20],
  reverse_charge: false,

  # Reference original invoices
  billing_references: ["F2024001", "F2024002"],

  supplier: %{...},
  customer: %{...},
  details: [...]
}

xml = UblEx.generate(credit_note_data)
```

### Generating an Application Response

Application responses are used to acknowledge receipt and processing status of invoices:

```elixir
response_data = %{
  type: :application_response,
  id: "RESPONSE-001",
  date: ~D[2025-06-02],
  response_code: "AB",  # AB = Acknowledged, RE = Rejected
  document_reference: "INV-123",
  sender: %{
    endpoint_id: "0797948229",
    scheme: "0208",
    name: "My Company"
  },
  receiver: %{
    endpoint_id: "0844125969",
    scheme: "0208",
    name: "Supplier Inc"
  },
  status_reason: "Invoice approved",  # Optional
  note: "Payment scheduled"  # Optional
}

xml = UblEx.generate(response_data)
```

### Working with Attachments

```elixir
# Include PDF attachments (e.g., signed invoice)
document_data = %{
  type: :invoice,
  number: "F2024001",
  # ... other fields ...

  attachments: [
    %{
      filename: "F2024001.pdf",
      mime_type: "application/pdf",
      data: Base.encode64(pdf_binary)
    },
    %{
      filename: "terms.pdf",
      mime_type: "application/pdf",
      data: Base.encode64(terms_pdf)
    }
  ]
}

xml = UblEx.generate(document_data)

# Parse documents with attachments
{:ok, parsed} = UblEx.parse(xml)
parsed.attachments
# => [%{filename: "F2024001.pdf", mime_type: "application/pdf", data: "base64..."}]
```

### Generating SBDH-Wrapped Documents

For Peppol network transmission, wrap documents in a Standard Business Document Header (SBDH):

```elixir
# Same document data as before
document_data = %{
  type: :invoice,
  number: "F2024001",
  date: ~D[2024-01-15],
  # ... all other fields ...
}

# Generate with SBDH wrapper for Peppol network
sbdh_xml = UblEx.generate_with_sbdh(document_data)

# The SBDH includes routing information automatically derived from:
# - Supplier endpoint_id and scheme -> SBDH Sender
# - Customer VAT (if no endpoint_id) -> SBDH Receiver
# - Document type and customization -> SBDH Business Scope

# Parse SBDH-wrapped documents (automatically unwraps)
{:ok, parsed} = UblEx.parse(sbdh_xml)
# Returns the same data structure as parsing unwrapped UBL
```

## Document Structure

### Invoice and Credit Note Structure

```elixir
%{
  # Document metadata
  type: :invoice | :credit,
  number: "F2024001",
  date: ~D[2024-01-15],
  expires: ~D[2024-02-14],           # Invoices only
  reverse_charge: false,              # EU intra-community reverse charge
  order_reference: "PO-12345",
  billing_references: ["F001"],       # Credit notes only
  payment_id: "+++000/2024/00186+++", # Optional: Belgian structured payment reference

  # Supplier information
  supplier: %{
    endpoint_id: "0797948229",
    scheme: "0208",                   # Peppol scheme ID
    name: "Company Name",
    street: "Street 123",
    city: "City",
    zipcode: "1000",
    country: "BE",
    vat: "BE0797948229",
    email: "invoice@company.com",
    iban: "BE68539007547034"           # Required for payment means
  },

  # Customer information
  customer: %{
    endpoint_id: "0012345625",
    scheme: "0208",
    name: "Customer Name",
    vat: "BE0012345625",
    street: "Customer Street",
    housenumber: "45",
    city: "City",
    zipcode: "2000",
    country: "BE"
  },

  # Line items
  details: [
    %{
      name: "Service or product description",
      quantity: Decimal.new("1.00"),
      price: Decimal.new("100.00"),
      vat: Decimal.new("21.00"),      # VAT percentage
      discount: Decimal.new("0.00")   # Discount percentage
    }
  ],

  # Optional attachments
  attachments: [
    %{
      filename: "invoice.pdf",
      mime_type: "application/pdf",
      data: "base64encoded..."
    }
  ]
}
```

### Application Response Structure

```elixir
%{
  # Document metadata
  type: :application_response,
  id: "RESPONSE-001",
  date: ~D[2025-06-02],
  response_code: "AB",                # AB = Acknowledged, RE = Rejected, AP = Accepted with errors, CA = Conditionally accepted
  document_reference: "INV-123",      # The invoice/credit note being acknowledged
  status_reason: "Optional reason",
  note: "Optional note",

  # Sender (the party sending the response)
  sender: %{
    endpoint_id: "0797948229",
    scheme: "0208",
    name: "Company Name"
  },

  # Receiver (the party receiving the response)
  receiver: %{
    endpoint_id: "0844125969",
    scheme: "0208",
    name: "Supplier Name"
  }
}
```

## API Reference

### Parsing

#### `UblEx.parse(xml_content)`

Parse UBL XML with automatic schema detection. This is the recommended way to parse documents.

Returns `{:ok, parsed_data}` or `{:error, reason}`.

#### `UblEx.parse_xml(xml_content, schema_id)`

Parse XML with a specific schema (`:ubl_peppol`). Use this when you know the schema in advance.

Returns `{:ok, parsed_data}` or `{:error, reason}`.

### Generation

#### `UblEx.generate(document_data)`

Generate XML based on the `:type` field in the data (`:invoice`, `:credit`, or `:application_response`).

#### `UblEx.generate_with_sbdh(document_data)`

Generate XML wrapped in SBDH (Standard Business Document Header) for Peppol network transmission.

## EU Reverse Charge (Intra-Community Transactions)

For B2B transactions between EU countries where the customer is liable for VAT:

```elixir
document_data = %{
  # ...
  reverse_charge: true,  # Triggers tax category "K" in UBL
  # ...
}
```

This generates the correct UBL tax category for intra-community reverse charge transactions according to EU VAT regulations.

## Real-World Usage

### Basic Invoice Processing

```elixir
defmodule MyApp.Invoices do
  def import_ubl_invoice(xml_file_path) do
    with {:ok, xml} <- File.read(xml_file_path),
         {:ok, parsed} <- UblEx.parse(xml) do

      # Save to your database
      %Invoice{}
      |> Invoice.changeset(%{
        number: parsed.number,
        date: parsed.date,
        supplier_name: parsed.supplier.name,
        customer_name: parsed.customer.name,
        total: calculate_total(parsed.details)
      })
      |> Repo.insert()
    end
  end

  defp calculate_total(details) do
    Enum.reduce(details, Decimal.new(0), fn item, acc ->
      line_total = Decimal.mult(item.quantity, item.price)
      Decimal.add(acc, line_total)
    end)
  end
end
```

### Generate Invoice from Database

```elixir
defmodule MyApp.Invoices do
  def generate_ubl_xml(invoice_id) do
    invoice = Repo.get!(Invoice, invoice_id) |> Repo.preload([:customer, :supplier, :line_items])

    document_data = %{
      type: :invoice,
      number: invoice.number,
      date: invoice.date,
      expires: invoice.due_date,
      reverse_charge: invoice.reverse_charge?,

      supplier: %{
        endpoint_id: invoice.supplier.endpoint_id,
        scheme: invoice.supplier.scheme,
        name: invoice.supplier.name,
        street: invoice.supplier.street,
        city: invoice.supplier.city,
        zipcode: invoice.supplier.zipcode,
        country: invoice.supplier.country,
        vat: invoice.supplier.vat,
        email: invoice.supplier.email
      },

      customer: %{
        endpoint_id: invoice.customer.endpoint_id,
        scheme: invoice.customer.scheme,
        name: invoice.customer.name,
        vat: invoice.customer.vat,
        street: invoice.customer.street,
        housenumber: invoice.customer.housenumber,
        city: invoice.customer.city,
        zipcode: invoice.customer.zipcode,
        country: invoice.customer.country
      },

      details: Enum.map(invoice.line_items, fn item ->
        %{
          name: item.description,
          quantity: item.quantity,
          price: item.unit_price,
          vat: item.vat_rate,
          discount: item.discount_percentage
        }
      end)
    }

    UblEx.generate(document_data)
  end
end
```

## Compliance

This library generates UBL documents compliant with:

- **UBL 2.1** - Universal Business Language version 2.1
- **Peppol BIS Billing 3.0** - Pan-European Public Procurement Online
- **EN16931** - European standard for electronic invoicing

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
