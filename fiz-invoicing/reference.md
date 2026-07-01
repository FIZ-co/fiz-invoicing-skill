# FIZ Public API — Full Reference

Complete field reference for the endpoints used to issue invoices. Base URL:
`https://api.fiz.co`. Auth header: `x-api-key`. All requests except the docs
require it.

The API validates with a strict whitelist: **unknown fields cause a 400**. Send
only the fields listed here.

---

## Customers

### `POST /customers`

| Field             | Type   | Required | Notes / example                         |
|-------------------|--------|----------|-----------------------------------------|
| `name`            | string | **yes**  | `"João Silva"`                          |
| `firstName`       | string | no       | `"João"`                                |
| `lastName`        | string | no       | `"Silva"`                               |
| `email`           | string | no       | valid email                             |
| `taxpayerNumber`  | string | no       | NIF, e.g. `"303741791"`                 |
| `country`         | string | no       | ISO 3166-1 alpha-2, default `"PT"`      |
| `phone`           | string | no       | `"+351912345678"`                       |
| `mobile`          | string | no       | `"+351912345678"`                       |
| `fax`             | string | no       | `"+351212345678"`                       |
| `address`         | string | no       | `"Rua das Flores, 123"`                 |
| `city`            | string | no       | `"Lisboa"`                              |
| `postalCode`      | string | no       | `"1000-100"`                            |
| `website`         | string | no       | `"https://example.com"`                 |
| `companyName`     | string | no       | `"Silva & Associados Lda"`              |
| `companyPosition` | string | no       | `"Diretor Geral"`                       |
| `description`     | string | no       | free text                               |
| `photo`           | string | no       | URL                                     |

Response: the created customer, including `id` (use as `customerId`).

### `GET /customers`, `GET /customers/:id`, `PATCH /customers/:id`, `DELETE /customers/:id`

List supports `?search=`. `PATCH` accepts any subset of the create fields.

---

## Items (products / services)

### `POST /items`

| Field                     | Type    | Required | Notes / values                                          |
|---------------------------|---------|----------|---------------------------------------------------------|
| `name`                    | string  | **yes**  | `"Consulting hour"`                                     |
| `type`                    | enum    | **yes**  | `PRODUCT` \| `SERVICE`                                  |
| `unitPrice`               | number  | **yes**  | ≥ 0, e.g. `80`                                          |
| `vatRate`                 | enum    | **yes**  | `NORMAL` \| `INTERMEDIATE` \| `REDUCED` \| `EXEMPT`     |
| `description`             | string  | no       |                                                         |
| `unitType`                | enum    | no       | `UNIT` \| `HOUR` \| `DAY` \| `MONTH` \| `WEEK` \| `BOX` \| `PACKAGE` \| `METER` \| `SQUARE_METER` \| `CUBIC_METER` \| `KILOGRAM` \| `LITER` \| `NA` |
| `vatTerritory`            | enum    | no       | e.g. `CONTINENTAL` (Portuguese territory)               |
| `taxRate`                 | number  | no       | percentage, ≥ 0, e.g. `23`                              |
| `vatExemptionReason`      | string  | no       | required when `vatRate` is `EXEMPT`; an `M`-code matching the legal reason — see `domain.md` |
| `termsOfPayment`          | string  | no       | `"Pagamento a 30 dias"`                                 |
| `isAutoVATEnabled`        | boolean | no       | default `false`                                         |
| `withholdingTaxAvailable` | boolean | no       | default `false`                                         |
| `withholdingTaxPercent`   | number  | no       | ≥ 0, e.g. `25`                                          |
| `withholdingTaxType`      | enum    | no       | `IRS` \| `IRC` \| `IS`                                  |
| `withholdingTaxReason`    | string  | no       | free text                                               |

Response: the created item, including `id` (use in the invoice `items` array).

### `GET /items`, `GET /items/:id`, `PATCH /items/:id`, `DELETE /items/:id`

List supports `?search=`. `PATCH` accepts any subset of the create fields.

---

## Invoices

### `POST /invoices` — create draft

| Field        | Type     | Required | Notes                                                     |
|--------------|----------|----------|-----------------------------------------------------------|
| `dueDate`    | string   | **yes**  | ISO 8601 w/ timezone, e.g. `2026-07-18T00:00:00.000Z`     |
| `cae`        | string   | **yes**  | Portuguese economic activity code, e.g. `"62010"`         |
| `type`       | enum     | **yes**  | see Document types below                                  |
| `customerId` | string   | **yes**  | customer `id`                                             |
| `items`      | array    | **yes**  | ≥ 1 element of `{ id: string, quantity: number ≥ 1 }`     |
| `notes`      | string   | no       | free-text note on the invoice                             |
| `seriesId`   | string   | no       | series `id` from `GET /series`; omit → account default. Malformed id → 400; well-formed but unknown id → 404 (no silent fallback) |
| `summary`    | object   | no       | global discount, see below                                |
| `payment`    | object   | no       | only for `INVOICE_RECEIPT` / `SIMPLIFIED_INVOICE`         |

The API sets `date` (now) and `currency` (`EUR`) itself — do not send them.

**`summary` object:**

| Field                   | Type   | Notes                                  |
|-------------------------|--------|----------------------------------------|
| `globalDiscountType`    | enum   | `PERCENT` \| `AMOUNT`                   |
| `globalDiscountPercent` | number | use with `PERCENT`, e.g. `10` = 10%    |
| `globalDiscountAmount`  | number | use with `AMOUNT`, absolute value      |

**`payment` object:**

| Field    | Type   | Notes                                                              |
|----------|--------|--------------------------------------------------------------------|
| `method` | enum   | `cash` \| `card` \| `bankTransfer` \| `mbWay` \| `multibanco` \| `spin` \| `other` |
| `date`   | string | ISO 8601 w/ timezone                                               |

Passing `payment` for any `type` other than `INVOICE_RECEIPT` or
`SIMPLIFIED_INVOICE` returns **400** with:
`"payment can only be provided for document types: INVOICE_RECEIPT, SIMPLIFIED_INVOICE"`.

**Document types (`type` — `Invoice_Document_Type`):**

`INVOICE` · `INVOICE_RECEIPT` · `SIMPLIFIED_INVOICE` · `RECEIPT` ·
`CREDIT_NOTE` · `DEBIT_NOTE`

**Response (abridged):**
```json
{
  "id": "6900afc7e9a04d2adc897c68",
  "documentType": "INVOICE",
  "status": "DRAFT",
  "series": { "ref": "…", "name": "FIZ2025…" },
  "payment": null,
  "customer": { "ref": "…", "data": { "name": "…", "taxpayerNumber": "…", "email": "…", "country": "PT" } },
  "dueDate": "2026-07-18T00:00:00.000Z",
  "date": "2026-06-18T11:57:59.008Z",
  "items": [
    { "id": "…", "ref": "<item id>", "meta": { "quantity": 10, "taxAmount": 184 },
      "data": { "name": "…", "unitPrice": 80, "taxRate": 23, "vatRate": "NORMAL" } }
  ]
}
```

The example above is the typical `DRAFT` case. When you pass a `payment` object
(only for `INVOICE_RECEIPT` / `SIMPLIFIED_INVOICE`), the created document may come
back with a non-draft `status` and a populated `payment` field. Either way you
still call the issue endpoint to finalize.

### `PATCH /invoices/:id` — edit a draft

Updates a draft invoice with PATCH semantics: only the fields you send are
changed; omitted fields keep their current value. Accepts any subset of the create
fields **except `type`** (the document type cannot be changed on update):
`notes`, `dueDate`, `cae`, `customerId`, `items`, `summary`, `payment`, `seriesId`.
Returns the updated invoice. Intended for drafts; an issued invoice should be
corrected with a credit note rather than edited.

**404 on PATCH has two causes:** an unknown invoice `id` in the path, *or* a
well-formed but unknown `seriesId` in the body (same as create) — don't assume it's
always the invoice id.

**`payment` differs from create here:** unlike `POST /invoices`, PATCH does **not**
enforce the `INVOICE_RECEIPT` / `SIMPLIFIED_INVOICE` restriction on `payment` (the
type-dependent validator is dropped on update because `type` is omitted). So a
`payment` object is accepted on a PATCH regardless of document type — avoid sending
one unless the document type actually supports it.

```bash
curl -sS -w '\n%{http_code}' -X PATCH \
  "$FIZ_API_URL/invoices/<id>" \
  -H "x-api-key: $FIZ_API_KEY" -H 'Content-Type: application/json' \
  -d '{ "notes": "PO #118", "seriesId": "68483b3fa19e44171e3d0808" }'
```

### `POST /invoices/:id/issue` — issue (finalize)

No body. Returns the invoice with the official `number`, `status: ISSUED`, and a
`syncWithAt` block:

| Field         | Type    | Notes                                            |
|---------------|---------|--------------------------------------------------|
| `status`      | enum    | `SYNCED` \| `PROCESSING` \| `FAILED`             |
| `atCode`      | string? | tax-authority code                               |
| `atMessage`   | string  | human-readable sync message                      |
| `systemError` | string? | internal error if any                            |
| `isRetriable` | boolean | whether issuing can be retried                   |
| `updatedAt`   | string  | timestamp                                        |

If `status` is `FAILED`, surface `atMessage` and `isRetriable` to the user.

### `POST /invoices/credit-notes` — reverse an issued invoice

Creates a credit note that reverses `parentInvoiceId` (a full reversal — the
parent's customer and lines are copied). By default it is **issued immediately**.

**Request:**

| Field             | Type    | Req | Notes                                                        |
|-------------------|---------|-----|--------------------------------------------------------------|
| `parentInvoiceId` | string  | yes | The issued invoice to reverse.                               |
| `reasonCode`      | enum    | yes | Anexo 40 credit-note reason (see `domain.md`), e.g. `INCORRECT_VAT_RATE`. |
| `reason`          | string  | no  | Free-text reason. Required by the AT; if omitted a default label for `reasonCode` is used. |
| `issue`           | boolean | no  | Default `true` → created **and issued**. `false` → left as a draft. |

**Response:** the credit note — `documentType: CREDIT_NOTE`, its own `id`,
`number`, `atcud`, `status` (`ISSUED` unless `issue:false`), `creditNoteReasonCode`,
`parentInvoiceId`, `customer`, `items`, `summary`, and a `syncWithAt` block (check
it like any issue). A full credit note also sets the **parent** to
`status: CANCELED`.

Common errors: **404** if `parentInvoiceId` doesn't exist; **400** for an invalid
`reasonCode`.

### `POST /invoices/:id/cancel` — cancel an issued invoice

No body. Sets the invoice to `status: CANCELED` (and syncs the cancellation with
the AT). Returns the cancelled invoice with `canceledAt` and a `syncWithAt` block.

**400** if the invoice already has issued credit/debit notes against it — cancel
is only for a document nothing else references yet; otherwise reverse it with a
credit note.

### `GET /invoices` — list

Query params: `offset` (default 0), `limit` (default 20), `sort`
(e.g. `date:desc`), `search`, `documentType`, `status`
(`DRAFT`/`ISSUED`/`PAID`/`CANCELED`/`CREATED`/`SCHEDULED`), `aggregatedStatus`,
`date`, `dueDate`, `fromDate`, `toDate`, `currency`, `description`, `notes`,
`filterAllStatusesByDate`, `includeATInvoices`.

### `GET /invoices/:id` — get one

Returns the full invoice: `number`, `atcud`, `status`, totals in `summary`,
`items`, `customer`, `issuer`, `qrCode`, `syncWithAt`, etc.

### `GET /invoices/:id/pdf` — download PDF

Query params: `format` (`A4` | `RECEIPT`), `isDuplicate` (boolean),
`templateId` (string). Returns `{ id, name, url }`.

### `DELETE /invoices/:id`

Deletes the invoice (used for drafts). Returns `{ id, createdAt }`.

---

## Series

### `GET /series` — list the account's active series

Read-only. No query params. Returns an array of the account's **active** series.
Use a series `id` as the `seriesId` when creating or PATCHing an invoice to issue it
into that numbering sequence; omit `seriesId` to use the account's default series.

Each element:

| Field            | Type      | Notes                                                  |
|------------------|-----------|--------------------------------------------------------|
| `id`             | string    | the series id — use as `seriesId` on an invoice        |
| `name`           | string?   | e.g. `"SAAS"`                                           |
| `isDefault`      | boolean?  | whether this is the account's default series           |
| `status`         | string?   | e.g. `"ACTIVE"`                                         |
| `managementMode` | string?   | numbering mode: `AUTOMATIC` \| `MANUAL`                 |
| `entries`        | array?    | per-document-type entries (with ATCUD), see below       |

**`entries[]` element:**

| Field            | Type      | Notes                                                  |
|------------------|-----------|--------------------------------------------------------|
| `documentType`   | string    | document type the entry applies to, e.g. `"INVOICE"`   |
| `validationCode` | string?   | series ATCUD validation code assigned by the AT, e.g. `"AAJF"` |
| `isVerified`     | boolean?  | whether the entry is verified/communicated to the AT   |

```bash
curl -sS -w '\n%{http_code}' \
  "$FIZ_API_URL/series" \
  -H "x-api-key: $FIZ_API_KEY"
```

---

## Validation rules to remember

- **Strict whitelist**: any unknown property → 400. Send only documented fields.
- `dueDate` / `payment.date` must be full ISO 8601 **with timezone**
  (`...T00:00:00.000Z`), not a bare `YYYY-MM-DD`.
- `items` must have at least one entry; each `quantity` ≥ 1.
- `payment` is restricted to `INVOICE_RECEIPT` / `SIMPLIFIED_INVOICE` **on create
  only** (`POST /invoices`); on `PATCH /invoices/:id` that type check is not
  applied, so a `payment` is accepted regardless of document type.
- `seriesId`, when present, is never silently ignored: a malformed value (not a
  24-char Mongo id) → **400**, while a well-formed but unknown/wrong-account id →
  **404** (on both create and PATCH).
- Enum values are case-sensitive and exactly as written above. Note `payment.method`
  uses camelCase (`mbWay`, `bankTransfer`) while document types and vat rates use
  UPPER_SNAKE_CASE.
