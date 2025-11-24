defmodule UblEx.Parser.UblHandler do
  @moduledoc """
  Direct Saxy handler for parsing UBL documents into our target map format.
  Knows the UBL structure and builds the result directly without XPath.
  """

  alias UblEx.Generator.Helpers

  @behaviour Saxy.Handler

  defstruct [
    :document_type,
    :result,
    :path,
    :current_text,
    :current_line,
    :current_party,
    :current_attachment,
    :line_items,
    :attachments,
    :billing_refs,
    :in_payment_means
  ]

  def new do
    %__MODULE__{
      document_type: nil,
      result: %{},
      path: [],
      current_text: "",
      current_line: nil,
      current_party: nil,
      line_items: [],
      attachments: [],
      billing_refs: [],
      in_payment_means: false
    }
  end

  @impl Saxy.Handler
  def handle_event(:start_document, _prolog, state) do
    {:ok, state}
  end

  @impl Saxy.Handler
  def handle_event(:end_document, _data, state) do
    result =
      state.result
      |> maybe_add(:details, Enum.reverse(state.line_items))
      |> maybe_add(:attachments, Enum.reverse(state.attachments))
      |> maybe_add(:billing_references, Enum.reverse(state.billing_refs))

    {:ok, %{state | result: result}}
  end

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attributes}, state) do
    local_name = local_name_from_qname(name)
    new_state = %{state | path: [local_name | state.path], current_text: ""}

    new_state =
      cond do
        local_name == "StandardBusinessDocument" ->
          new_state

        local_name in ["Invoice", "CreditNote", "ApplicationResponse"] ->
          set_document_type(new_state, local_name)

        local_name == "InvoiceLine" or local_name == "CreditNoteLine" ->
          %{new_state | current_line: %{}}

        local_name == "Party" and in_path?(state.path, ["AccountingSupplierParty"]) ->
          %{new_state | current_party: {:supplier, %{}}}

        local_name == "Party" and in_path?(state.path, ["AccountingCustomerParty"]) ->
          %{new_state | current_party: {:customer, %{}}}

        local_name == "SenderParty" ->
          %{new_state | current_party: {:sender, %{}}}

        local_name == "ReceiverParty" ->
          %{new_state | current_party: {:receiver, %{}}}

        local_name == "Party" and in_path?(state.path, ["SenderParty"]) ->
          %{new_state | current_party: {:sender, %{}}}

        local_name == "Party" and in_path?(state.path, ["ReceiverParty"]) ->
          %{new_state | current_party: {:receiver, %{}}}

        local_name == "AdditionalDocumentReference" ->
          %{new_state | current_attachment: %{}}

        local_name == "PaymentMeans" ->
          %{new_state | in_payment_means: true}

        local_name == "EndpointID" and not is_nil(state.current_party) ->
          {party_type, party_data} = state.current_party
          scheme = get_attribute(attributes, "schemeID")
          %{new_state | current_party: {party_type, Map.put(party_data, :scheme, scheme)}}

        local_name == "EmbeddedDocumentBinaryObject" and not is_nil(state.current_attachment) ->
          mime = get_attribute(attributes, "mimeCode")
          attachment = state.current_attachment |> Map.put(:mime_type, mime)
          %{new_state | current_attachment: attachment}

        true ->
          new_state
      end

    {:ok, new_state}
  end

  @impl Saxy.Handler
  def handle_event(:end_element, name, state) do
    local_name = local_name_from_qname(name)
    text = String.trim(state.current_text)

    new_state =
      cond do
        # Document-level fields
        local_name == "ID" and match?([^local_name, "Invoice" | _], state.path) ->
          put_result(state, :number, text)

        local_name == "ID" and match?([^local_name, "CreditNote" | _], state.path) ->
          put_result(state, :number, text)

        local_name == "ID" and match?([^local_name, "ApplicationResponse" | _], state.path) ->
          put_result(state, :id, text)

        local_name == "IssueDate" ->
          put_result(state, :date, parse_date(text))

        local_name == "DueDate" ->
          put_result(state, :expires, parse_date(text))

        local_name == "ResponseCode" ->
          put_result(state, :response_code, text)

        local_name == "StatusReason" ->
          put_result(state, :status_reason, text)

        local_name == "Note" and match?([^local_name, "ApplicationResponse"], state.path) ->
          put_result(state, :note, text)

        local_name == "ID" and in_path?(state.path, ["OrderReference"]) ->
          put_result(state, :order_reference, text)

        local_name == "ID" and
            in_path?(state.path, ["BillingReference", "InvoiceDocumentReference"]) ->
          %{state | billing_refs: [text | state.billing_refs]}

        local_name == "ID" and in_path?(state.path, ["DocumentReference"]) and
            state.document_type == :application_response ->
          put_result(state, :document_reference, parse_document_id(text))

        local_name == "ID" and match?(["ID", "ClassifiedTaxCategory" | _], state.path) and
            not is_nil(state.current_line) ->
          tax_category = Helpers.peppol_code_to_category(text)
          %{state | current_line: Map.put(state.current_line, :tax_category, tax_category)}

        # Payment fields
        local_name == "PaymentMeansCode" and state.in_payment_means ->
          put_result(state, :payment_means_code, text)

        local_name == "PaymentID" and state.in_payment_means ->
          put_result(state, :payment_id, text)

        local_name == "ID" and state.in_payment_means and
            in_path?(state.path, ["PayeeFinancialAccount"]) ->
          supplier = state.result[:supplier]

          if supplier do
            updated_supplier = Map.put(supplier, :iban, text)
            %{state | result: Map.put(state.result, :supplier, updated_supplier)}
          else
            state
          end

        local_name == "PaymentMeans" ->
          %{state | in_payment_means: false}

        # Party fields
        local_name == "EndpointID" and not is_nil(state.current_party) ->
          {party_type, party_data} = state.current_party
          %{state | current_party: {party_type, Map.put(party_data, :endpoint_id, text)}}

        local_name == "Name" and not is_nil(state.current_party) and
            in_path?(state.path, ["PartyName"]) ->
          {party_type, party_data} = state.current_party
          %{state | current_party: {party_type, Map.put(party_data, :name, text)}}

        local_name == "RegistrationName" and not is_nil(state.current_party) ->
          {party_type, party_data} = state.current_party
          %{state | current_party: {party_type, Map.put(party_data, :name, text)}}

        local_name == "StreetName" and not is_nil(state.current_party) ->
          {party_type, party_data} = state.current_party

          case party_type do
            :customer ->
              {street, housenumber} = parse_street_housenumber(text)

              party_data =
                party_data |> Map.put(:street, street) |> Map.put(:housenumber, housenumber)

              %{state | current_party: {party_type, party_data}}

            _ ->
              %{state | current_party: {party_type, Map.put(party_data, :street, text)}}
          end

        local_name == "CityName" and not is_nil(state.current_party) ->
          {party_type, party_data} = state.current_party
          %{state | current_party: {party_type, Map.put(party_data, :city, text)}}

        local_name == "PostalZone" and not is_nil(state.current_party) ->
          {party_type, party_data} = state.current_party
          %{state | current_party: {party_type, Map.put(party_data, :zipcode, text)}}

        local_name == "IdentificationCode" and not is_nil(state.current_party) and
            in_path?(state.path, ["Country"]) ->
          {party_type, party_data} = state.current_party
          %{state | current_party: {party_type, Map.put(party_data, :country, text)}}

        local_name == "CompanyID" and not is_nil(state.current_party) and
            in_path?(state.path, ["PartyTaxScheme"]) ->
          {party_type, party_data} = state.current_party
          %{state | current_party: {party_type, Map.put(party_data, :vat, text)}}

        local_name == "ElectronicMail" and not is_nil(state.current_party) ->
          {party_type, party_data} = state.current_party
          %{state | current_party: {party_type, Map.put(party_data, :email, text)}}

        (local_name == "Party" or local_name == "SenderParty" or local_name == "ReceiverParty") and
            not is_nil(state.current_party) ->
          {party_type, party_data} = state.current_party

          clean_party =
            party_data |> Enum.reject(fn {_, v} -> v == nil or v == "" end) |> Enum.into(%{})

          %{state | result: Map.put(state.result, party_type, clean_party), current_party: nil}

        # Line items
        local_name == "Name" and not is_nil(state.current_line) and in_path?(state.path, ["Item"]) ->
          %{state | current_line: Map.put(state.current_line, :name, text)}

        local_name == "InvoicedQuantity" and not is_nil(state.current_line) ->
          %{state | current_line: Map.put(state.current_line, :quantity_text, text)}

        local_name == "CreditedQuantity" and not is_nil(state.current_line) ->
          %{state | current_line: Map.put(state.current_line, :quantity_text, text)}

        local_name == "PriceAmount" and not is_nil(state.current_line) and
            in_path?(state.path, ["Price"]) ->
          %{state | current_line: Map.put(state.current_line, :price_text, text)}

        local_name == "Percent" and not is_nil(state.current_line) and
            in_path?(state.path, ["ClassifiedTaxCategory"]) ->
          %{state | current_line: Map.put(state.current_line, :vat_text, text)}

        local_name == "LineExtensionAmount" and not is_nil(state.current_line) ->
          %{state | current_line: Map.put(state.current_line, :line_total_text, text)}

        local_name == "InvoiceLine" or local_name == "CreditNoteLine" ->
          finalize_line_item(state)

        # Attachments
        local_name == "ID" and not is_nil(state.current_attachment) ->
          attachment = state.current_attachment |> Map.put(:filename, text)
          %{state | current_attachment: attachment}

        local_name == "EmbeddedDocumentBinaryObject" and not is_nil(state.current_attachment) ->
          attachment = state.current_attachment |> Map.put(:data, text)
          %{state | current_attachment: attachment}

        local_name == "AdditionalDocumentReference" and not is_nil(state.current_attachment) ->
          attachment = state.current_attachment

          if attachment[:data] && attachment[:data] != "" do
            %{state | attachments: [attachment | state.attachments], current_attachment: nil}
          else
            %{state | current_attachment: nil}
          end

        true ->
          state
      end

    {:ok, %{new_state | path: tl(state.path)}}
  end

  @impl Saxy.Handler
  def handle_event(:characters, chars, state) do
    {:ok, %{state | current_text: state.current_text <> chars}}
  end

  defp set_document_type(state, "Invoice"),
    do: %{
      state
      | document_type: :invoice,
        result: state.result |> Map.put(:type, :invoice) |> Map.put(:expires, nil)
    }

  defp set_document_type(state, "CreditNote"),
    do: %{state | document_type: :credit, result: Map.put(state.result, :type, :credit)}

  defp set_document_type(state, "ApplicationResponse"),
    do: %{
      state
      | document_type: :application_response,
        result: Map.put(state.result, :type, :application_response)
    }

  defp local_name_from_qname(name) when is_binary(name) do
    case String.split(name, ":") do
      [_ns, local] -> local
      [local] -> local
    end
  end

  defp get_attribute(attributes, attr_name) do
    Enum.find_value(attributes, fn {name, value} ->
      if local_name_from_qname(name) == attr_name, do: value
    end)
  end

  defp in_path?(path, elements) do
    Enum.any?(elements, fn elem -> elem in path end)
  end

  defp put_result(state, key, value) do
    %{state | result: Map.put(state.result, key, value)}
  end

  defp maybe_add(map, _key, []), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp parse_date(date_string) when is_binary(date_string) and date_string != "" do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp parse_document_id(id) when is_binary(id) do
    id |> String.split("/", trim: true) |> List.last()
  end

  defp parse_street_housenumber(street_full) when is_binary(street_full) do
    case Regex.run(~r/^(.+?)\s+(\d+.*)$/, street_full) do
      [_, street, number] -> {street, number}
      _ -> {street_full, ""}
    end
  end

  defp parse_street_housenumber(_), do: {"", ""}

  defp finalize_line_item(state) do
    line = state.current_line

    quantity = safe_float(line[:quantity_text])
    price = safe_float(line[:price_text])
    vat_percent = safe_float(line[:vat_text])
    line_total = safe_float(line[:line_total_text])
    tax_category = Map.get(line, :tax_category)

    discount = calculate_discount(quantity, price, line_total)

    completed_line =
      %{
        name: line[:name],
        quantity: safe_decimal(quantity),
        price: safe_decimal(price),
        vat: safe_decimal(vat_percent),
        discount: discount
      }
      |> maybe_add_tax_category(tax_category)

    %{state | line_items: [completed_line | state.line_items], current_line: nil}
  end

  defp maybe_add_tax_category(line, nil), do: line
  defp maybe_add_tax_category(line, :standard), do: line
  defp maybe_add_tax_category(line, tax_category), do: Map.put(line, :tax_category, tax_category)

  defp safe_float(nil), do: 0.0
  defp safe_float(""), do: 0.0

  defp safe_float(text) when is_binary(text) do
    case Float.parse(text) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  defp safe_decimal(value) when is_number(value), do: Decimal.from_float(value)
  defp safe_decimal(_), do: Decimal.new("0.00")

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
end
