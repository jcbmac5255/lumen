import { Controller } from "@hotwired/stimulus";

// Remembers the open/closed state of <details> elements across page loads via localStorage.
// Attach with data-controller="details-memo" data-details-memo-key-value="some-stable-key".
export default class extends Controller {
  static values = { key: String };

  connect() {
    if (!this.keyValue) return;
    const stored = localStorage.getItem(this.#storageKey());
    if (stored === "1") this.element.open = true;
    if (stored === "0") this.element.open = false;
    this.element.addEventListener("toggle", this.#onToggle);
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.#onToggle);
  }

  #onToggle = () => {
    localStorage.setItem(this.#storageKey(), this.element.open ? "1" : "0");
  };

  #storageKey() {
    return `details-memo:${this.keyValue}`;
  }
}
