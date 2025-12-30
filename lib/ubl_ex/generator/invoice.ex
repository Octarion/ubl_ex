defmodule UblEx.Generator.Invoice do
  @moduledoc """
  Generate Peppol-compliant UBL Invoice XML documents.
  """

  alias UblEx.Generator.Helpers

  @doc """
  Generate a UBL Invoice XML document.
  """
  def generate(document_data) do
    attachments_xml = generate_attachments(document_data)
    note_xml = generate_note(document_data)
    number = document_data.number
    customer = document_data.customer
    supplier = document_data.supplier
    vat_number = Helpers.vat_number(customer.vat)
    customer_endpoint_id = Map.get(customer, :endpoint_id, vat_number)
    customer_scheme = Helpers.party_scheme(customer)

    totals = Helpers.ubl_totals(document_data.details)

    invoice_lines =
      document_data.details
      |> Enum.with_index(1)
      |> Enum.reverse()
      |> Enum.reduce([], fn {detail, index}, agg ->
        total_ex = Helpers.ubl_line_total(detail)
        vat_amount = Decimal.mult(total_ex, detail.vat) |> Decimal.div(100) |> Decimal.round(2)
        [%{index: index, detail: detail, total_ex: total_ex, vat_amount: vat_amount} | agg]
      end)
      |> Enum.map(&invoice_line/1)

    order_reference = Map.get(document_data, :order_reference, "NA")

    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Invoice xmlns:cec="urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2" xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:ns5="urn:oasis:names:specification:ubl:schema:xsd:SignatureBasicComponents-2">
    <cbc:UBLVersionID>2.1</cbc:UBLVersionID>
    <cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0</cbc:CustomizationID>
    <cbc:ProfileID>urn:fdc:peppol.eu:2017:poacc:billing:01:1.0</cbc:ProfileID>
    <cbc:ID>#{number}</cbc:ID>
    <cbc:IssueDate>#{document_data.date}</cbc:IssueDate>
    <cbc:DueDate>#{document_data.expires}</cbc:DueDate>
    <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>
    #{note_xml}<cbc:TaxPointDate>#{document_data.date}</cbc:TaxPointDate>
    <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
    <cac:OrderReference>
        <cbc:ID>#{order_reference}</cbc:ID>
    </cac:OrderReference>
    #{attachments_xml}
    <cac:AdditionalDocumentReference>
        <cbc:ID>UBL.BE</cbc:ID>
        <cbc:DocumentDescription>Invoicing Software v1.0</cbc:DocumentDescription>
    </cac:AdditionalDocumentReference>
    <cac:AccountingSupplierParty>
        <cac:Party>
            <cbc:EndpointID schemeID="#{Helpers.party_scheme(supplier)}">#{supplier.endpoint_id}</cbc:EndpointID>
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
                <cbc:CompanyID>#{customer.vat}</cbc:CompanyID>
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
    #{Helpers.delivery_terms(customer, false)}
    #{payment_means(document_data, supplier)}
    #{payment_terms(document_data)}
    <cac:TaxTotal>
        <cbc:TaxAmount currencyID="EUR">#{Helpers.format(totals.vat)}</cbc:TaxAmount>
        #{Helpers.tax_totals(document_data.details)}
    </cac:TaxTotal>
    <cac:LegalMonetaryTotal>
        <cbc:LineExtensionAmount currencyID="EUR">#{Helpers.format(totals.subtotal)}</cbc:LineExtensionAmount>
        <cbc:TaxExclusiveAmount currencyID="EUR">#{Helpers.format(totals.subtotal)}</cbc:TaxExclusiveAmount>
        <cbc:TaxInclusiveAmount currencyID="EUR">#{Helpers.format(totals.grand_total)}</cbc:TaxInclusiveAmount>
        <cbc:PayableAmount currencyID="EUR">#{Helpers.format(totals.grand_total)}</cbc:PayableAmount>
    </cac:LegalMonetaryTotal>
    #{invoice_lines}
    </Invoice>\
    """
  end

  defp invoice_line(line) do
    detail = line.detail
    tax_category = Helpers.infer_tax_category(detail)

    allowance_charge =
      if Decimal.gt?(detail.discount, 0), do: Helpers.allowance_charge_xml(detail), else: ""

    line_note =
      case Map.get(detail, :note) do
        note when is_binary(note) and note != "" ->
          "\n        <cbc:Note>#{Helpers.escape(note)}</cbc:Note>"

        _ ->
          ""
      end

    """
    <cac:InvoiceLine>
        <cbc:ID>#{line.index}</cbc:ID>#{line_note}
        <cbc:InvoicedQuantity unitCode="NAR">#{detail.quantity}</cbc:InvoicedQuantity>
        <cbc:LineExtensionAmount currencyID="EUR">#{Helpers.format(line.total_ex)}</cbc:LineExtensionAmount>#{allowance_charge}
        <cac:Item>
            <cbc:Description>#{Helpers.escape(detail.name)}</cbc:Description>
            <cbc:Name>#{Helpers.escape(detail.name)}</cbc:Name>
            <cac:ClassifiedTaxCategory>
                #{Helpers.tax(detail.vat, tax_category)}
                <cac:TaxScheme>
                    <cbc:ID>VAT</cbc:ID>
                </cac:TaxScheme>
            </cac:ClassifiedTaxCategory>
        </cac:Item>
        <cac:Price>
            <cbc:PriceAmount currencyID="EUR">#{Helpers.format(detail.price)}</cbc:PriceAmount>
        </cac:Price>
    </cac:InvoiceLine>\
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

  defp generate_note(document_data) do
    case Map.get(document_data, :note) do
      note when is_binary(note) and note != "" ->
        "<cbc:Note>#{Helpers.escape(note)}</cbc:Note>\n    "

      _ ->
        ""
    end
  end

  defp payment_means(document_data, supplier) do
    payment_id = Map.get(document_data, :payment_id)
    iban = supplier[:iban] || ""

    payment_means_code =
      case Map.get(document_data, :payment_means_code) do
        code when is_binary(code) and code != "" -> code
        _ -> if iban != "", do: "58", else: "1"
      end

    payment_id_xml =
      if payment_id, do: "<cbc:PaymentID>#{Helpers.escape(payment_id)}</cbc:PaymentID>", else: ""

    """
    <cac:PaymentMeans>
        <cbc:PaymentMeansCode>#{payment_means_code}</cbc:PaymentMeansCode>
        #{payment_id_xml}
        <cac:PayeeFinancialAccount>
            <cbc:ID>#{Helpers.escape(iban)}</cbc:ID>
        </cac:PayeeFinancialAccount>
    </cac:PaymentMeans>\
    """
  end

  defp payment_terms(document_data) do
    case Map.get(document_data, :payment_terms) do
      terms when is_binary(terms) and terms != "" ->
        """
        <cac:PaymentTerms>
            <cbc:Note>#{Helpers.escape(terms)}</cbc:Note>
        </cac:PaymentTerms>\
        """

      _ ->
        ""
    end
  end
end
