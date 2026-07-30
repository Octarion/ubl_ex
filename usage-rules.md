# ubl_ex usage rules

Parse and generate Peppol BIS Billing 3.0 / UBL 2.1 documents (invoices, credit notes,
application responses). No Ash/Ecto dependency — plain maps in, XML strings out.

## Entry points

- `UblEx.parse/1` — parse any UBL XML with auto schema detection. Returns
  `{:ok, parsed_data}` or `{:error, reason}`. Always prefer this over `UblEx.parse_xml/2`
  unless you already know the schema.
- `UblEx.generate/1` — dispatches on the `:type` key (`:invoice`, `:credit`,
  `:application_response`) and returns an XML **string directly** — not `{:ok, xml}`.
  Only the error path is wrapped: `{:error, reason}` when `:type` is missing/unknown.
  Do not pattern-match `{:ok, xml} = UblEx.generate(data)`; check `is_binary/1` or match
  on `{:error, _}` first.
- `UblEx.generate_with_sbdh/1` — same as `generate/1` but wraps the result in an SBDH
  envelope for Peppol network transmission. Same string-or-`{:error, _}` return shape.
- `UblEx.strip_sbdh/1` — unwrap an SBDH-wrapped document back to plain UBL. Idempotent:
  safe to call on already-unwrapped XML.

## Money fields are `Decimal`, not float or string

`quantity`, `price`, `vat`, `discount` on every line item must be `Decimal.t()`
(e.g. `Decimal.new("21.00")`), never floats or bare numbers — floats lose the precision
Peppol validation checks against. `vat` and `discount` are **percentages**, not amounts.

## Tax category defaults and required exemption fields

`tax_category` on a line item defaults to `:standard` when `vat` is non-zero and
`:zero_rated` when `vat` is `Decimal.new("0.00")`. You rarely need to set it explicitly
for domestic standard-rated or zero-rated lines.

When `tax_category` is `:exempt`, `:export`, `:intra_community`, or `:reverse_charge`,
Peppol rules BR-O-11..14 require both `tax_exemption_reason_code` (a `vatex-{country}-{code}`
string, e.g. `"vatex-eu-ic"`) and `tax_exemption_reason` (human-readable) on that line item.
Omitting either when using one of these four categories produces XML that generates fine
but fails Peppol validation — this isn't caught until you call `UblEx.Validator.validate/2`.

## `scheme` is usually inferred — don't hardcode it

`supplier.scheme` / `customer.scheme` are optional; they're inferred from the party's
`country` field (e.g. `BE` → `"0208"`, `NL` → `"0106"`, unknown countries → `"0088"`).
Only set `scheme` explicitly when the party's Peppol identifier scheme doesn't match
their country (e.g. a VAT-based scheme in a country with a non-VAT default).

## Validator requires the optional `req` dependency

`UblEx.Validator.validate/2` calls the free `peppol.helger.com` service over HTTP and
needs `{:req, "~> 0.5.0 or ~> 0.6.0 or ~> 0.7.0"}` in the consuming app's deps — it is
declared `optional: true` in ubl_ex so libraries that only generate/parse don't pull in
an HTTP client. If `req` isn't present, calling `validate/2` raises immediately with a
message telling you to add it — it does not silently no-op.

- Validation hits the network; do not call it in hot paths or from tests without a
  network guard/tag (this repo tags its own live-service tests `:external`).
- The service has no SLA and rate-limits (HTTP 429 under load) — don't treat a 429 as a
  validation failure of the document.
- SBDH-wrapped XML cannot be validated directly — call `UblEx.strip_sbdh/1` first.
- Result shape: `{:ok, %{success: true, errors: [], warnings: [...]}}` on success,
  `{:error, %{success: false, errors: [...]}}` on validation failure — `warnings` can be
  non-empty even when `success: true`, so check `result.warnings` separately from the
  ok/error tuple.

## Round-tripping

`parse |> generate` is supported and should not lose data, but the output is a
**regenerated** document, not a byte-identical copy — don't diff raw XML strings to
check round-trip correctness; compare the parsed maps instead.

## Credit notes reference invoices by number, not by parsed struct

`billing_references` on a `:credit` document is a list of invoice **number strings**
(e.g. `["F2024001"]`), not the parsed invoice map.
