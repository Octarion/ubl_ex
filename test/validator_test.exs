defmodule UblEx.ValidatorTest do
  use ExUnit.Case, async: true

  @moduletag :external

  describe "validate/2" do
    @tag timeout: 60_000
    test "validates a valid invoice" do
      # Generate a simple valid invoice
      invoice_data = %{
        type: :invoice,
        number: "TEST001",
        date: ~D[2025-01-15],
        expires: ~D[2025-02-14],
        supplier: %{
          name: "Test Supplier",
          vat: "BE0478493179",
          endpoint_id: "0478493179",
          scheme: "0208",
          street: "Test Street",
          housenumber: "1",
          zipcode: "1000",
          city: "Brussels",
          country: "BE",
          email: "supplier@test.be",
          iban: "BE68539007547034"
        },
        customer: %{
          name: "Test Customer",
          vat: "BE0308357159",
          endpoint_id: "0308357159",
          scheme: "0208",
          street: "Customer Street",
          housenumber: "2",
          zipcode: "2000",
          city: "Antwerp",
          country: "BE",
          email: "customer@test.be"
        },
        details: [
          %{
            name: "Test Item",
            quantity: Decimal.new("1"),
            price: Decimal.new("100.00"),
            vat: Decimal.new("21"),
            discount: Decimal.new("0")
          }
        ]
      }

      xml = UblEx.generate(invoice_data)

      case UblEx.Validator.validate(xml, :invoice) do
        {:ok, result} ->
          assert result.success == true
          assert is_list(result.errors)
          assert is_list(result.warnings)

          # Show warnings but don't fail on them (test data may have minor issues)
          if result.warnings != [] do
            IO.puts("\nValidation warnings (non-fatal):")
            Enum.each(result.warnings, fn warning -> IO.puts("  - #{warning}") end)
          end

        {:error, %{success: false} = result} ->
          IO.puts("\nValidation errors:")
          Enum.each(result.errors, fn error -> IO.puts("  - #{error}") end)

          if result.warnings != [] do
            IO.puts("\nValidation warnings:")
            Enum.each(result.warnings, fn warning -> IO.puts("  - #{warning}") end)
          end

          flunk("Invoice validation failed with errors")

        {:error, %{status: status, body: body}} ->
          IO.puts("\nHTTP #{status} error body:")
          IO.puts(body)
          flunk("Validation service HTTP #{status} error")

        {:error, reason} ->
          flunk("Validation failed: #{inspect(reason)}")
      end
    end

    @tag timeout: 60_000
    test "validates a credit note from fixture" do
      # Read the test fixture
      xml = File.read!("test/fixtures/xml/ubl_creditnote.xml")

      case UblEx.Validator.validate(xml, :credit) do
        {:ok, result} ->
          assert result.success == true
          assert is_list(result.errors)
          assert is_list(result.warnings)

        {:error, %{success: false} = result} ->
          # If validation fails, show the errors for debugging
          IO.puts("\nValidation errors:")
          Enum.each(result.errors, fn error -> IO.puts("  - #{error}") end)

          IO.puts("\nValidation warnings:")
          Enum.each(result.warnings, fn warning -> IO.puts("  - #{warning}") end)

          flunk("Credit note validation failed")

        {:error, %{status: status, body: body}} ->
          IO.puts("\nHTTP #{status} error body:")
          IO.puts(body)
          flunk("Validation service HTTP #{status} error")

        {:error, reason} ->
          flunk("Validation service error: #{inspect(reason)}")
      end
    end

    test "requires req dependency" do
      # This test would need to be run in isolation to properly test
      # For now, just verify the module loads
      assert Code.ensure_loaded?(UblEx.Validator)
    end
  end
end
