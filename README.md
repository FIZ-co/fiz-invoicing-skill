# FIZ Invoicing — Claude Code / Agent Skill

> **Emitir faturas em Portugal com IA.** Skill para [Claude Code](https://claude.com/claude-code)
> que emite **faturas, faturas-recibo e faturas simplificadas** através da
> [API pública da FIZ](https://api.fiz.co) — cria clientes e artigos, aplica a
> **taxa de IVA** correta por território, o **motivo de isenção** certo, retenção
> na fonte, e comunica o documento à **Autoridade Tributária (AT)**. *Faturação
> automática para freelancers e empresas, em linguagem natural.*

A [Claude Code](https://claude.com/claude-code) skill that lets you issue
invoices through the [FIZ](https://fiz.co) Public API by just asking in plain
language — *"bill João 10 consulting hours"*, *"issue a fatura-recibo for this
customer"*, *"download the PDF for invoice X"*.

> **Prefer not to manage an API key?** FIZ also ships an **MCP connector** at
> `https://api.fiz.co/mcp` — connect it to Claude or ChatGPT with OAuth and skip
> the setup below. See [Two ways to use FIZ with AI](#two-ways-to-use-fiz-with-ai).

It follows the [Agent Skills](https://agentskills.io) open standard, so it is not
locked to one tool: install it in Claude Code today, and it works with any agent
runtime that supports the standard. It is **Claude-Code-first**, though — the
`SKILL.md` frontmatter uses a couple of Claude Code extensions to the standard
(`allowed-tools`, and `${CLAUDE_SKILL_DIR}` for the helper path); spec-compliant
runtimes ignore the extra frontmatter, and the helper falls back to an absolute
skill path. (Setup notes here are written for Claude Code; other runtimes load
`fiz-invoicing/SKILL.md` the same way.)

The skill teaches the agent both the **API mechanics** (endpoints, fields, auth)
and the **Portuguese tax domain** behind invoicing (VAT rates per territory, when
an exemption code is required and which one, CAE/NIF rules, withholding tax, and
why issuing is irreversible) — so it builds *correct* fiscal documents, not just
well-formed JSON.

**Keywords / palavras-chave:** faturação Portugal, emitir faturas, fatura-recibo,
fatura simplificada, API faturação, IVA, motivo de isenção, CAE, NIF, AT /
e-Fatura, Portuguese invoicing, Claude Code skill, agent skill.

## Two ways to use FIZ with AI

FIZ can be driven by an AI assistant in two different ways. They are not
competitors — pick the one that fits how you work.

|                        | **MCP connector** | **This skill** |
|------------------------|-------------------|----------------|
| What it is             | FIZ's own MCP server, `https://api.fiz.co/mcp` | An [Agent Skill](https://agentskills.io) — instructions + a curl helper |
| Setup                  | Paste a URL, sign in with OAuth | Copy a folder, export an API key |
| Credentials            | **No API key.** OAuth, short-lived tokens, revocable per connection | An API key you manage in your environment |
| Where it works         | Claude (web, desktop, mobile), ChatGPT, Claude Code | Claude Code and other Agent Skills runtimes |
| Permissions            | You tick the scopes at connect time, per company | Whatever your API key can do |
| Confirmation on fiscal acts | Built into the server: preview → your confirmation → execute | Built into the skill's instructions |
| Best for               | Everyday use, non-technical users, phone and web | Scripting, CI, batch work, the full REST surface |

**Most people should start with the connector.** It needs no API key, works
outside the terminal, and the confirmation step for issuing is enforced by the
server rather than by instructions.

### Connecting the MCP server

**Claude (web, desktop, mobile)** — Settings → Connectors → *Add custom
connector*, paste `https://api.fiz.co/mcp`, then enable it in a chat and sign in.

**ChatGPT** — Settings → Apps & Connectors → *Create*, paste
`https://api.fiz.co/mcp`, choose OAuth.

**Claude Code:**
```bash
claude mcp add --transport http fiz https://api.fiz.co/mcp
# then, in the session: /mcp → fiz → Authenticate
```

At sign-in you pick **one company** and which permissions to grant — read
invoices/customers/items, create and edit drafts, issue fiscal documents, read
bank transactions. Untick anything you don't want. Disconnect any time at
[app.fiz.co/settings/integrations](https://app.fiz.co/settings/integrations).

Full connector documentation, including the tool list:
**https://api.fiz.co/docs/mcp**

### Using both

They coexist. If you run this skill in a session where the FIZ connector is also
connected, the skill tells the agent to prefer the connector's tools — you get the
OAuth path for the API calls *and* the skill's Portuguese tax guidance (which VAT
rate, which exemption code, when a credit note is the right fix) on top. That
guidance is the part the connector doesn't carry.

## What it can do

- Find or create a **customer**
- Find or create **items** (products / services) with the right VAT rate
- Work out the **correct VAT** for a sale, including cross-border, OSS and
  reverse-charge cases
- Build a **draft** invoice (with per-line or global discounts, a back-dated issue
  date, or a separate tax point date)
- **Issue** it (the legally binding step that reports it to the tax authority)
- **Register a payment** on an issued invoice and get the receipt (recibo) it
  normally issues
- Issue a **credit note** to reverse a wrong invoice, or **cancel** one
- Create and issue a **guia de transporte** (transport document)
- Read **bank transactions** to check whether an invoice was actually paid
- Download any document's **PDF**

Writes can carry an **`Idempotency-Key`**, so a retry after a timeout replays the
original response instead of issuing a second document.

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code) installed
- A FIZ account and an API key — get one at
  **https://app.fiz.co/settings/integrations**

(The MCP connector needs neither: just a FIZ account and the server URL.)

## Install

Copy the `fiz-invoicing/` folder into your Claude Code skills directory.

**Personal (all your projects):**
```bash
git clone https://github.com/FIZ-co/fiz-invoicing-skill.git
cp -r fiz-invoicing-skill/fiz-invoicing ~/.claude/skills/
```

**Project-scoped (one repo only):**
```bash
cp -r fiz-invoicing-skill/fiz-invoicing /path/to/your-project/.claude/skills/
```

That's it — the skill auto-activates when you ask Claude about invoices,
customers, items, or payments in FIZ. (Run `/skills` in Claude Code to confirm
`fiz-invoicing` is listed.)

## Configure your API key

The skill reads your key from an environment variable so it never gets hardcoded:

```bash
export FIZ_API_KEY="your_key_from_app.fiz.co"
# optional — defaults to https://api.fiz.co
export FIZ_API_URL="https://api.fiz.co"
```

Set these in the shell where you run Claude Code (e.g. your `~/.zshrc`) or a
secret manager. If the key isn't set, the agent will ask you to **set
`FIZ_API_KEY` in your environment** — it won't ask you to paste the key into the
chat, and it never prints the key. Treat the key as a credential; keep it out of
the conversation.

## Usage examples

Just talk to Claude:

> *Create a customer named Maria Costa, NIF 303741791, then bill her for 5 hours
> of consulting at €80/h and issue the invoice.*

> *Issue a fatura simplificada for a €40 retail sale, paid by MB WAY.*

> *I'm exempt under the small-business regime — issue an invoice for €500 of
> design work.* (Claude knows this maps to VAT `EXEMPT` + exemption code `M10`.)

> *What VAT should I charge a Spanish company with a valid VAT number?* (Answered
> from the API's own calculator — no invoice is created.)

> *Invoice 4 was paid by bank transfer today — record it and give me the receipt
> PDF.*

> *I invoiced Padaria Central at the wrong VAT rate. Credit-note it and re-issue
> correctly.*

Claude will confirm before the irreversible **issue** step — and before every
other legally binding fiscal act: recording a payment, credit notes,
cancellations, and issuing a guia. None of them can be undone.

## What's inside

```
fiz-invoicing/
├── SKILL.md            # main instructions + tax-domain essentials (loaded on trigger)
├── domain.md           # full Portuguese tax reference (VAT rates, M-codes, CAE, NIF…)
├── reference.md        # complete API field reference (every endpoint, field, enum)
├── scripts/
│   └── fiz.sh          # tiny curl helper: `fiz GET /invoices` (checks HTTP status)
└── agents/
    └── openai.yaml     # optional Codex UI metadata / invocation policy
```

`SKILL.md` with its YAML frontmatter is the portable core (works in any Agent
Skills runtime). `agents/openai.yaml` adds Codex-specific display metadata;
runtimes that don't use it simply ignore it.

**Invocation policy:** auto-invocation is intentionally **enabled** on both
runtimes (Claude Code leaves model invocation on; Codex sets
`allow_implicit_invocation: true`). The safety net for these state-changing
operations is the *preview-all-writes + a separate confirmation before each
irreversible fiscal act* — issuing, payments, credit notes, cancellations, and
guia issue/cancel — described in `SKILL.md`, not gating discovery. To force
manual-only use, set `disable-model-invocation: true` (Claude Code) /
`allow_implicit_invocation: false` (Codex).

## Notes & disclaimer

- VAT rates and exemption codes in this skill are documented for convenience and
  verified against FIZ at the time of writing, but **tax law changes**. The
  authoritative behaviour is whatever the FIZ API enforces. For anything
  non-trivial, defer to the user's accountant.
- Issuing an invoice creates a real, legally binding fiscal document reported to
  the Portuguese tax authority (AT). It cannot be deleted — only corrected with a
  credit note. Credit notes, cancellations and guias de transporte are likewise
  reported to the AT.
- Recording a payment is a legally binding act too, and equally irreversible —
  there is no "unpay". It normally issues a receipt (recibo); for an invoice
  imported from the AT, none is issued.
- The skill asks for a separate confirmation before each of these.
- A **guia de transporte** must reach the AT before the goods move, so it cannot
  be back-dated — you can't document a shipment after the fact.
- Some endpoints depend on the account's plan: the VAT calculator needs Auto IVA,
  and bank access needs the accounting feature. Without them those calls return
  402 / 403 respectively.

## License

[MIT](./LICENSE)
