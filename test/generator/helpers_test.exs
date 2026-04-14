defmodule UblEx.Generator.HelpersTest do
  use ExUnit.Case, async: true

  alias UblEx.Generator.Helpers

  describe "ubl_line_total/1 discount rounding" do
    test "half-penny rounding: qty=1, price=19.57, discount=50% yields 9.79" do
      detail = %{
        quantity: Decimal.new("1"),
        price: Decimal.new("19.57"),
        discount: Decimal.new("50"),
        vat: Decimal.new("21")
      }

      assert Decimal.eq?(Helpers.ubl_line_total(detail), Decimal.new("9.79"))
    end

    test "allowance_charge_xml uses derived allowance consistent with line total" do
      detail = %{
        quantity: Decimal.new("1"),
        price: Decimal.new("19.57"),
        discount: Decimal.new("50"),
        vat: Decimal.new("21")
      }

      xml = Helpers.allowance_charge_xml(detail)

      assert xml =~ ~r/<cbc:Amount currencyID="EUR">9.78<\/cbc:Amount>/
      assert xml =~ ~r/<cbc:BaseAmount currencyID="EUR">19.57<\/cbc:BaseAmount>/
    end

    test "invariant: base_amount = line_total + allowance for half-penny case" do
      detail = %{
        quantity: Decimal.new("1"),
        price: Decimal.new("19.57"),
        discount: Decimal.new("50"),
        vat: Decimal.new("21")
      }

      line_total = Helpers.ubl_line_total(detail)
      base_amount = Decimal.mult(detail.quantity, detail.price) |> Decimal.round(2)

      xml = Helpers.allowance_charge_xml(detail)
      [_, allowance_str] = Regex.run(~r/<cbc:Amount currencyID="EUR">([^<]+)</, xml)
      allowance = Decimal.new(allowance_str)

      assert Decimal.eq?(Decimal.add(line_total, allowance), base_amount)
    end
  end
end
