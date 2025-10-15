# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
