import { Controller } from "@hotwired/stimulus";

// Chat @mentions typeahead.
//
// Watches the chat textarea for `@<query>` tokens as the user types and shows
// a dropdown of matching accounts, categories, and merchants. Selecting an
// item replaces the `@<query>` with the item's name as plain text — the AI
// already has tool access to resolve names, so the @-mention is just typing
// convenience.
export default class extends Controller {
  static targets = ["input", "dropdown"];
  static values = {
    url: { type: String, default: "/chat_mentions" },
  };

  connect() {
    this.activeIndex = 0;
    this.results = [];
    this.pending = null;
    if (this.hasDropdownTarget) this.#hide();
  }

  disconnect() {
    if (this.pending) clearTimeout(this.pending);
  }

  onInput() {
    const token = this.#currentMentionToken();
    if (token === null) {
      this.#hide();
      return;
    }
    this.#fetchDebounced(token.query);
  }

  onKeyDown(event) {
    if (this.dropdownTarget.classList.contains("hidden")) return;
    if (this.results.length === 0) return;

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        event.stopImmediatePropagation();
        this.activeIndex = (this.activeIndex + 1) % this.results.length;
        this.#render();
        break;
      case "ArrowUp":
        event.preventDefault();
        event.stopImmediatePropagation();
        this.activeIndex =
          (this.activeIndex - 1 + this.results.length) % this.results.length;
        this.#render();
        break;
      case "Enter":
      case "Tab":
        event.preventDefault();
        event.stopImmediatePropagation();
        this.#select(this.results[this.activeIndex]);
        break;
      case "Escape":
        event.preventDefault();
        event.stopImmediatePropagation();
        this.#hide();
        break;
    }
  }

  selectItem(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    this.#select(this.results[index]);
  }

  // --- private ---

  // Returns {query, start, end} for the active @token under the caret, or null.
  #currentMentionToken() {
    const input = this.inputTarget;
    const caret = input.selectionStart;
    if (caret !== input.selectionEnd) return null;

    const textBefore = input.value.slice(0, caret);
    const at = textBefore.lastIndexOf("@");
    if (at === -1) return null;

    // Must follow a whitespace/start-of-line boundary
    if (at > 0 && !/\s/.test(textBefore[at - 1])) return null;

    const query = textBefore.slice(at + 1);
    // Stop if the token contains a space or looks like an email
    if (/\s/.test(query)) return null;

    return { query, start: at, end: caret };
  }

  #fetchDebounced(query) {
    if (this.pending) clearTimeout(this.pending);
    this.pending = setTimeout(() => this.#fetch(query), 80);
  }

  async #fetch(query) {
    try {
      const url = new URL(this.urlValue, window.location.origin);
      url.searchParams.set("q", query);
      const res = await fetch(url, {
        headers: { Accept: "application/json" },
      });
      if (!res.ok) return this.#hide();
      this.results = await res.json();
      this.activeIndex = 0;
      if (this.results.length === 0) {
        this.#hide();
      } else {
        this.#render();
        this.#show();
      }
    } catch (_e) {
      this.#hide();
    }
  }

  #select(item) {
    if (!item) return;
    const token = this.#currentMentionToken();
    if (!token) return;

    const input = this.inputTarget;
    const before = input.value.slice(0, token.start);
    const after = input.value.slice(token.end);
    const insert = `@${item.name} `;
    input.value = before + insert + after;

    const caret = before.length + insert.length;
    input.setSelectionRange(caret, caret);
    input.focus();
    this.#hide();

    // Trigger any auto-resize / change handlers on the textarea
    input.dispatchEvent(new Event("input", { bubbles: true }));
  }

  #render() {
    const typeIcon = {
      account: "🏦",
      category: "🏷️",
      merchant: "🛒",
    };
    this.dropdownTarget.innerHTML = this.results
      .map((r, i) => {
        const active = i === this.activeIndex ? "bg-surface-inset" : "";
        return `
          <button type="button"
            data-action="click->chat-mentions#selectItem"
            data-index="${i}"
            class="w-full flex items-center gap-2 px-3 py-1.5 text-sm text-left hover:bg-surface-inset ${active}">
            <span class="shrink-0">${typeIcon[r.type] || ""}</span>
            <span class="truncate text-primary">${escapeHtml(r.name)}</span>
            <span class="ml-auto text-xs text-secondary">${escapeHtml(r.subtitle || "")}</span>
          </button>`;
      })
      .join("");
  }

  #show() {
    this.dropdownTarget.classList.remove("hidden");
  }

  #hide() {
    this.dropdownTarget.classList.add("hidden");
    this.dropdownTarget.innerHTML = "";
    this.results = [];
    this.activeIndex = 0;
  }
}

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[c]));
}
