import { Controller } from "@hotwired/stimulus";

// HTML5 drag-and-drop ordering for the accounts settings list.
// Each item has data-id (account id) and data-sortable-accounts-target="item".
// On drop, PATCH /accounts/reorder with the new ID order.
export default class extends Controller {
  static targets = ["item"];
  static values = { url: { type: String, default: "/accounts/reorder" } };

  connect() {
    this.itemTargets.forEach((el) => this.#wire(el));
  }

  itemTargetConnected(el) {
    this.#wire(el);
  }

  // --- drag events ---

  #wire(el) {
    if (el.dataset.sortableWired) return;
    el.dataset.sortableWired = "1";
    el.setAttribute("draggable", "true");
    el.addEventListener("dragstart", this.#onDragStart);
    el.addEventListener("dragover", this.#onDragOver);
    el.addEventListener("dragleave", this.#onDragLeave);
    el.addEventListener("drop", this.#onDrop);
    el.addEventListener("dragend", this.#onDragEnd);
  }

  #onDragStart = (e) => {
    this.dragging = e.currentTarget;
    e.currentTarget.classList.add("opacity-50");
    e.dataTransfer.effectAllowed = "move";
    // Some browsers require setData to initiate the drag
    e.dataTransfer.setData("text/plain", e.currentTarget.dataset.id);
  };

  #onDragOver = (e) => {
    if (!this.dragging || this.dragging === e.currentTarget) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";

    // Insert dragging element before or after the target based on mouse position
    const rect = e.currentTarget.getBoundingClientRect();
    const after = e.clientY - rect.top > rect.height / 2;
    const parent = e.currentTarget.parentNode;
    if (after) {
      parent.insertBefore(this.dragging, e.currentTarget.nextSibling);
    } else {
      parent.insertBefore(this.dragging, e.currentTarget);
    }
  };

  #onDragLeave = (_e) => {
    // no-op; visual cues handled by dragover
  };

  #onDrop = (e) => {
    e.preventDefault();
  };

  #onDragEnd = (e) => {
    e.currentTarget.classList.remove("opacity-50");
    this.dragging = null;
    this.#persist();
  };

  async #persist() {
    const ids = this.itemTargets.map((el) => el.dataset.id);
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    try {
      await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": token || "",
        },
        body: JSON.stringify({ ids }),
      });
    } catch (_e) {
      // Silent fail — refresh will show server's authoritative order
    }
  }
}
