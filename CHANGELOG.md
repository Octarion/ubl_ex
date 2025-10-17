# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
