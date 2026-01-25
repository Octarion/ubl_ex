# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.7] - 2026-01-25

### Changed
- Made optional fields truly optional per Peppol BIS 3.0 specification:
  - Supplier: `street`, `city`, `zipcode`, `vat`, `email` are now optional
  - Customer: `street`, `housenumber`, `city`, `zipcode`, `vat` are now optional
  - Only `endpoint_id`, `name`, and `country` are required for parties

## [0.7.6] - 2026-01-15

### Added
- `tax_subtotals` field in parsed results exposing VAT breakdown per rate
  - Each subtotal includes `percentage`, `taxable_amount`, and `tax_amount`
  - Useful for invoices with multiple VAT rates

## [0.7.5] - 2026-01-09

### Added
- `UblEx.strip_sbdh/1` function to remove StandardBusinessDocument/StandardBusinessDocumentHeader wrapper from UBL XML
  - Useful for accounting software that cannot process SBDH-wrapped documents
  - Extracts the inner UBL document (Invoice, CreditNote, or ApplicationResponse)
  - Returns unchanged XML if no SBDH wrapper is present
  - Parsed results are identical whether SBDH is present or stripped

## [0.7.4] - 2025-12-30

### Added
- Support for `cbc:Note` elements in invoices and credit notes per Peppol BIS 3.0:
  - Document-level note (0..1) - Optional note at invoice/credit note root level
  - Line-level note (0..1) - Optional note on individual invoice/credit note lines
  - Payment terms (0..1) - Optional `cac:PaymentTerms` with required `cbc:Note` describing payment conditions
- Generator support for all three note types
- Parser support for extracting all three note types
- Full round-trip support for notes (parse → generate → parse)

## [0.7.3] - 2025-12-29

### Fixed
- VAT rounding error when multiple line items share the same VAT rate
  - Previously: VAT calculated per line, then summed (e.g., 14.89 + 14.89 + 14.89 = 44.67)
  - Now: Lines grouped by VAT rate, summed, then VAT calculated once (e.g., (70.92 + 70.92 + 70.92) × 21% = 44.68)
  - Fixes 1 cent discrepancies in grand totals caused by cumulative rounding errors
  - Affects both `ubl_totals/1` and `tax_totals/1` functions in `UblEx.Generator.Helpers`

## [0.7.2] - 2025-12-29

### Added
- Parser now extracts monetary totals from UBL documents, eliminating need for users to recalculate:
  - `tax_amount` - Total tax/VAT amount from TaxTotal element
  - `line_extension_amount` - Sum of all line totals before tax
  - `tax_exclusive_amount` - Total amount before tax (after allowances/charges)
  - `tax_inclusive_amount` - Total amount including tax
  - `payable_amount` - Final amount to be paid
  - `allowance_total_amount` - Total discounts/allowances (optional)
  - `charge_total_amount` - Total additional charges (optional)
  - `prepaid_amount` - Amount already paid (optional)
  - All monetary values returned as `Decimal` types for precision

### Changed
- Updated credo from 1.7.13 to 1.7.15
- Updated ex_doc from 0.39.1 to 0.39.3

## [0.7.1] - 2025-12-15

### Fixed
- Division by zero error when generating invoices with 100% discount
  - Previously: `allowance_charge_xml/1` tried to reverse-calculate base amount from discounted total, causing crash with 100% discount (0 / 0)
  - Now: Base amount calculated directly as `quantity × price`, which works for any discount percentage including 100%

## [0.7.0] - 2025-11-25

### Changed
- **BREAKING:** Tax exemption fields now required for exempt/export/intra-community/reverse charge transactions per Peppol BIS 3.0 validation rules (BR-O-11 through BR-O-14)
  - Previously: Tax categories E, G, K, AE generated without exemption reason fields
  - Now: Must provide `tax_exemption_reason_code` and `tax_exemption_reason` for these categories
  - Migration: Add VATEX codes and reasons to line items with tax_category `:exempt`, `:export`, `:intra_community`, or `:reverse_charge`
  - Example: `tax_exemption_reason_code: "vatex-eu-ic", tax_exemption_reason: "Intra-community supply - Article 138 Directive 2006/112/EC"`
  - Not required for: Standard VAT (S), zero-rated (Z), or outside scope (O) categories

### Added
- Tax exemption field support on line items:
  - `tax_exemption_reason_code` - VATEX code (e.g., "vatex-eu-ic", "vatex-eu-ae", "vatex-eu-g")
  - `tax_exemption_reason` - Human-readable explanation
- Generator now includes exemption fields in TaxSubtotal sections when provided
- Parser extracts exemption fields from TaxSubtotal and applies them to matching line items
- Full round-trip support for exemption fields
- Documentation with link to official Peppol VATEX code list
- Comprehensive test coverage for all exemption scenarios

## [0.6.1] - 2025-11-24

### Fixed
- Customer VAT number now preserved as-is instead of being reconstructed from customer country
  - Previously: A Swiss customer with Belgian VAT `BE0123456749` would incorrectly become `CH0123456749`
  - Now: The original VAT number is used directly in the PartyTaxScheme/CompanyID element

### Added
- Automatic Peppol scheme inference from country code via `Helpers.infer_scheme/1` and `Helpers.party_scheme/1`
  - If `scheme` is not explicitly set, it is now inferred from the party's `country` field
  - Supports all EU member states with their primary Peppol scheme IDs
  - Falls back to `"0088"` (EAN/GLN) for unmapped countries

### Changed
- External validation tests (peppol.helger.com) are now excluded by default to avoid rate limiting
  - Run with `mix test --include external` to include validation tests

## [0.6.0] - 2025-11-24

### Changed
- **BREAKING:** Replaced `reverse_charge` boolean with `tax_category` atom for full Peppol BIS 3.0 tax category support
  - Previously: `reverse_charge: true` triggered tax category "K" (intra-community)
  - Now: Use `tax_category: :intra_community` for EU cross-border B2B transactions
  - Migration: Replace `reverse_charge: true` with `tax_category: :intra_community`
  - Migration: Remove `reverse_charge: false` (no replacement needed, `:standard` is the default)

### Added
- Full tax category support with descriptive atoms:
  - `:standard` (S) - Standard rated VAT (default for 6/12/21%)
  - `:zero_rated` (Z) - Zero rated goods (default for 0% VAT)
  - `:exempt` (E) - Exempt from tax
  - `:reverse_charge` (AE) - Domestic reverse charge
  - `:intra_community` (K) - EU cross-border B2B (intra-community supply)
  - `:export` (G) - Export outside EU
  - `:outside_scope` (O) - Services outside scope of tax
- Automatic inference: If `tax_category` not specified, defaults to `:standard` for non-zero VAT and `:zero_rated` for 0% VAT
- Parser now converts Peppol codes back to descriptive atoms for round-trip fidelity

## [0.5.0] - 2025-11-17

### Changed
- **BREAKING:** `reverse_charge` is now a per-line setting instead of document-wide
  - Previously: `reverse_charge` was set at the document level and applied to all line items
  - Now: `reverse_charge` must be set on individual line items in the `details` array
  - Migration: Move `reverse_charge: true` from document root to each applicable line item
  - Benefit: Allows mixing regular and reverse charge line items in the same invoice
  - Default: Line items without `reverse_charge` field default to `false`
  - Parser: Now extracts `reverse_charge` per line based on TaxCategory ID ("K" = reverse charge)

## [0.4.0] - 2025-10-17

### Added
- Optional UBL document validation against Peppol BIS Billing 3.0 rules
- `UblEx.Validator.validate/3` function for validating invoices and credit notes
- Integration with free peppol.helger.com validation web service
- Support for custom validation options (timeout, VESID override)
- Detailed error and warning reporting from validation service
- Optional `req` dependency for validation feature (not required for core functionality)

## [0.3.1] - 2025-10-17

### Fixed
- Fixed PaymentMeansCode roundtrip preservation - parser now captures original code, generator uses parsed value or intelligently defaults based on IBAN presence
- Fixed PaymentID roundtrip - parser now extracts PaymentID from PaymentMeans element
- Fixed IBAN roundtrip - parser now extracts and stores supplier IBAN in supplier data
- Fixed billing reference ID duplication - removed duplicate "F" prefix in generator template
- Fixed document ID preservation - parser now keeps full ID (e.g., "V01/F2025158") without stripping prefix, generator uses ID as-is

## [0.3.0] - 2025-10-17

### Added
- Configurable customer endpoint scheme via `customer.scheme` field (defaults to "0208")
- Explicit customer endpoint ID via `customer.endpoint_id` field (defaults to VAT number for backward compatibility)
- Support for different Peppol identifier schemes (e.g., "9925" for organization numbers, country-specific schemes)

## [0.2.0] - 2025-10-17

### Changed
- **BREAKING:** Migrated XML parsing from SweetXML to Saxy for improved performance
  - Direct SAX event handler eliminates XPath queries and intermediate DOM trees
  - Significantly faster parsing on large documents
- **BREAKING:** Removed `parse_xml/2` function - use `parse/1` instead
- **BREAKING:** Removed schema registry system (`register_schema/2`, `list_schemas/0`, `validate_xml/2`)
  - Parser now has hardcoded UBL structure knowledge instead of configurable schemas
- Simplified API to just 3 main functions: `parse/1`, `generate/1`, `generate_with_sbdh/1`

### Removed
- SweetXML dependency (replaced with Saxy)
- Old XPath-based parser infrastructure (1,185+ lines of code)
- Schema configuration system (no longer needed with direct handler)

### Fixed
- Invalid XML now returns `{:error, reason}` tuple instead of raising/exiting
- ApplicationResponse documents now properly parse `:id`, `:sender`, and `:receiver` fields
- SenderParty/ReceiverParty elements handled correctly (with or without nested Party elements)
- **BREAKING:** Credit notes no longer include `:expires` field (only invoices have DueDate per Peppol BIS Billing 3.0 spec)

### Performance
- 1,414x faster XML parsing on production-sized documents (890KB invoice with attachment)
- 90% memory reduction compared to SweetXML in production workloads
- 1,000 invoices/day: 37 minutes → 1.6 seconds of CPU time

## [0.1.0] - 2025-10-15

### Added
- UBL document generation for Invoices, Credit Notes, and Application Responses
- Peppol BIS Billing 3.0 compliance
- SBDH (Standard Business Document Header) generation for Peppol network transmission
- Full round-trip support for all document types (parse → generate → parse)
- Automatic SBDH parsing and unwrapping
- Attachment support for invoices and credit notes
- Auto-detection of document types (Invoice, CreditNote, ApplicationResponse)
- Namespace-agnostic XML parser with configurable schemas
- Schema registry for multiple XML formats
- Customer endpoint_id derivation from VAT for SBDH when not provided
