defmodule UblEx.Generator.Helpers do
  @moduledoc """
  Helper functions for UBL generation.

  Contains utility functions for calculating totals, formatting values,
  and generating XML fragments.
  """

  @country_schemes %{
    "AT" => "9915",
    "BE" => "0208",
    "BG" => "9926",
    "CY" => "9928",
    "CZ" => "9929",
    "DE" => "0204",
    "DK" => "0096",
    "EE" => "9931",
    "ES" => "9920",
    "FI" => "0037",
    "FR" => "0009",
    "GR" => "9933",
    "HR" => "9934",
    "HU" => "9910",
    "IE" => "9935",
    "IT" => "0201",
    "LT" => "9937",
    "LU" => "9938",
    "LV" => "9939",
    "MT" => "9943",
    "NL" => "0106",
    "PL" => "9945",
    "PT" => "9946",
    "RO" => "9947",
    "SE" => "0007",
    "SI" => "9949",
    "SK" => "9950"
  }

  @default_scheme "0088"

  @doc """
  Infer Peppol scheme ID from country code.

  Returns the country-specific scheme if known, otherwise returns "0088" (EAN/GLN).

  ## Examples

      iex> UblEx.Generator.Helpers.infer_scheme("BE")
      "0208"

      iex> UblEx.Generator.Helpers.infer_scheme("US")
      "0088"
  """
  def infer_scheme(country) when is_binary(country) do
    Map.get(@country_schemes, country, @default_scheme)
  end

  def infer_scheme(_), do: @default_scheme

  @doc """
  Get scheme for a party, using explicit scheme if provided, otherwise inferring from country.
  """
  def party_scheme(party) do
    case Map.get(party, :scheme) do
      nil -> infer_scheme(Map.get(party, :country))
      scheme -> scheme
    end
  end

  @tax_category_codes %{
    standard: "S",
    zero_rated: "Z",
    exempt: "E",
    reverse_charge: "AE",
    intra_community: "K",
    export: "G",
    outside_scope: "O"
  }

  @peppol_code_to_category Map.new(@tax_category_codes, fn {k, v} -> {v, k} end)

  @doc """
  Convert a Peppol tax category code to a descriptive atom.

  Returns `:standard` for unknown codes.
  """
  def peppol_code_to_category(code) do
    Map.get(@peppol_code_to_category, code, :standard)
  end

  @doc """
  Infer tax category from detail, defaulting based on VAT percentage.

  If `tax_category` is explicitly set, use it. Otherwise:
  - VAT 6%, 12%, 21% → :standard
  - VAT 0% → :zero_rated
  """
  def infer_tax_category(detail) do
    case Map.get(detail, :tax_category) do
      nil -> default_tax_category(detail.vat)
      category -> category
    end
  end

  defp default_tax_category(vat) when is_struct(vat, Decimal) do
    if Decimal.eq?(vat, 0), do: :zero_rated, else: :standard
  end

  defp default_tax_category(0), do: :zero_rated
  defp default_tax_category(_), do: :standard

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

  Groups details by VAT percentage and tax category, then generates TaxSubtotal elements.
  """
  def tax_totals(details) do
    details
    |> Enum.reduce(%{}, fn detail, agg ->
      tax_category = infer_tax_category(detail)
      key = {detail.vat, tax_category}

      current =
        Map.get(agg, key, %{
          vat: Decimal.new(0),
          subtotal: Decimal.new(0),
          tax_category: tax_category
        })

      total_ex = ubl_line_total(detail)
      vat_amount = Decimal.mult(total_ex, detail.vat) |> Decimal.div(100) |> Decimal.round(2)
      subtotal = Decimal.add(current.subtotal, total_ex) |> Decimal.round(2)
      vat = Decimal.add(current.vat, vat_amount) |> Decimal.round(2)
      Map.put(agg, key, %{vat: vat, subtotal: subtotal, tax_category: tax_category})
    end)
    |> Enum.map(&tax_sub_total/1)
  end

  @doc """
  Generate a TaxSubtotal XML element.
  """
  def tax_sub_total(
        {{perc, _tax_category}, %{vat: vat, subtotal: subtotal, tax_category: tax_category}}
      ) do
    """
        <cac:TaxSubtotal>
            <cbc:TaxableAmount currencyID="EUR">#{format(subtotal)}</cbc:TaxableAmount>
            <cbc:TaxAmount currencyID="EUR">#{format(vat)}</cbc:TaxAmount>
            <cac:TaxCategory>
                #{tax(perc, tax_category)}
                <cac:TaxScheme>
                    <cbc:ID>VAT</cbc:ID>
                </cac:TaxScheme>
            </cac:TaxCategory>
        </cac:TaxSubtotal>\
    """
  end

  @doc """
  Generate tax category XML (ID and Percent).

  Accepts VAT percentage (integer or Decimal) and tax category atom.
  """
  def tax(perc, tax_category) when is_struct(perc, Decimal) do
    tax(Decimal.to_integer(perc), tax_category)
  end

  def tax(perc, tax_category) when is_atom(tax_category) do
    code = Map.fetch!(@tax_category_codes, tax_category)
    tax_xml(code, perc)
  end

  defp tax_xml(code, percent) do
    """
    <cbc:ID>#{code}</cbc:ID>
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
            <cbc:ID>#{number}</cbc:ID>
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
