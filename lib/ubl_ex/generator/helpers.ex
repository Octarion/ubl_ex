defmodule UblEx.Generator.Helpers do
  @moduledoc """
  Helper functions for UBL generation.

  Contains utility functions for calculating totals, formatting values,
  and generating XML fragments.
  """

  @doc """
  Calculate UBL-compliant line total for a detail item.

  Ensures consistency with AllowanceCharge calculations.
  """
  def ubl_line_total(detail) do
    if Decimal.gt?(detail.discount, 0) do
      base_amount = Decimal.mult(detail.quantity, detail.price) |> Decimal.round(2)
      multiplier = Decimal.div(detail.discount, 100)
      allowance = Decimal.mult(base_amount, multiplier) |> Decimal.round(2)
      Decimal.sub(base_amount, allowance) |> Decimal.round(2)
    else
      Decimal.mult(detail.quantity, detail.price) |> Decimal.round(2)
    end
  end

  @doc """
  Calculate UBL-compliant totals with proper rounding for Peppol validation.

  Ensures:
  - BR-CO-15: TaxInclusiveAmount = TaxExclusiveAmount + TaxAmount
  - BR-CO-10: LineExtensionAmount = Σ InvoiceLine/LineExtensionAmount
  - PEPPOL-EN16931-R120: Line net amounts are correctly calculated

  Returns a map with:
  - `:subtotal` - Sum of all line totals
  - `:vat` - Sum of all VAT amounts
  - `:grand_total` - Subtotal + VAT
  """
  def ubl_totals(details) do
    line_totals =
      details
      |> Enum.map(fn detail ->
        line_total = ubl_line_total(detail)

        vat_amount =
          Decimal.mult(line_total, detail.vat)
          |> Decimal.div(100)
          |> Decimal.round(2)

        %{line_total: line_total, vat_amount: vat_amount}
      end)

    subtotal =
      line_totals
      |> Enum.map(& &1.line_total)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
      |> Decimal.round(2)

    vat =
      line_totals
      |> Enum.map(& &1.vat_amount)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
      |> Decimal.round(2)

    grand_total = Decimal.add(subtotal, vat) |> Decimal.round(2)

    %{subtotal: subtotal, vat: vat, grand_total: grand_total}
  end

  @doc """
  Generate tax totals XML for all tax categories.

  Groups details by VAT percentage and generates TaxSubtotal elements.
  """
  def tax_totals(details, intra) do
    details
    |> Enum.reduce(%{}, fn detail, agg ->
      current = Map.get(agg, detail.vat, %{vat: Decimal.new(0), subtotal: Decimal.new(0)})
      total_ex = ubl_line_total(detail)
      vat_amount = Decimal.mult(total_ex, detail.vat) |> Decimal.div(100) |> Decimal.round(2)
      subtotal = Decimal.add(current.subtotal, total_ex) |> Decimal.round(2)
      vat = Decimal.add(current.vat, vat_amount) |> Decimal.round(2)
      Map.put(agg, detail.vat, %{vat: vat, subtotal: subtotal})
    end)
    |> Enum.map(&tax_sub_total(&1, intra))
  end

  @doc """
  Generate a TaxSubtotal XML element.
  """
  def tax_sub_total({perc, %{vat: vat, subtotal: subtotal}}, intra) do
    """
        <cac:TaxSubtotal>
            <cbc:TaxableAmount currencyID="EUR">#{format(subtotal)}</cbc:TaxableAmount>
            <cbc:TaxAmount currencyID="EUR">#{format(vat)}</cbc:TaxAmount>
            <cac:TaxCategory>
                #{tax(perc, intra)}
                <cac:TaxScheme>
                    <cbc:ID>VAT</cbc:ID>
                </cac:TaxScheme>
            </cac:TaxCategory>
        </cac:TaxSubtotal>\
    """
  end

  @doc """
  Generate tax category XML (ID and Percent).

  Accepts either integer or Decimal percentages.
  """
  def tax(perc, intra) when is_struct(perc, Decimal) do
    tax(Decimal.to_integer(perc), intra)
  end

  def tax(0, false), do: tax("Z", "0")
  def tax(0, true), do: tax("K", "0")
  def tax(6, _), do: tax("S", "6")
  def tax(12, _), do: tax("S", "12")
  def tax(21, _), do: tax("S", "21")

  def tax(id, percent) do
    """
    <cbc:ID>#{id}</cbc:ID>
                  <cbc:Percent>#{percent}</cbc:Percent>\
    """
  end

  @doc """
  Generate AllowanceCharge XML for a detail with discount.
  """
  def allowance_charge_xml(detail) do
    if Decimal.gt?(detail.discount, 0) do
      line_total = ubl_line_total(detail)
      percentage = detail.discount

      multiplier_decimal = Decimal.div(percentage, 100)

      base_amount =
        Decimal.div(line_total, Decimal.sub(Decimal.new(1), multiplier_decimal))
        |> Decimal.round(2)

      allowance_amount =
        Decimal.mult(base_amount, percentage) |> Decimal.div(100) |> Decimal.round(2)

      """
        <cac:AllowanceCharge>
            <cbc:ChargeIndicator>false</cbc:ChargeIndicator>
            <cbc:AllowanceChargeReason>Discount</cbc:AllowanceChargeReason>
            <cbc:MultiplierFactorNumeric>#{format(detail.discount)}</cbc:MultiplierFactorNumeric>
            <cbc:Amount currencyID="EUR">#{format(allowance_amount)}</cbc:Amount>
            <cbc:BaseAmount currencyID="EUR">#{format(base_amount)}</cbc:BaseAmount>
        </cac:AllowanceCharge>\
      """
    else
      ""
    end
  end

  @doc """
  Generate BillingReference XML elements.

  Accepts a list of invoice numbers and generates BillingReference elements.
  """
  def billing_reference([]), do: ""

  def billing_reference(invoice_numbers) when is_list(invoice_numbers) do
    invoice_numbers
    |> Enum.map(fn number ->
      """
      <cac:BillingReference>
            <cac:InvoiceDocumentReference>
            <cbc:ID>V01/F#{number}</cbc:ID>
            </cac:InvoiceDocumentReference>\
      </cac:BillingReference>
      """
    end)
    |> Enum.join("\n")
  end

  @doc """
  Generate Delivery terms XML for invoices.
  """
  def delivery_terms(customer, false) do
    """
    <cac:Delivery>
        <cac:DeliveryLocation>
            <cac:Address>
                <cbc:StreetName>#{escape(customer.street)} #{escape(customer.housenumber)}</cbc:StreetName>
                <cbc:CityName>#{escape(customer.city)}</cbc:CityName>
                <cbc:PostalZone>#{customer.zipcode}</cbc:PostalZone>
                <cac:Country>
                    <cbc:IdentificationCode>#{customer.country}</cbc:IdentificationCode>
                </cac:Country>
            </cac:Address>
        </cac:DeliveryLocation>
    </cac:Delivery>\
    """
  end

  def delivery_terms(_customer, true), do: ""

  @doc """
  Extract numeric VAT number (remove country code and non-digits).
  """
  def vat_number(nil), do: ""
  def vat_number(str), do: String.replace(str, ~r/\D*/, "")

  @doc """
  Format a Decimal amount as a string with 2 decimal places.
  """
  def format(amt) do
    amt
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> format_decimal_string()
  end

  defp format_decimal_string(str) do
    case String.split(str, ".") do
      [int_part] -> "#{int_part}.00"
      [int_part, dec_part] when byte_size(dec_part) == 1 -> "#{int_part}.#{dec_part}0"
      [int_part, dec_part] -> "#{int_part}.#{String.slice(dec_part, 0, 2)}"
    end
  end

  @doc """
  Escape XML special characters.
  """
  def escape(str) when is_binary(str) do
    str
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  def escape(other), do: to_string(other)
end
