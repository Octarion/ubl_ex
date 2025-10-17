defmodule UblEx.Validator do
  @moduledoc """
  Validates UBL documents against Peppol BIS Billing 3.0 rules using the
  peppol.helger.com validation web service.

  This module provides an optional validation feature that requires the `req`
  dependency. The validation service is provided free of charge without SLA
  by Philip Helger.

  ## Usage

      # Validate an invoice
      xml = UblEx.generate(%{type: :invoice, ...})
      case UblEx.Validator.validate(xml, :invoice) do
        {:ok, result} -> IO.puts("Valid!")
        {:error, errors} -> IO.inspect(errors)
      end

      # Validate a credit note
      xml = UblEx.generate(%{type: :credit, ...})
      UblEx.Validator.validate(xml, :credit)

  ## Requirements

  Add `{:req, "~> 0.5.0"}` to your dependencies in mix.exs to use this module.
  """

  @endpoint "https://peppol.helger.com/wsdvs"

  @vesids %{
    invoice: "eu.peppol.bis3:invoice:3.13.0",
    credit: "eu.peppol.bis3:creditnote:3.13.0"
  }

  @doc """
  Validates a UBL document against Peppol BIS Billing 3.0 rules.

  ## Parameters

    - `xml` - The UBL XML document as a string
    - `type` - The document type (`:invoice` or `:credit`)
    - `opts` - Optional keyword list:
      - `:vesid` - Override the default VESID for the document type
      - `:timeout` - Request timeout in milliseconds (default: 30000)

  ## Returns

    - `{:ok, result}` - Validation successful, returns parsed result map
    - `{:error, reason}` - Validation failed or service error

  ## Examples

      iex> xml = File.read!("invoice.xml")
      iex> UblEx.Validator.validate(xml, :invoice)
      {:ok, %{success: true, errors: [], warnings: []}}

  """
  def validate(xml, type, opts \\ []) when type in [:invoice, :credit] do
    unless Code.ensure_loaded?(Req) do
      raise """
      UblEx.Validator requires the :req dependency.
      Add {:req, "~> 0.5.0"} to your mix.exs dependencies.
      """
    end

    vesid = Keyword.get(opts, :vesid, @vesids[type])
    timeout = Keyword.get(opts, :timeout, 30_000)

    soap_body = build_soap_request(xml, vesid)

    case Req.post(@endpoint,
           body: soap_body,
           headers: [
             {"content-type", "text/xml; charset=utf-8"},
             {"SOAPAction", ""}
           ],
           receive_timeout: timeout
         ) do
      {:ok, %{status: 200, body: response_body}} ->
        parse_response(response_body)

      {:ok, %{status: status, body: body}} ->
        # Return more details for debugging
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_soap_request(xml, vesid) do
    escaped_xml = escape_xml(xml)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/">
      <S:Body>
        <validateRequestInput xmlns="http://peppol.helger.com/ws/documentvalidationservice/201701/" VESID="#{vesid}" displayLocale="en">
          <XML>#{escaped_xml}</XML>
        </validateRequestInput>
      </S:Body>
    </S:Envelope>
    """
  end

  defp escape_xml(xml) do
    xml
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp parse_response(response_body) do
    # Extract validation success status
    success =
      case Regex.run(~r/validateResponseOutput[^>]*success="([^"]*)"/, response_body) do
        [_, "true"] -> true
        [_, "false"] -> false
        _ -> nil
      end

    if success == nil do
      {:error, "Unable to parse validation response"}
    else
      errors = extract_items(response_body, "ERROR")
      warnings = extract_items(response_body, "WARN")

      if success do
        {:ok, %{success: true, errors: errors, warnings: warnings}}
      else
        {:error, %{success: false, errors: errors, warnings: warnings}}
      end
    end
  end

  defp extract_items(xml, error_level) do
    # Extract error/warning messages from Item elements
    # Format: <Item errorLevel="ERROR" ... errorText="message" .../>
    regex = ~r/<Item[^>]*errorLevel="#{error_level}"[^>]*errorText="([^"]*)"[^>]*\/>/

    Regex.scan(regex, xml)
    |> Enum.map(fn [_, text] -> text end)
    |> Enum.map(&decode_xml_entities/1)
  end

  defp decode_xml_entities(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
  end
end
