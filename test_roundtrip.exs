#!/usr/bin/env elixir

# Test script to parse UBL XML and regenerate it, then compare differences

defmodule RoundtripTest do
  def run(xml_file) do
    IO.puts("Testing roundtrip for: #{xml_file}\n")

    # Read original XML
    IO.puts("1. Reading original XML...")
    original_xml = File.read!(xml_file)
    IO.puts("   Original size: #{byte_size(original_xml)} bytes\n")

    # Parse the XML
    IO.puts("2. Parsing XML...")
    case UblEx.parse(original_xml) do
      {:ok, parsed_data} ->
        IO.puts("   ✓ Parsed successfully")
        IO.puts("   Document type: #{inspect(parsed_data[:type])}")
        IO.puts("   Document number: #{inspect(parsed_data[:number] || parsed_data[:id])}\n")

        # Generate new XML from parsed data
        IO.puts("3. Generating XML from parsed data...")
        regenerated_xml = UblEx.generate(parsed_data)
        IO.puts("   Regenerated size: #{byte_size(regenerated_xml)} bytes\n")

        # Write both files for comparison
        original_file = "/tmp/original_ubl.xml"
        regenerated_file = "/tmp/regenerated_ubl.xml"

        File.write!(original_file, original_xml)
        File.write!(regenerated_file, regenerated_xml)

        IO.puts("4. Files written:")
        IO.puts("   Original: #{original_file}")
        IO.puts("   Regenerated: #{regenerated_file}\n")

        # Compare
        IO.puts("5. Comparison:")
        if original_xml == regenerated_xml do
          IO.puts("   ✓ IDENTICAL - No differences found!")
        else
          IO.puts("   ✗ DIFFERENT - Files differ")
          IO.puts("\n   Size difference: #{byte_size(regenerated_xml) - byte_size(original_xml)} bytes")

          # Try to parse the regenerated XML to verify it's still valid
          IO.puts("\n6. Validating regenerated XML...")
          case UblEx.parse(regenerated_xml) do
            {:ok, reparsed_data} ->
              IO.puts("   ✓ Regenerated XML is valid and parseable")

              # Compare key fields
              IO.puts("\n7. Comparing key fields:")
              compare_field(parsed_data, reparsed_data, :type)
              compare_field(parsed_data, reparsed_data, :number)
              compare_field(parsed_data, reparsed_data, :id)
              compare_field(parsed_data, reparsed_data, :date)
              compare_field(parsed_data, reparsed_data, :currency)

              if parsed_data[:details] && reparsed_data[:details] do
                IO.puts("\n   Details comparison:")
                compare_field(parsed_data[:details], reparsed_data[:details], :total)
                compare_field(parsed_data[:details], reparsed_data[:details], :tax_total)
                compare_field(parsed_data[:details], reparsed_data[:details], :payable)
              end

              IO.puts("\n   Use 'diff' command to see detailed differences:")
              IO.puts("   diff #{original_file} #{regenerated_file}")

            {:error, reason} ->
              IO.puts("   ✗ Regenerated XML is INVALID: #{reason}")
          end
        end

      {:error, reason} ->
        IO.puts("   ✗ Parsing failed: #{reason}")
    end
  end

  defp compare_field(data1, data2, field) do
    val1 = data1[field]
    val2 = data2[field]

    status = if val1 == val2, do: "✓", else: "✗"
    IO.puts("   #{status} #{field}: #{inspect(val1)} #{if val1 != val2, do: "→ #{inspect(val2)}", else: ""}")
  end
end

# Run test
xml_file = System.argv() |> List.first() || "test/fixtures/xml/ubl_invoice.xml"
RoundtripTest.run(xml_file)
