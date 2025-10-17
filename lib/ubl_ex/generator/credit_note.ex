defmodule UblEx.Generator.CreditNote do
  @moduledoc """
  Generate Peppol-compliant UBL CreditNote XML documents.
  """

  alias UblEx.Generator.Helpers

  @doc """
  Generate a UBL CreditNote XML document.
  """
  def generate(document_data) do
    attachments_xml = generate_attachments(document_data)
    number = document_data.number
    customer = document_data.customer
    supplier = document_data.supplier
    reverse_charge = Map.get(document_data, :reverse_charge, false)
    vat_number = Helpers.vat_number(customer.vat)
    customer_endpoint_id = Map.get(customer, :endpoint_id, vat_number)
    customer_scheme = Map.get(customer, :scheme, "0208")

    totals = Helpers.ubl_totals(document_data.details)

    credit_note_lines =
      document_data.details
      |> Enum.with_index(1)
      |> Enum.reverse()
      |> Enum.reduce([], fn {detail, index}, agg ->
        total_ex = Helpers.ubl_line_total(detail)
        vat_amount = Decimal.mult(total_ex, detail.vat) |> Decimal.div(100) |> Decimal.round(2)
        [%{index: index, detail: detail, total_ex: total_ex, vat_amount: vat_amount} | agg]
      end)
      |> Enum.map(&credit_note_line(&1, reverse_charge))

    billing_references = Map.get(document_data, :billing_references, [])
    order_reference = Map.get(document_data, :order_reference, "NA")

    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <CreditNote xmlns:cec="urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2" xmlns="urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:ns5="urn:oasis:names:specification:ubl:schema:xsd:SignatureBasicComponents-2">
    <cbc:UBLVersionID>2.1</cbc:UBLVersionID>
    <cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0</cbc:CustomizationID>
    <cbc:ProfileID>urn:fdc:peppol.eu:2017:poacc:billing:01:1.0</cbc:ProfileID>
    <cbc:ID>V01/#{number}</cbc:ID>
    <cbc:IssueDate>#{document_data.date}</cbc:IssueDate>
    <cbc:CreditNoteTypeCode>381</cbc:CreditNoteTypeCode>
    <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
    <cac:OrderReference>
        <cbc:ID>#{order_reference}</cbc:ID>
    </cac:OrderReference>
    #{Helpers.billing_reference(billing_references)}
    #{attachments_xml}
    <cac:AdditionalDocumentReference>
        <cbc:ID>UBL.BE</cbc:ID>
        <cbc:DocumentDescription>Invoicing Software v1.0</cbc:DocumentDescription>
    </cac:AdditionalDocumentReference>
    <cac:AccountingSupplierParty>
        <cac:Party>
            <cbc:EndpointID schemeID="#{supplier.scheme || "0208"}">#{supplier.endpoint_id}</cbc:EndpointID>
            <cac:PartyName>
                <cbc:Name>#{Helpers.escape(supplier.name)}</cbc:Name>
            </cac:PartyName>
            <cac:PostalAddress>
                <cbc:StreetName>#{Helpers.escape(supplier.street)}</cbc:StreetName>
                <cbc:CityName>#{Helpers.escape(supplier.city)}</cbc:CityName>
                <cbc:PostalZone>#{supplier.zipcode}</cbc:PostalZone>
                <cac:Country>
                    <cbc:IdentificationCode>#{supplier.country}</cbc:IdentificationCode>
                </cac:Country>
            </cac:PostalAddress>
            <cac:PartyTaxScheme>
                <cbc:CompanyID>#{supplier.vat}</cbc:CompanyID>
                <cac:TaxScheme>
                    <cbc:ID>VAT</cbc:ID>
                </cac:TaxScheme>
            </cac:PartyTaxScheme>
            <cac:PartyLegalEntity>
                <cbc:RegistrationName>#{Helpers.escape(supplier.name)}</cbc:RegistrationName>
                <cbc:CompanyID>#{supplier.endpoint_id}</cbc:CompanyID>
            </cac:PartyLegalEntity>
            <cac:Contact>
                <cbc:ElectronicMail>#{supplier.email}</cbc:ElectronicMail>
            </cac:Contact>
        </cac:Party>
    </cac:AccountingSupplierParty>
    <cac:AccountingCustomerParty>
        <cac:Party>
            <cbc:EndpointID schemeID="#{customer_scheme}">#{Helpers.escape(customer_endpoint_id)}</cbc:EndpointID>
            <cac:PartyName>
                <cbc:Name>#{Helpers.escape(customer.name)}</cbc:Name>
            </cac:PartyName>
            <cac:PostalAddress>
                <cbc:StreetName>#{Helpers.escape(customer.street)} #{Helpers.escape(customer.housenumber)}</cbc:StreetName>
                <cbc:CityName>#{Helpers.escape(customer.city)}</cbc:CityName>
                <cbc:PostalZone>#{Helpers.escape(customer.zipcode)}</cbc:PostalZone>
                <cac:Country>
                    <cbc:IdentificationCode>#{customer.country}</cbc:IdentificationCode>
                </cac:Country>
            </cac:PostalAddress>
            <cac:PartyTaxScheme>
                <cbc:CompanyID>#{customer.country}#{vat_number}</cbc:CompanyID>
                <cac:TaxScheme>
                    <cbc:ID>VAT</cbc:ID>
                </cac:TaxScheme>
            </cac:PartyTaxScheme>
            <cac:PartyLegalEntity>
                <cbc:RegistrationName>#{Helpers.escape(customer.name)}</cbc:RegistrationName>
                <cbc:CompanyID>#{vat_number}</cbc:CompanyID>
            </cac:PartyLegalEntity>
        </cac:Party>
    </cac:AccountingCustomerParty>
    #{Helpers.delivery_terms(customer, true)}
    #{payment_means(document_data, supplier)}
    <cac:TaxTotal>
        <cbc:TaxAmount currencyID="EUR">#{Helpers.format(totals.vat)}</cbc:TaxAmount>
        #{Helpers.tax_totals(document_data.details, reverse_charge)}
    </cac:TaxTotal>
    <cac:LegalMonetaryTotal>
        <cbc:LineExtensionAmount currencyID="EUR">#{Helpers.format(totals.subtotal)}</cbc:LineExtensionAmount>
        <cbc:TaxExclusiveAmount currencyID="EUR">#{Helpers.format(totals.subtotal)}</cbc:TaxExclusiveAmount>
        <cbc:TaxInclusiveAmount currencyID="EUR">#{Helpers.format(totals.grand_total)}</cbc:TaxInclusiveAmount>
        <cbc:PayableAmount currencyID="EUR">#{Helpers.format(totals.grand_total)}</cbc:PayableAmount>
    </cac:LegalMonetaryTotal>
    #{credit_note_lines}
    </CreditNote>\
    """
  end

  defp credit_note_line(line, reverse_charge) do
    detail = line.detail

    allowance_charge =
      if Decimal.gt?(detail.discount, 0), do: Helpers.allowance_charge_xml(detail), else: ""

    """
    <cac:CreditNoteLine>
        <cbc:ID>#{line.index}</cbc:ID>
        <cbc:CreditedQuantity unitCode="NAR">#{detail.quantity}</cbc:CreditedQuantity>
        <cbc:LineExtensionAmount currencyID="EUR">#{Helpers.format(line.total_ex)}</cbc:LineExtensionAmount>#{allowance_charge}
        <cac:Item>
            <cbc:Description>#{Helpers.escape(detail.name)}</cbc:Description>
            <cbc:Name>#{Helpers.escape(detail.name)}</cbc:Name>
            <cac:ClassifiedTaxCategory>
                #{Helpers.tax(detail.vat, reverse_charge)}
                <cac:TaxScheme>
                    <cbc:ID>VAT</cbc:ID>
                </cac:TaxScheme>
            </cac:ClassifiedTaxCategory>
        </cac:Item>
        <cac:Price>
            <cbc:PriceAmount currencyID="EUR">#{Helpers.format(detail.price)}</cbc:PriceAmount>
        </cac:Price>
    </cac:CreditNoteLine>\
    """
  end

  defp generate_attachments(document_data) do
    case Map.get(document_data, :attachments) do
      attachments when is_list(attachments) and length(attachments) > 0 ->
        attachments
        |> Enum.map(&generate_attachment_xml/1)
        |> Enum.join("\n    ")

      _ ->
        ""
    end
  end

  defp generate_attachment_xml(%{filename: filename, mime_type: mime_type, data: data})
       when is_binary(data) do
    """
    <cac:AdditionalDocumentReference>
        <cbc:ID>#{Helpers.escape(filename)}</cbc:ID>
        <cbc:DocumentDescription>Attachment</cbc:DocumentDescription>
        <cac:Attachment>
            <cbc:EmbeddedDocumentBinaryObject mimeCode="#{mime_type}" filename="#{Helpers.escape(filename)}">#{data}</cbc:EmbeddedDocumentBinaryObject>
        </cac:Attachment>
    </cac:AdditionalDocumentReference>\
    """
  end

  defp generate_attachment_xml(_), do: ""

  defp payment_means(document_data, supplier) do
    payment_id = Map.get(document_data, :payment_id)
    # IBAN is optional - if not provided, use empty string which is valid for non-SEPA payments
    iban = supplier[:iban] || ""

    payment_id_xml =
      if payment_id, do: "<cbc:PaymentID>#{Helpers.escape(payment_id)}</cbc:PaymentID>", else: ""

    """
    <cac:PaymentMeans>
        <cbc:PaymentMeansCode>58</cbc:PaymentMeansCode>
        #{payment_id_xml}
        <cac:PayeeFinancialAccount>
            <cbc:ID>#{Helpers.escape(iban)}</cbc:ID>
        </cac:PayeeFinancialAccount>
    </cac:PaymentMeans>\
    """
  end
end
