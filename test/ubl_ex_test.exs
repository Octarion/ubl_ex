defmodule UblExTest do
  use ExUnit.Case
  doctest UblEx

  @fixtures_path Path.join(__DIR__, "fixtures/xml")

  describe "parse/1" do
    test "parses UBL invoice successfully" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_invoice.xml"))

      assert {:ok, parsed} = UblEx.parse(xml)
      assert parsed.type == :invoice
      assert is_binary(parsed.number)
      assert %Date{} = parsed.date
      assert is_map(parsed.supplier)
      assert is_map(parsed.customer)
      assert is_list(parsed.details)
    end

    test "parses UBL credit note successfully" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_creditnote.xml"))

      assert {:ok, parsed} = UblEx.parse(xml)
      assert parsed.type == :credit
      assert is_binary(parsed.number)
      assert %Date{} = parsed.date
      assert is_map(parsed.supplier)
      assert is_map(parsed.customer)
      assert is_list(parsed.details)
    end

    test "returns error on invalid XML" do
      assert {:error, _reason} = UblEx.parse("not xml")
    end

    test "parses application response" do
      xml = File.read!(Path.join(@fixtures_path, "sbdh_application_response.xml"))

      assert {:ok, parsed} = UblEx.parse(xml)
      assert parsed.type == :application_response
      assert parsed.response_code == "AB"
      assert parsed.document_reference == "F2025173"
    end
  end

  describe "generate/1" do
    test "generates invoice from parsed data" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_invoice.xml"))
      {:ok, parsed} = UblEx.parse(xml)

      assert is_binary(UblEx.generate(parsed))
    end

    test "generates credit note from parsed data" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_creditnote.xml"))
      {:ok, parsed} = UblEx.parse(xml)

      assert is_binary(UblEx.generate(parsed))
    end

    test "returns error for missing type field" do
      assert {:error, reason} = UblEx.generate(%{number: "F001"})
      assert reason =~ "Missing :type field"
    end

    test "returns error for invalid type" do
      assert {:error, reason} = UblEx.generate(%{type: :invalid})
      assert reason =~ "Unknown document type"
    end

    test "generates application response from parsed data" do
      xml = File.read!(Path.join(@fixtures_path, "sbdh_application_response.xml"))
      {:ok, parsed} = UblEx.parse(xml)

      assert is_binary(UblEx.generate(parsed))
    end
  end

  describe "attachments" do
    test "parses attachments from credit note" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_creditnote.xml"))
      {:ok, parsed} = UblEx.parse(xml)

      assert is_list(parsed.attachments)
      assert length(parsed.attachments) > 0

      attachment = hd(parsed.attachments)
      assert is_binary(attachment.filename)
      assert attachment.filename =~ ".pdf"
      assert attachment.mime_type == "application/pdf"
      assert is_binary(attachment.data)
      assert String.length(attachment.data) > 0
    end

    test "generates XML with multiple attachments" do
      data = %{
        type: :invoice,
        number: "F001",
        date: ~D[2024-01-15],
        expires: ~D[2024-02-14],
        supplier: %{
          endpoint_id: "0797948229",
          scheme: "0208",
          name: "Test",
          street: "St",
          city: "City",
          zipcode: "1000",
          country: "BE",
          vat: "BE123",
          email: "test@test.com"
        },
        customer: %{
          name: "Customer",
          vat: "BE456",
          street: "St",
          housenumber: "1",
          city: "City",
          zipcode: "1000",
          country: "BE"
        },
        details: [
          %{
            name: "Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("21"),
            discount: Decimal.new("0")
          }
        ],
        attachments: [
          %{filename: "invoice.pdf", mime_type: "application/pdf", data: "base64data1"},
          %{filename: "terms.pdf", mime_type: "application/pdf", data: "base64data2"}
        ]
      }

      xml = UblEx.generate(data)
      assert xml =~ "invoice.pdf"
      assert xml =~ "terms.pdf"
      assert xml =~ "base64data1"
      assert xml =~ "base64data2"
    end

    test "attachment round-trip preserves data" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_creditnote.xml"))
      {:ok, parsed1} = UblEx.parse(xml)

      # Should have attachments
      assert length(parsed1.attachments) > 0
      original_attachment = hd(parsed1.attachments)

      # Generate and reparse
      generated_xml = UblEx.generate(parsed1)
      {:ok, parsed2} = UblEx.parse(generated_xml)

      # Verify attachment preserved
      assert length(parsed2.attachments) == length(parsed1.attachments)
      reparsed_attachment = hd(parsed2.attachments)

      assert reparsed_attachment.filename == original_attachment.filename
      assert reparsed_attachment.mime_type == original_attachment.mime_type
      assert reparsed_attachment.data == original_attachment.data
    end
  end

  describe "generate_with_sbdh/1" do
    test "generates SBDH-wrapped invoice" do
      data = %{
        type: :invoice,
        number: "F001",
        date: ~D[2024-01-15],
        expires: ~D[2024-02-14],
        supplier: %{
          endpoint_id: "0797948229",
          scheme: "0208",
          name: "Test",
          street: "St",
          city: "City",
          zipcode: "1000",
          country: "BE",
          vat: "BE123",
          email: "test@test.com"
        },
        customer: %{
          name: "Customer",
          vat: "BE456",
          street: "St",
          housenumber: "1",
          city: "City",
          zipcode: "1000",
          country: "BE"
        },
        details: [
          %{
            name: "Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("21"),
            discount: Decimal.new("0")
          }
        ]
      }

      xml = UblEx.generate_with_sbdh(data)
      assert xml =~ "StandardBusinessDocument"
      assert xml =~ "StandardBusinessDocumentHeader"
      assert xml =~ "<Invoice"
      assert xml =~ "0208:0797948229"
      assert xml =~ "0208:456"
    end

    test "SBDH-wrapped invoice round-trip" do
      data = %{
        type: :invoice,
        number: "F001",
        date: ~D[2024-01-15],
        expires: ~D[2024-02-14],
        supplier: %{
          endpoint_id: "0797948229",
          scheme: "0208",
          name: "Test",
          street: "St",
          city: "City",
          zipcode: "1000",
          country: "BE",
          vat: "BE123",
          email: "test@test.com"
        },
        customer: %{
          name: "Customer",
          vat: "BE456",
          street: "St",
          housenumber: "1",
          city: "City",
          zipcode: "1000",
          country: "BE"
        },
        details: [
          %{
            name: "Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("21"),
            discount: Decimal.new("0")
          }
        ]
      }

      sbdh_xml = UblEx.generate_with_sbdh(data)
      {:ok, parsed} = UblEx.parse(sbdh_xml)

      assert parsed.type == :invoice
      assert parsed.number == "F001"
      assert parsed.supplier.name == "Test"
      assert parsed.customer.name == "Customer"
    end

    test "generates SBDH-wrapped credit note" do
      data = %{
        type: :credit,
        number: "C001",
        date: ~D[2024-01-20],
        billing_references: ["F001"],
        supplier: %{
          endpoint_id: "0797948229",
          scheme: "0208",
          name: "Test",
          street: "St",
          city: "City",
          zipcode: "1000",
          country: "BE",
          vat: "BE123",
          email: "test@test.com"
        },
        customer: %{
          name: "Customer",
          vat: "BE456",
          street: "St",
          housenumber: "1",
          city: "City",
          zipcode: "1000",
          country: "BE"
        },
        details: [
          %{
            name: "Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("21"),
            discount: Decimal.new("0")
          }
        ]
      }

      xml = UblEx.generate_with_sbdh(data)
      assert xml =~ "StandardBusinessDocument"
      assert xml =~ "<CreditNote"
      assert xml =~ "0208:0797948229"
    end

    test "generates SBDH-wrapped application response" do
      data = %{
        type: :application_response,
        id: "RESPONSE-001",
        date: ~D[2025-06-02],
        response_code: "AB",
        document_reference: "F001",
        sender: %{
          endpoint_id: "0797948229",
          scheme: "0208",
          name: "My Company"
        },
        receiver: %{
          endpoint_id: "0844125969",
          scheme: "0208",
          name: "Supplier Inc"
        }
      }

      xml = UblEx.generate_with_sbdh(data)
      assert xml =~ "StandardBusinessDocument"
      assert xml =~ "<ApplicationResponse"
      assert xml =~ "0208:0797948229"
      assert xml =~ "0208:0844125969"
    end
  end

  describe "tax_category" do
    test "generates invoice with standard tax category (default)" do
      data =
        invoice_data([
          %{
            name: "Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("21"),
            discount: Decimal.new("0")
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:ID>S</cbc:ID>"
      assert xml =~ "<cbc:Percent>21</cbc:Percent>"
    end

    test "generates invoice with intra-community tax category" do
      data =
        invoice_data([
          %{
            name: "EU Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :intra_community
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:ID>K</cbc:ID>"
      assert xml =~ "<cbc:Percent>0</cbc:Percent>"
    end

    test "generates invoice with reverse charge tax category" do
      data =
        invoice_data([
          %{
            name: "Domestic Reverse Charge",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :reverse_charge
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:ID>AE</cbc:ID>"
    end

    test "generates invoice with exempt tax category" do
      data =
        invoice_data([
          %{
            name: "Exempt Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :exempt
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:ID>E</cbc:ID>"
    end

    test "generates invoice with export tax category" do
      data =
        invoice_data([
          %{
            name: "Export Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :export
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:ID>G</cbc:ID>"
    end

    test "generates invoice with outside_scope tax category" do
      data =
        invoice_data([
          %{
            name: "Out of Scope Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :outside_scope
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:ID>O</cbc:ID>"
    end

    test "generates invoice with zero_rated tax category" do
      data =
        invoice_data([
          %{
            name: "Zero Rated Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :zero_rated
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:ID>Z</cbc:ID>"
    end

    test "defaults 0% vat to zero_rated when no tax_category specified" do
      data =
        invoice_data([
          %{
            name: "Zero VAT Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0")
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:ID>Z</cbc:ID>"
    end

    test "generates invoice with mixed tax categories" do
      data =
        invoice_data([
          %{
            name: "Standard Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("21"),
            discount: Decimal.new("0")
          },
          %{
            name: "EU Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("200"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :intra_community
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:ID>S</cbc:ID>"
      assert xml =~ "<cbc:ID>K</cbc:ID>"
    end

    test "tax_category survives round-trip" do
      data =
        invoice_data([
          %{
            name: "EU Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :intra_community
          }
        ])

      xml = UblEx.generate(data)
      {:ok, parsed} = UblEx.parse(xml)

      assert hd(parsed.details).tax_category == :intra_community
    end

    test "standard tax_category is not included in parsed output (default)" do
      data =
        invoice_data([
          %{
            name: "Standard Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("21"),
            discount: Decimal.new("0")
          }
        ])

      xml = UblEx.generate(data)
      {:ok, parsed} = UblEx.parse(xml)

      refute Map.has_key?(hd(parsed.details), :tax_category)
    end
  end

  describe "tax exemption fields" do
    test "generates invoice with intra-community exemption fields" do
      data =
        invoice_data([
          %{
            name: "EU Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :intra_community,
            tax_exemption_reason_code: "vatex-eu-ic",
            tax_exemption_reason: "Vrijgestelde intracommunautaire levering - Art. 39bis WBTW"
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:TaxExemptionReasonCode>vatex-eu-ic</cbc:TaxExemptionReasonCode>"

      assert xml =~
               "<cbc:TaxExemptionReason>Vrijgestelde intracommunautaire levering - Art. 39bis WBTW</cbc:TaxExemptionReason>"
    end

    test "generates invoice with reverse charge exemption fields" do
      data =
        invoice_data([
          %{
            name: "Domestic RC",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :reverse_charge,
            tax_exemption_reason_code: "vatex-eu-ae",
            tax_exemption_reason: "BTW te voldoen door de medecontractant - Art. 51 §2 WBTW"
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:TaxExemptionReasonCode>vatex-eu-ae</cbc:TaxExemptionReasonCode>"

      assert xml =~
               "<cbc:TaxExemptionReason>BTW te voldoen door de medecontractant - Art. 51 §2 WBTW</cbc:TaxExemptionReason>"
    end

    test "generates invoice with export exemption fields" do
      data =
        invoice_data([
          %{
            name: "Export Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :export,
            tax_exemption_reason_code: "vatex-eu-g",
            tax_exemption_reason: "Vrijgestelde uitvoer - Art. 39 WBTW"
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:TaxExemptionReasonCode>vatex-eu-g</cbc:TaxExemptionReasonCode>"

      assert xml =~
               "<cbc:TaxExemptionReason>Vrijgestelde uitvoer - Art. 39 WBTW</cbc:TaxExemptionReason>"
    end

    test "generates invoice with exempt exemption fields" do
      data =
        invoice_data([
          %{
            name: "Medical Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :exempt,
            tax_exemption_reason_code: "vatex-eu-132c",
            tax_exemption_reason: "Vrijgestelde medische prestatie - Art. 44 §1 WBTW"
          }
        ])

      xml = UblEx.generate(data)
      assert xml =~ "<cbc:TaxExemptionReasonCode>vatex-eu-132c</cbc:TaxExemptionReasonCode>"

      assert xml =~
               "<cbc:TaxExemptionReason>Vrijgestelde medische prestatie - Art. 44 §1 WBTW</cbc:TaxExemptionReason>"
    end

    test "parses exemption fields from XML" do
      data =
        invoice_data([
          %{
            name: "EU Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :intra_community,
            tax_exemption_reason_code: "vatex-eu-ic",
            tax_exemption_reason: "Vrijgestelde intracommunautaire levering - Art. 39bis WBTW"
          }
        ])

      xml = UblEx.generate(data)
      {:ok, parsed} = UblEx.parse(xml)

      detail = hd(parsed.details)
      assert detail.tax_exemption_reason_code == "vatex-eu-ic"

      assert detail.tax_exemption_reason ==
               "Vrijgestelde intracommunautaire levering - Art. 39bis WBTW"
    end

    test "generates invoice without exemption fields when not provided" do
      data =
        invoice_data([
          %{
            name: "Standard Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("21"),
            discount: Decimal.new("0")
          }
        ])

      xml = UblEx.generate(data)
      refute xml =~ "<cbc:TaxExemptionReasonCode>"
      refute xml =~ "<cbc:TaxExemptionReason>"
    end

    test "round-trip preserves exemption fields" do
      data =
        invoice_data([
          %{
            name: "EU Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0"),
            tax_category: :intra_community,
            tax_exemption_reason_code: "vatex-eu-ic",
            tax_exemption_reason: "Vrijgestelde intracommunautaire levering - Art. 39bis WBTW"
          }
        ])

      xml1 = UblEx.generate(data)
      {:ok, parsed1} = UblEx.parse(xml1)
      xml2 = UblEx.generate(parsed1)
      {:ok, parsed2} = UblEx.parse(xml2)

      detail1 = hd(parsed1.details)
      detail2 = hd(parsed2.details)

      assert detail1.tax_exemption_reason_code == detail2.tax_exemption_reason_code
      assert detail1.tax_exemption_reason == detail2.tax_exemption_reason
      assert detail1.tax_category == detail2.tax_category
    end
  end

  describe "scheme inference" do
    test "infers scheme from country when not explicitly set" do
      data = %{
        type: :invoice,
        number: "F001",
        date: ~D[2024-01-15],
        expires: ~D[2024-02-14],
        supplier: %{
          endpoint_id: "0797948229",
          name: "German Supplier",
          street: "Hauptstraße",
          city: "Berlin",
          zipcode: "10115",
          country: "DE",
          vat: "DE123456789",
          email: "test@test.de"
        },
        customer: %{
          name: "French Customer",
          vat: "FR12345678901",
          street: "Rue de Paris",
          housenumber: "1",
          city: "Paris",
          zipcode: "75001",
          country: "FR"
        },
        details: [
          %{
            name: "Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("19"),
            discount: Decimal.new("0")
          }
        ]
      }

      xml = UblEx.generate(data)

      assert xml =~ ~s(schemeID="0204")
      assert xml =~ ~s(schemeID="0009")
    end

    test "uses explicit scheme when provided" do
      data = %{
        type: :invoice,
        number: "F001",
        date: ~D[2024-01-15],
        expires: ~D[2024-02-14],
        supplier: %{
          endpoint_id: "0797948229",
          scheme: "0088",
          name: "Supplier",
          street: "Street",
          city: "City",
          zipcode: "1000",
          country: "DE",
          vat: "DE123456789",
          email: "test@test.de"
        },
        customer: %{
          scheme: "0088",
          name: "Customer",
          vat: "FR12345678901",
          street: "Street",
          housenumber: "1",
          city: "City",
          zipcode: "75001",
          country: "FR"
        },
        details: [
          %{
            name: "Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("19"),
            discount: Decimal.new("0")
          }
        ]
      }

      xml = UblEx.generate(data)

      assert xml =~ ~s(schemeID="0088")
      refute xml =~ ~s(schemeID="0204")
      refute xml =~ ~s(schemeID="0009")
    end

    test "falls back to 0088 for unknown country" do
      data = %{
        type: :invoice,
        number: "F001",
        date: ~D[2024-01-15],
        expires: ~D[2024-02-14],
        supplier: %{
          endpoint_id: "123456789",
          name: "US Supplier",
          street: "Main Street",
          city: "New York",
          zipcode: "10001",
          country: "US",
          vat: "US123456789",
          email: "test@test.us"
        },
        customer: %{
          name: "US Customer",
          vat: "US987654321",
          street: "Broadway",
          housenumber: "1",
          city: "New York",
          zipcode: "10002",
          country: "US"
        },
        details: [
          %{
            name: "Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("0"),
            discount: Decimal.new("0")
          }
        ]
      }

      xml = UblEx.generate(data)

      assert xml =~ ~s(schemeID="0088")
    end
  end

  describe "customer VAT handling" do
    test "preserves customer VAT number when country differs from VAT country" do
      data = %{
        type: :invoice,
        number: "F001",
        date: ~D[2024-01-15],
        expires: ~D[2024-02-14],
        supplier: %{
          endpoint_id: "0797948229",
          scheme: "0208",
          name: "Test Supplier",
          street: "Test Street",
          city: "Test City",
          zipcode: "1000",
          country: "BE",
          vat: "BE0797948229",
          email: "test@test.com"
        },
        customer: %{
          name: "Swiss Customer with Belgian VAT",
          vat: "BE0123456749",
          street: "Bahnhofstrasse",
          housenumber: "1",
          city: "Zürich",
          zipcode: "8001",
          country: "CH"
        },
        details: [
          %{
            name: "Service",
            quantity: Decimal.new("1"),
            price: Decimal.new("100"),
            vat: Decimal.new("21"),
            discount: Decimal.new("0")
          }
        ]
      }

      xml = UblEx.generate(data)

      assert xml =~ "<cbc:CompanyID>BE0123456749</cbc:CompanyID>"
      refute xml =~ "<cbc:CompanyID>CH0123456749</cbc:CompanyID>"
    end
  end

  describe "round-trip" do
    test "invoice survives parse -> generate -> parse cycle" do
      original_xml = File.read!(Path.join(@fixtures_path, "ubl_invoice.xml"))

      # First parse
      {:ok, parsed1} = UblEx.parse(original_xml)

      # Generate
      generated_xml = UblEx.generate(parsed1)

      # Second parse
      {:ok, parsed2} = UblEx.parse(generated_xml)

      # Verify key fields match
      assert parsed1.type == parsed2.type
      assert parsed1.number == parsed2.number
      assert parsed1.date == parsed2.date
      assert parsed1.supplier.name == parsed2.supplier.name
      assert parsed1.supplier.vat == parsed2.supplier.vat
      assert parsed1.customer.name == parsed2.customer.name
      assert parsed1.customer.vat == parsed2.customer.vat
      assert length(parsed1.details) == length(parsed2.details)
    end

    test "credit note survives parse -> generate -> parse cycle" do
      original_xml = File.read!(Path.join(@fixtures_path, "ubl_creditnote.xml"))

      # First parse
      {:ok, parsed1} = UblEx.parse(original_xml)

      # Generate
      generated_xml = UblEx.generate(parsed1)

      # Second parse
      {:ok, parsed2} = UblEx.parse(generated_xml)

      # Verify key fields match
      assert parsed1.type == parsed2.type
      assert parsed1.number == parsed2.number
      assert parsed1.date == parsed2.date
      assert parsed1.supplier.name == parsed2.supplier.name
      assert parsed1.customer.name == parsed2.customer.name
      assert length(parsed1.details) == length(parsed2.details)
      assert length(parsed1.attachments) == length(parsed2.attachments)
    end

    test "application response survives parse -> generate -> parse cycle" do
      original_xml = File.read!(Path.join(@fixtures_path, "sbdh_application_response.xml"))

      # First parse
      {:ok, parsed1} = UblEx.parse(original_xml)

      # Generate
      generated_xml = UblEx.generate(parsed1)

      # Second parse
      {:ok, parsed2} = UblEx.parse(generated_xml)

      # Verify key fields match
      assert parsed1.type == parsed2.type
      assert parsed1.id == parsed2.id
      assert parsed1.date == parsed2.date
      assert parsed1.response_code == parsed2.response_code
      assert parsed1.document_reference == parsed2.document_reference
      assert parsed1.sender.name == parsed2.sender.name
      assert parsed1.receiver.name == parsed2.receiver.name
    end
  end

  defp invoice_data(details) do
    %{
      type: :invoice,
      number: "F001",
      date: ~D[2024-01-15],
      expires: ~D[2024-02-14],
      supplier: %{
        endpoint_id: "0797948229",
        scheme: "0208",
        name: "Test Supplier",
        street: "Test Street",
        city: "Test City",
        zipcode: "1000",
        country: "BE",
        vat: "BE0797948229",
        email: "test@test.com"
      },
      customer: %{
        name: "Test Customer",
        vat: "BE0456789012",
        street: "Customer Street",
        housenumber: "1",
        city: "Customer City",
        zipcode: "2000",
        country: "BE"
      },
      details: details
    }
  end
end
