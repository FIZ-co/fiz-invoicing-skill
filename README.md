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

## What it can do

- Find or create a **customer**
- Find or create **items** (products / services) with the right VAT rate
- Build a **draft** invoice (with optional discount or payment)
- **Issue** it (the legally binding step that reports it to the tax authority)
- Download the invoice **PDF**

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code) installed
- A FIZ account and an API key — get one at
  **https://app.fiz.co/settings/integrations**

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

Claude will confirm before the irreversible **issue** step.

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
operations is the *preview-all-writes + separate confirmation before the
irreversible issue step* described in `SKILL.md`, not gating discovery. To force
manual-only use, set `disable-model-invocation: true` (Claude Code) /
`allow_implicit_invocation: false` (Codex).

## Notes & disclaimer

- VAT rates and exemption codes in this skill are documented for convenience and
  verified against FIZ at the time of writing, but **tax law changes**. The
  authoritative behaviour is whatever the FIZ API enforces. For anything
  non-trivial, defer to the user's accountant.
- Issuing an invoice creates a real, legally binding fiscal document reported to
  the Portuguese tax authority (AT). It cannot be deleted — only corrected with a
  credit note. The skill confirms before issuing.

## License

[MIT](./LICENSE)
