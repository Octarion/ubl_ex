defmodule UblEx.Generator.ApplicationResponse do
  @moduledoc """
  Generator for Peppol BIS Billing 3.0 compliant ApplicationResponse (message acknowledgment) documents.

  Application responses are used to acknowledge receipt and processing status of invoices and credit notes.
  """

  alias UblEx.Generator.Helpers

  @doc """
  Generate a Peppol-compliant UBL ApplicationResponse XML document.

  ## Parameters

    * `document_data` - Map containing:
      - `:id` - Unique response ID
      - `:date` - Response date (Date struct)
      - `:response_code` - Status code (e.g., "AB" for acknowledged, "RE" for rejected)
      - `:document_reference` - ID of the document being acknowledged
      - `:sender` - Map with `:endpoint_id`, `:scheme`, `:name`
      - `:receiver` - Map with `:endpoint_id`, `:scheme`, `:name`
      - `:status_reason` - Optional reason text
      - `:note` - Optional note

  ## Response Codes

    * `AB` - Acknowledged / Accepted
    * `RE` - Rejected
    * `AP` - Accepted with errors
    * `CA` - Conditionally accepted
    * `PD` - Paid
    * `IP` - In process
    * `UQ` - Under query

  ## Example

      document_data = %{
        id: "RESPONSE-001",
        date: ~D[2025-06-02],
        response_code: "AB",
        document_reference: "INV-123",
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

      xml = UblEx.Generator.ApplicationResponse.generate(document_data)
  """
  @spec generate(map()) :: String.t()
  def generate(document_data) do
    id = Map.get(document_data, :id, "UNKNOWN")
    date = Map.get(document_data, :date, Date.utc_today()) |> Date.to_iso8601()
    response_code = Map.get(document_data, :response_code, "AB")
    document_reference = Map.get(document_data, :document_reference, "")
    status_reason = Map.get(document_data, :status_reason, "")
    note = Map.get(document_data, :note, "")

    sender = Map.get(document_data, :sender, %{})
    receiver = Map.get(document_data, :receiver, %{})

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <ApplicationResponse xmlns="urn:oasis:names:specification:ubl:schema:xsd:ApplicationResponse-2"
                         xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
                         xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        <cbc:CustomizationID>urn:fdc:peppol.eu:poacc:trns:invoice_response:3</cbc:CustomizationID>
        <cbc:ProfileID>urn:fdc:peppol.eu:poacc:bis:invoice_response:3</cbc:ProfileID>
        <cbc:ID>#{Helpers.escape(id)}</cbc:ID>
        <cbc:IssueDate>#{date}</cbc:IssueDate>#{generate_note(note)}
        <cac:SenderParty>
            #{generate_party(sender)}
        </cac:SenderParty>
        <cac:ReceiverParty>
            #{generate_party(receiver)}
        </cac:ReceiverParty>
        <cac:DocumentResponse>
            <cac:Response>
                <cbc:ResponseCode listID="UNCL4343OpSubset">#{Helpers.escape(response_code)}</cbc:ResponseCode>#{generate_status_reason(status_reason)}
            </cac:Response>
            <cac:DocumentReference>
                <cbc:ID>#{Helpers.escape(document_reference)}</cbc:ID>
                <cbc:DocumentTypeCode listID="UNCL1001">380</cbc:DocumentTypeCode>
            </cac:DocumentReference>
        </cac:DocumentResponse>
    </ApplicationResponse>
    """
  end

  defp generate_party(%{endpoint_id: endpoint_id, scheme: scheme, name: name}) do
    """
    <cbc:EndpointID schemeID="#{Helpers.escape(scheme)}">#{Helpers.escape(endpoint_id)}</cbc:EndpointID>
            <cac:PartyIdentification>
                <cbc:ID schemeID="#{Helpers.escape(scheme)}">#{Helpers.escape(endpoint_id)}</cbc:ID>
            </cac:PartyIdentification>
            <cac:PartyLegalEntity>
                <cbc:RegistrationName>#{Helpers.escape(name)}</cbc:RegistrationName>
            </cac:PartyLegalEntity>\
    """
  end

  defp generate_party(_), do: ""

  defp generate_note(""), do: ""
  defp generate_note(nil), do: ""

  defp generate_note(note) do
    """

        <cbc:Note>#{Helpers.escape(note)}</cbc:Note>\
    """
  end

  defp generate_status_reason(""), do: ""
  defp generate_status_reason(nil), do: ""

  defp generate_status_reason(reason) do
    """

                <cbc:StatusReason>#{Helpers.escape(reason)}</cbc:StatusReason>\
    """
  end
end
