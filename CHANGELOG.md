# Changelog

All notable changes to this self-hosted fork are listed here. Newest versions go on top.

## [0.10.0] - 2026-04-24

### Added
- **`@mentions` in the AI chat** — type `@` to open a typeahead dropdown of your accounts, categories, and merchants. Selecting one inserts the name as plain text; the AI's existing tools resolve the reference.
- **File attachments in the AI chat** — click the `+` button to attach images (PNG / JPEG / GIF / WebP) or PDFs to a message. Up to 5 files per message, 20MB each. Claude reads them natively (vision for images, built-in PDF support for documents).
- **New Lumen logo** — replaced the gold "L" mark with a gradient green/teal/blue/purple "L" embedded with a bar chart. New login, nav, favicon, and PWA icon assets.
- **Dark-background PWA icon** so the installed home-screen icon doesn't render on a white tile.

### Changed
- **Public URL** is now https://lumen.nexgrid.cc (via Nginx Proxy Manager).
- **Repo renamed** to jcbmac5255/lumen. In-app GitHub links (user menu, feedback, Redis error page) updated.
- **Help button (?)** in the left nav now opens the Feedback page instead of trying to launch Intercom.
- **README** and **CONTRIBUTING** rewritten for Lumen with attribution to the upstream Maybe Finance project.

### Fixed
- **AI assistant** tool-call flow: tools with no arguments (e.g. `get_accounts`) no longer crash the response, and conversation history now correctly interleaves `tool_use` → `tool_result` → final text for Anthropic's Messages API.
- **Navigation flashes** from Turbo's cached-snapshot preview (added `turbo-cache-control: no-preview`). Bottom-nav Budgets link now points directly at the current month to avoid the 302 that caused a flash of another tab.
- **Chat input** placeholder buttons that did nothing (upstream stubs) removed.

### Infra
- **Service worker** registered and actually caching static assets — previous worker was a commented stub. Cache-first for fingerprinted assets, network-first for HTML.
- **Rails.cache** backed by Redis; dashboard sankey computation cached with transaction-update-time invalidation.
- **Mobile PWA performance pass** — logo PNGs shrunk from ~190-350KB down to ~13-44KB (pngquant + resize), gzip enabled on the reverse proxy, Turbo-preload on nav items.
- **Server timezone** set to America/New_York so backup filenames and logs match local clock.
- **Hetzner bucket renamed** to `lumen-finance` and backup script updated to match.

## [0.9.0] - 2026-04-23

### Changed
- **Rebranded as Lumen.** New name, new logo (gold "L" with a layered sunset/horizon motif), new favicons, new PWA manifest, new AI persona. Footer credits the original Maybe Finance open-source project. The Ruby module name and database names stay as `Maybe` / `maybe_production` for internal continuity — only user-facing strings changed.
- **Email "from" name** is now "Lumen" (instead of "Maybe Finance").
- **Plaid link-account screen** and **2FA authenticator entry** both now show "Lumen" instead of "Maybe Finance".

## [0.8.0] - 2026-04-23

### Added
- **Anthropic Claude as an AI provider** — the assistant sidebar can now run on Claude (Opus 4.7, Opus 4.6, Sonnet 4.6, or Haiku 4.5) via an `ANTHROPIC_API_KEY`. OpenAI is still supported; whichever key is set drives the model. Streaming chat and tool-calling (so the assistant can look up your accounts, transactions, balances, and income statement) both work with Claude. Default model is configurable via `DEFAULT_AI_MODEL` (fallback `claude-opus-4-7`).

### Infra
- **Production deployment live** at https://maybe.nexgrid.cc via Nginx Proxy Manager → Rails (prod mode).
- **Nightly database backups** streaming `pg_dump` to Hetzner Object Storage with 30-day retention.
- **One-command deploy** via `bin/deploy` (runs migrations, precompiles assets, restarts the service).
- **Server timezone** set to America/New_York so backup filenames and logs match local clock.

## [0.7.0] - 2026-04-23

### Added
- **Bills tracker** — new Bills page with a monthly calendar view showing bills due and their paid status (paid / overdue / upcoming).
- **Paid-from account on bills** — optionally link a bill to a checking or credit card account. Marking the bill paid automatically creates a matching transaction and updates the account balance. Unmarking reverses it.
- **Invite code deletion** — admins can now remove unused invite codes.
- **Password change from Security settings** — no more need to use the password reset flow just to rotate your password.

### Changed
- **Calendar scales better on mobile** — tighter cells, single-letter day headers, and colored status dots instead of truncated name pills on small screens.
- **Changelog page now reads from a local `CHANGELOG.md`** — no more fetching release notes from the upstream (unmaintained) repo.
- **Feedback page links repointed** to this fork's GitHub and the household Discord.
- **Contact link in user menu** now points to the household Discord instead of the old maintainer's.
- **Redis error page** setup-guide link repointed to this fork's Docker doc.
- **Removed the upstream i18n disclaimer** from Preferences (pointed at a dead issue).

### Fixed
- Invite-code UI readability in dark mode.
- Modal flash on cached page navigation.
