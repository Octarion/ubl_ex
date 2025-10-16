defmodule UblExTest do
  use ExUnit.Case
  doctest UblEx

  @fixtures_path Path.join(__DIR__, "fixtures/xml")

  describe "parse_xml/2" do
    test "parses UBL invoice successfully" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_invoice.xml"))

      assert {:ok, parsed} = UblEx.parse_xml(xml, :ubl_peppol)
      assert parsed.type == :invoice
      assert is_binary(parsed.number)
      assert %Date{} = parsed.date
      assert is_map(parsed.supplier)
      assert is_map(parsed.customer)
      assert is_list(parsed.details)
    end

    test "parses UBL credit note successfully" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_creditnote.xml"))

      assert {:ok, parsed} = UblEx.parse_xml(xml, :ubl_peppol)
      assert parsed.type == :credit
      assert is_binary(parsed.number)
      assert %Date{} = parsed.date
      assert is_map(parsed.supplier)
      assert is_map(parsed.customer)
      assert is_list(parsed.details)
    end

    test "crashes on invalid XML" do
      assert {:error, _reason} = UblEx.parse_xml("not xml", :ubl_peppol)
    end
  end

  describe "parse/1" do
    test "auto-detects UBL invoice" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_invoice.xml"))

      assert {:ok, parsed} = UblEx.parse(xml)
      assert parsed.type == :invoice
    end

    test "auto-detects UBL credit note" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_creditnote.xml"))

      assert {:ok, parsed} = UblEx.parse(xml)
      assert parsed.type == :credit
    end

    test "auto-detects application response" do
      xml = File.read!(Path.join(@fixtures_path, "sbdh_application_response.xml"))

      assert {:ok, parsed} = UblEx.parse(xml)
      assert parsed.type == :application_response
      assert parsed.response_code == "AB"
      assert parsed.document_reference == "F2025173"
    end
  end

  describe "generate/2" do
    test "generates invoice from parsed data" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_invoice.xml"))
      {:ok, parsed} = UblEx.parse_xml(xml, :ubl_peppol)

      assert is_binary(UblEx.generate(parsed))
    end

    test "generates credit note from parsed data" do
      xml = File.read!(Path.join(@fixtures_path, "ubl_creditnote.xml"))
      {:ok, parsed} = UblEx.parse_xml(xml, :ubl_peppol)

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
      {:ok, parsed} = UblEx.parse_xml(xml, :ubl_peppol)

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
        reverse_charge: false,
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
      {:ok, parsed1} = UblEx.parse_xml(xml, :ubl_peppol)

      # Should have attachments
      assert length(parsed1.attachments) > 0
      original_attachment = hd(parsed1.attachments)

      # Generate and reparse
      generated_xml = UblEx.generate(parsed1)
      {:ok, parsed2} = UblEx.parse_xml(generated_xml, :ubl_peppol)

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
        reverse_charge: false,
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
        reverse_charge: false,
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
        reverse_charge: false,
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

  describe "round-trip" do
    test "invoice survives parse -> generate -> parse cycle" do
      original_xml = File.read!(Path.join(@fixtures_path, "ubl_invoice.xml"))

      # First parse
      {:ok, parsed1} = UblEx.parse_xml(original_xml, :ubl_peppol)

      # Generate
      generated_xml = UblEx.generate(parsed1)

      # Second parse
      {:ok, parsed2} = UblEx.parse_xml(generated_xml, :ubl_peppol)

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
      {:ok, parsed1} = UblEx.parse_xml(original_xml, :ubl_peppol)

      # Generate
      generated_xml = UblEx.generate(parsed1)

      # Second parse
      {:ok, parsed2} = UblEx.parse_xml(generated_xml, :ubl_peppol)

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
end
