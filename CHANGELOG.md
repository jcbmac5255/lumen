# Changelog

All notable changes to this self-hosted fork are listed here. Newest versions go on top.

## [0.13.0] - 2026-05-03

### Added
- **Bills can pay down debt accounts.** A bill can now target a Loan, Credit Card, or Other Liability as its "Pays toward" account. When marked paid with both a paid-from (asset) and a paid-to (debt) account, marking it paid creates a linked transfer pair: an outflow on the source and an inflow on the debt, with the right `cc_payment` / `loan_payment` kind so analytics treat it correctly.
- **Self-Hosting settings page** now has an AI assistant section to set the Anthropic and OpenAI API keys from the UI. Values entered here override the matching env var; clearing falls back to the env var if one is set. (Anthropic takes precedence when both are set.)

### Changed
- **Account sidebar persists across navigations** so the account list no longer flashes / re-fetches on every page change. The sidebar invalidates itself when accounts actually change (via a version stamp on the persisted DOM node), so additions/renames/reorders still show up.

### Fixed
- **Deleting a bill that's been marked paid** now cleans up the linked ledger entries on both the source and destination accounts. For transfer-style payments the partner leg is removed via the existing Transferable cascade.
- **Deleting the transaction directly from an account view** (instead of unmarking the bill) used to fail with a 500 because of the FK from `bill_payments` → `entries`. The FK is now `ON DELETE CASCADE`, so deleting the entry removes the BillPayment marker too — the bill reverts to "unpaid" for that period.
- **Sparkline timeouts on the accounts list** after a sync. The per-account sparkline cache key was family-wide, so any sync to any account busted every sparkline at once and stampeded the request pool. The cache key is now per-account (busts only when that account's data changes), and the client-side fallback timeout is 30s (was 10s).

## [0.12.0] - 2026-04-26

### Added
- **Insights page** at `/insights` with a period selector (7D / 30D / MTD / 90D / YTD / 365D). Sections include:
  - **AI narrative** — Claude generates a 2-4 sentence summary of the period (lazy-loaded, cached 6h, ~$0.001/generation on Haiku).
  - **KPI cards**: Income, Expenses, Net, Savings rate — each with a vs-prior-period delta (↑/↓ %).
  - **Last 12 months** side-by-side income vs expense bar chart.
  - **Spending velocity** projection on in-progress periods (Current Month / Current Year): "you're on pace for $X by month end".
  - **Income source diversity** plain-English summary (single / concentrated / diversified).
  - **Income & Expenses by category** with bars + percentages, clickable to drill into the filtered transactions list for that category and date range.
  - **Spending by day of week** column chart.
  - **Largest transactions** (top 10 by absolute amount).
  - **Bills coverage** (uses Bills tracker — what % of expenses are recurring bills).
  - **Recurring detection** (merchants with 3+ similar-amount transactions in the last 90 days, with monthly-cost estimate).
  - **Unusual spending** (transactions ≥3× their category's 90-day median).
  - **Top merchants** + **cashflow by account**.
- **Insights** added to the bottom-nav and desktop sidebar.

### Changed
- **Transfer transactions can now be selected** for bulk-delete (and deleting one side now cascades to the other automatically — see below).
- **Application directory** renamed `/opt/maybe` → `/opt/lumen` on the host. Systemd units, backup script, and bin/deploy updated to match. The Ruby `Maybe` module name and database (`maybe_production`) stay for internal continuity.

### Fixed
- **Deleting one side of a transfer** now also deletes the matching transaction on the other account, and resyncs that account's balance immediately. Previously the partner row was orphaned and balances drifted until you hit the manual refresh button.
- **Turbo Drive's blue progress bar** is now hidden globally — was the brief blue line at the top during navigations.
- **WebAuthn config deprecation** — switched from `config.origin = ...` to `config.allowed_origins = [ ... ]`.

## [0.11.0] - 2026-04-24

### Added
- **Passkey (biometric) sign-in** — register a passkey from Settings → Security and sign in with Face ID, Touch ID, fingerprint, or your device PIN instead of typing a password. Backed by WebAuthn (ES256 + RS256). Supports multiple passkeys per account so each device can have its own.
- **Drag-reorder accounts** — grab any account row in Settings → Accounts to change the order. The home-screen sidebar reflects the new order within each group.
- **Sidebar groups remember their open/closed state** in `localStorage`, so collapsing "Credit cards" once doesn't get undone every time you navigate.
- **Create a new category inline** from the New Transaction modal (`+ New category` link under the Category select). No round-trip to Settings.
- **Chat @-mentions** — type **@** in the AI chat input to open a typeahead dropdown of your accounts, categories, and merchants. Selecting one inserts the name as plain text; the AI's existing tools resolve the reference.
- **File attachments in the AI chat** — click the **+** button to attach images (PNG / JPEG / GIF / WebP) or PDFs to a message. Up to 5 files per message, 20MB each. Claude reads them natively (vision for images, built-in PDF support for documents).
- **New Lumen logo** — replaced the gold "L" mark with a gradient green/teal/blue/purple "L" embedded with a bar chart. New login, nav, favicon, and PWA icon assets.
- **Dark-background PWA icon** so the installed home-screen icon doesn't render on a white tile.

### Changed
- **Invitation emails now send for real** in self-hosted mode. Previously the upstream code skipped the mailer in self-hosted; it now goes through Resend (or whatever SMTP you have configured). The button styles are inlined so Gmail's style-strip doesn't render the link as plain text, and a copy-paste fallback URL is included as a backup.
- **Pending-invitation row** restructured to stack on mobile so the invitation-link input doesn't blow past the viewport.
- **Public URL** is now https://lumen.nexgrid.cc (via Nginx Proxy Manager).
- **Repo renamed** to jcbmac5255/lumen. In-app GitHub links (user menu, feedback, Redis error page) updated.
- **Help (`?`) button in the left nav** now opens the Feedback page (was wired to Intercom, which isn't configured in self-hosted).
- **README** and **CONTRIBUTING** rewritten for Lumen with attribution to the upstream Maybe Finance project.

### Fixed
- **Invitation link input** in household settings was rendering white-on-white in dark mode — now uses design-token colors that adapt to the theme.
- **Inline code spans** on the in-app Changelog page were invisible against the dark background — added explicit `text-primary` / `bg-surface-inset` styling.
- **Pull-to-refresh** experiment in the mobile PWA was over-sensitive; disabled for now (controller left in repo for a future revisit).
- **AI assistant** tool-call flow: tools with no arguments (e.g. `get_accounts`) no longer crash the response, and conversation history now correctly interleaves `tool_use` → `tool_result` → final text for Anthropic's Messages API.
- **Navigation flashes** from Turbo's cached-snapshot preview (added `turbo-cache-control: no-preview`). Bottom-nav Budgets link now points directly at the current month to avoid the 302 that caused a flash of another tab.
- **Chat input** placeholder buttons that did nothing (upstream stubs) removed.

### Infra
- DB-level uniqueness on `(family_id, LOWER(name))` for categories — prevents duplicates if two household members try to create the same category at exactly the same moment.
- **Service worker** registered and actually caching static assets — previous worker was a commented stub. Cache-first for fingerprinted assets, network-first for HTML.
- **Rails.cache** backed by Redis; dashboard sankey computation cached with transaction-update-time invalidation.
- **Mobile PWA performance pass** — logo PNGs shrunk from ~190-350KB down to ~13-44KB (pngquant + resize), gzip enabled on the reverse proxy, Turbo-preload on nav items.
- **Hetzner bucket renamed** to `lumen-finance` and backup script updated to match.

## [0.10.0] - 2026-04-23

### Added
- **Bills tracker** — new Bills page with a monthly calendar view showing bills due and their paid status (paid / overdue / upcoming).
- **Paid-from account on bills** — optionally link a bill to a checking or credit card account. Marking the bill paid automatically creates a matching transaction and updates the account balance. Unmarking reverses it.
- **Invite code deletion** — admins can now remove unused invite codes.
- **Password change from Security settings** — no more need to use the password reset flow just to rotate your password.
- **Anthropic Claude as an AI provider** — the assistant sidebar can now run on Claude (Opus 4.7, Opus 4.6, Sonnet 4.6, or Haiku 4.5) via an `ANTHROPIC_API_KEY`. OpenAI is still supported; whichever key is set drives the model. Streaming chat and tool-calling (so the assistant can look up your accounts, transactions, balances, and income statement) both work with Claude. Default model is configurable via `DEFAULT_AI_MODEL` (fallback `claude-opus-4-7`).

### Changed
- **Rebranded as Lumen.** New name, new logo (gold "L" with a layered sunset/horizon motif), new favicons, new PWA manifest, new AI persona. Footer credits the original Maybe Finance open-source project. The Ruby module name and database names stay as `Maybe` / `maybe_production` for internal continuity — only user-facing strings changed.
- **Email "from" name** is now "Lumen" (instead of "Maybe Finance").
- **Plaid link-account screen** and **2FA authenticator entry** both now show "Lumen" instead of "Maybe Finance".
- **Calendar scales better on mobile** — tighter cells, single-letter day headers, and colored status dots instead of truncated name pills on small screens.
- **Changelog page now reads from a local `CHANGELOG.md`** — no more fetching release notes from the upstream (unmaintained) repo.
- **Feedback page links repointed** to this fork's GitHub and the household Discord.
- **Contact link in user menu** now points to the household Discord instead of the old maintainer's.
- **Redis error page** setup-guide link repointed to this fork's Docker doc.
- **Removed the upstream i18n disclaimer** from Preferences (pointed at a dead issue).

### Fixed
- Invite-code UI readability in dark mode.
- Modal flash on cached page navigation.

### Infra
- **Production deployment live** at https://maybe.nexgrid.cc via Nginx Proxy Manager → Rails (prod mode).
- **Nightly database backups** streaming `pg_dump` to Hetzner Object Storage with 30-day retention.
- **One-command deploy** via `bin/deploy` (runs migrations, precompiles assets, restarts the service).
- **Server timezone** set to America/New_York so backup filenames and logs match local clock.
