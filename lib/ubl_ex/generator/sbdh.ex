defmodule UblEx.Generator.SBDH do
  @moduledoc """
  Generate Standard Business Document Header (SBDH) wrappers for UBL documents.

  SBDH is used in Peppol networks for routing and identification of business documents.
  """

  @doc """
  Wrap UBL XML content with an SBDH header.

  ## Parameters

    * `ubl_xml` - The UBL XML content to wrap (as string)
    * `document_data` - Map containing:
      - `:type` - Document type (`:invoice`, `:credit`, `:application_response`)
      - `:number` or `:id` - Document identifier
      - `:date` - Document date
      - `:supplier` or `:sender` - Map with `:endpoint_id` and `:scheme`
      - `:customer` or `:receiver` - Map with `:endpoint_id` and `:scheme`
      - `:country` - Optional country code (defaults from supplier/sender)

  ## Example

      ubl_xml = UblEx.generate(document_data)
      sbdh_xml = UblEx.Generator.SBDH.wrap(ubl_xml, document_data)
  """
  @spec wrap(String.t(), map()) :: String.t()
  def wrap(ubl_xml, document_data) do
    # Extract sender/receiver info
    sender = Map.get(document_data, :supplier) || Map.get(document_data, :sender)
    receiver = Map.get(document_data, :customer) || Map.get(document_data, :receiver)

    sender_id = "#{sender.scheme}:#{sender.endpoint_id}"
    # For receivers (customers), use endpoint_id if available, otherwise derive from VAT
    receiver_id =
      if Map.has_key?(receiver, :endpoint_id) and Map.has_key?(receiver, :scheme) do
        "#{receiver.scheme}:#{receiver.endpoint_id}"
      else
        # Use VAT number without country prefix as endpoint_id
        vat_number = receiver.vat |> String.replace(~r/^[A-Z]{2}/, "")
        scheme = Map.get(receiver, :scheme, "0208")
        "#{scheme}:#{vat_number}"
      end

    # Get document metadata
    doc_type = document_type_name(document_data.type)
    instance_id = Map.get(document_data, :number) || Map.get(document_data, :id, "UNKNOWN")
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    country = Map.get(document_data, :country) || Map.get(sender, :country, "BE")

    # Get document standard URN
    standard_urn = document_standard(document_data.type)
    profile_id = profile_identifier(document_data.type)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <sh:StandardBusinessDocument xmlns:sh="http://www.unece.org/cefact/namespaces/StandardBusinessDocumentHeader">
      <sh:StandardBusinessDocumentHeader>
        <sh:HeaderVersion>1.0</sh:HeaderVersion>
        <sh:Sender>
          <sh:Identifier Authority="iso6523-actorid-upis">#{sender_id}</sh:Identifier>
        </sh:Sender>
        <sh:Receiver>
          <sh:Identifier Authority="iso6523-actorid-upis">#{receiver_id}</sh:Identifier>
        </sh:Receiver>
        <sh:DocumentIdentification>
          <sh:Standard>#{standard_urn}</sh:Standard>
          <sh:TypeVersion>2.1</sh:TypeVersion>
          <sh:InstanceIdentifier>#{instance_id}</sh:InstanceIdentifier>
          <sh:Type>#{doc_type}</sh:Type>
          <sh:CreationDateAndTime>#{timestamp}</sh:CreationDateAndTime>
        </sh:DocumentIdentification>
        <sh:BusinessScope>
          <sh:Scope>
            <sh:Type>DOCUMENTID</sh:Type>
            <sh:InstanceIdentifier>#{profile_id}</sh:InstanceIdentifier>
            <sh:Identifier>busdox-docid-qns</sh:Identifier>
          </sh:Scope>
          <sh:Scope>
            <sh:Type>PROCESSID</sh:Type>
            <sh:InstanceIdentifier>#{process_identifier(document_data.type)}</sh:InstanceIdentifier>
            <sh:Identifier>cenbii-procid-ubl</sh:Identifier>
          </sh:Scope>
          <sh:Scope>
            <sh:Type>COUNTRY_C1</sh:Type>
            <sh:InstanceIdentifier>#{country}</sh:InstanceIdentifier>
          </sh:Scope>
        </sh:BusinessScope>
      </sh:StandardBusinessDocumentHeader>
      #{strip_xml_declaration(ubl_xml)}
    </sh:StandardBusinessDocument>
    """
  end

  defp document_type_name(:invoice), do: "Invoice"
  defp document_type_name(:credit), do: "CreditNote"
  defp document_type_name(:application_response), do: "ApplicationResponse"

  defp document_standard(:invoice), do: "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
  defp document_standard(:credit), do: "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2"

  defp document_standard(:application_response),
    do: "urn:oasis:names:specification:ubl:schema:xsd:ApplicationResponse-2"

  defp profile_identifier(:invoice),
    do:
      "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2::Invoice##urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0::2.1"

  defp profile_identifier(:credit),
    do:
      "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2::CreditNote##urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0::2.1"

  defp profile_identifier(:application_response),
    do:
      "urn:oasis:names:specification:ubl:schema:xsd:ApplicationResponse-2::ApplicationResponse##urn:fdc:peppol.eu:poacc:trns:invoice_response:3::2.1"

  defp process_identifier(:invoice), do: "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"
  defp process_identifier(:credit), do: "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"

  defp process_identifier(:application_response),
    do: "urn:fdc:peppol.eu:poacc:bis:invoice_response:3"

  defp strip_xml_declaration(xml) do
    xml
    |> String.replace(~r/^<\?xml[^?]*\?>\s*/, "")
    |> String.trim()
  end
end
