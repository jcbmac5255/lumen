import { Controller } from "@hotwired/stimulus";

// Lets a user create a new category directly from a category <select>
// without leaving the current form. Click the toggle button, type a name,
// hit Enter or Create — the new category is POSTed to /categories.json,
// then added as an <option> and selected.
export default class extends Controller {
  static targets = ["select", "form", "input", "error"];

  toggle(event) {
    event.preventDefault();
    const hidden = this.formTarget.classList.toggle("hidden");
    if (!hidden) {
      this.errorTarget.textContent = "";
      this.inputTarget.value = "";
      this.inputTarget.focus();
    }
  }

  async submit(event) {
    event.preventDefault();
    const name = this.inputTarget.value.trim();
    if (!name) {
      this.inputTarget.focus();
      return;
    }

    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    try {
      const res = await fetch("/categories", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": token || "",
        },
        body: JSON.stringify({ category: { name } }),
      });

      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        this.errorTarget.textContent = (body.errors || ["Could not create"]).join(", ");
        return;
      }

      const cat = await res.json();
      const opt = document.createElement("option");
      opt.value = cat.id;
      opt.textContent = cat.name;
      opt.selected = true;
      this.selectTarget.appendChild(opt);
      this.selectTarget.dispatchEvent(new Event("change", { bubbles: true }));

      this.inputTarget.value = "";
      this.errorTarget.textContent = "";
      this.formTarget.classList.add("hidden");
    } catch (e) {
      this.errorTarget.textContent = "Network error";
    }
  }

  onKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.submit(event);
    } else if (event.key === "Escape") {
      this.formTarget.classList.add("hidden");
    }
  }
}
