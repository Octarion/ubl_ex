# UblEx

Parse and generate UBL (Universal Business Language) documents in Elixir with full round-trip support.

**Peppol BIS Billing 3.0 compliant** • **UBL 2.1** • **EN16931**

## Features

- **Parse** UBL Invoice, CreditNote, and ApplicationResponse XML documents
- **Generate** Peppol-compliant UBL XML
- **Validate** against official Peppol BIS Billing 3.0 rules (optional)
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
    {:ubl_ex, "~> 0.6.0"}
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

### Validating UBL Documents

UblEx includes an optional validator that validates your generated UBL documents against official Peppol BIS Billing 3.0 rules using the free peppol.helger.com validation service.

**Note:** This feature requires the optional `req` dependency. Add it to your `mix.exs`:

```elixir
def deps do
  [
    {:ubl_ex, "~> 0.6.0"},
    {:req, "~> 0.5.0"}  # Required for validation
  ]
end
```

#### Validating an Invoice

```elixir
# Generate an invoice
document_data = %{type: :invoice, number: "F2024001", ...}
xml = UblEx.generate(document_data)

# Validate against Peppol BIS Billing 3.0
case UblEx.Validator.validate(xml, :invoice) do
  {:ok, result} ->
    IO.puts("✓ Valid Peppol invoice!")
    if result.warnings != [] do
      IO.puts("Warnings: #{inspect(result.warnings)}")
    end

  {:error, %{success: false, errors: errors}} ->
    IO.puts("✗ Invalid invoice:")
    Enum.each(errors, fn error -> IO.puts("  - #{error}") end)
end
```

#### Validating a Credit Note

```elixir
xml = UblEx.generate(%{type: :credit, ...})
UblEx.Validator.validate(xml, :credit)
```

#### Validation Options

```elixir
# Custom timeout (default: 30 seconds)
UblEx.Validator.validate(xml, :invoice, timeout: 60_000)

# Override VESID (validation executor set ID)
UblEx.Validator.validate(xml, :invoice, vesid: "eu.peppol.bis3:invoice:3.13.0")
```

#### Understanding Validation Results

The validator returns:
- **Errors** - Must be fixed for Peppol compliance
- **Warnings** - Should be fixed for best practices (e.g., country-specific requirements)

```elixir
{:ok, result} = UblEx.Validator.validate(xml, :invoice)
result.success  # true/false
result.errors   # List of error messages
result.warnings # List of warning messages
```

**Important Notes:**
- Validation requires an internet connection (calls external service)
- The service is provided free of charge without SLA
- For production use, consider caching validation results
- SBDH-wrapped documents cannot be validated directly (unwrap first)

## Document Structure

### Invoice and Credit Note Structure

```elixir
%{
  # Document metadata
  type: :invoice | :credit,
  number: "F2024001",
  date: ~D[2024-01-15],
  expires: ~D[2024-02-14],           # Invoices only
  order_reference: "PO-12345",
  billing_references: ["F001"],       # Credit notes only
  payment_id: "+++000/2024/00186+++", # Optional: Belgian structured payment reference

  # Supplier information
  supplier: %{
    endpoint_id: "0797948229",
    scheme: "0208",                   # Optional: inferred from country if not set
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
    # scheme: "0208",                 # Optional: inferred from country if not set
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
      discount: Decimal.new("0.00"),  # Discount percentage
      tax_category: :standard         # Optional: defaults to :standard for non-zero VAT, :zero_rated for 0%
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

## Tax Categories

UblEx supports all Peppol BIS 3.0 tax categories via the `tax_category` field on line items:

| Atom | Peppol Code | Use Case |
|------|-------------|----------|
| `:standard` | S | Standard rated VAT (default for 6/12/21%) |
| `:zero_rated` | Z | Zero rated goods (default for 0% VAT) |
| `:exempt` | E | Exempt from tax |
| `:reverse_charge` | AE | Domestic reverse charge |
| `:intra_community` | K | EU cross-border B2B (intra-community supply) |
| `:export` | G | Export outside EU |
| `:outside_scope` | O | Services outside scope of tax |

### EU Intra-Community Transactions

For B2B transactions between EU countries where the customer is liable for VAT:

```elixir
document_data = %{
  type: :invoice,
  number: "F2024001",
  # ...
  details: [
    %{
      name: "Consulting Services",
      quantity: Decimal.new("1.00"),
      price: Decimal.new("1000.00"),
      vat: Decimal.new("0.00"),
      discount: Decimal.new("0.00"),
      tax_category: :intra_community   # Generates tax category "K" in UBL
    }
  ]
}
```

### Mixed Tax Categories

You can mix different tax categories in the same invoice:

```elixir
details: [
  %{
    name: "Standard Service",
    quantity: Decimal.new("1.00"),
    price: Decimal.new("500.00"),
    vat: Decimal.new("21.00"),
    discount: Decimal.new("0.00")
    # tax_category defaults to :standard
  },
  %{
    name: "EU Cross-Border Service",
    quantity: Decimal.new("1.00"),
    price: Decimal.new("1000.00"),
    vat: Decimal.new("0.00"),
    discount: Decimal.new("0.00"),
    tax_category: :intra_community
  },
  %{
    name: "Export Service",
    quantity: Decimal.new("1.00"),
    price: Decimal.new("750.00"),
    vat: Decimal.new("0.00"),
    discount: Decimal.new("0.00"),
    tax_category: :export
  }
]
```

## Peppol Scheme IDs

The `scheme` field on supplier and customer is optional. If not provided, it is automatically inferred from the `country` field using the following mappings:

| Country | Scheme | Description |
|---------|--------|-------------|
| AT | 9915 | Austria - VAT |
| BE | 0208 | Belgium - KBO/BCE |
| BG | 9926 | Bulgaria - VAT |
| CY | 9928 | Cyprus - VAT |
| CZ | 9929 | Czech Republic - VAT |
| DE | 0204 | Germany - Leitweg-ID |
| DK | 0096 | Denmark - CVR |
| EE | 9931 | Estonia - VAT |
| ES | 9920 | Spain - VAT |
| FI | 0037 | Finland - LY-tunnus |
| FR | 0009 | France - SIRET |
| GR | 9933 | Greece - VAT |
| HR | 9934 | Croatia - VAT |
| HU | 9910 | Hungary - VAT |
| IE | 9935 | Ireland - VAT |
| IT | 0201 | Italy - Codice Fiscale |
| LT | 9937 | Lithuania - VAT |
| LU | 9938 | Luxembourg - VAT |
| LV | 9939 | Latvia - VAT |
| MT | 9943 | Malta - VAT |
| NL | 0106 | Netherlands - KvK |
| PL | 9945 | Poland - VAT |
| PT | 9946 | Portugal - VAT |
| RO | 9947 | Romania - VAT |
| SE | 0007 | Sweden - Organisationsnummer |
| SI | 9949 | Slovenia - VAT |
| SK | 9950 | Slovakia - VAT |

For countries not in this list, the fallback is `0088` (EAN/GLN - international).

You can always override the inferred scheme by explicitly setting the `scheme` field on the party.

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
        base = %{
          name: item.description,
          quantity: item.quantity,
          price: item.unit_price,
          vat: item.vat_rate,
          discount: item.discount_percentage
        }
        if item.tax_category, do: Map.put(base, :tax_category, item.tax_category), else: base
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
