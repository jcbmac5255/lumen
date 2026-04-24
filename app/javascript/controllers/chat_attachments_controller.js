import { Controller } from "@hotwired/stimulus";

// Manage file attachments on the chat input.
// - Clicking the + button opens the native file picker
// - Selected files render as chips below the input
// - Each chip has a remove ✕ that deletes just that file from the list
// - Because input[type=file] doesn't support removing individual files,
//   we maintain our own FileList using DataTransfer.
export default class extends Controller {
  static targets = ["fileInput", "previews", "form"];
  static values = {
    maxCount: { type: Number, default: 5 },
    maxSizeMb: { type: Number, default: 20 },
  };

  connect() {
    this.files = [];
  }

  pick() {
    this.fileInputTarget.click();
  }

  onFiles(event) {
    const incoming = Array.from(event.target.files || []);
    for (const f of incoming) {
      if (this.files.length >= this.maxCountValue) {
        alert(`Max ${this.maxCountValue} files per message.`);
        break;
      }
      if (f.size > this.maxSizeMbValue * 1024 * 1024) {
        alert(`${f.name} exceeds the ${this.maxSizeMbValue}MB limit.`);
        continue;
      }
      this.files.push(f);
    }
    this.#syncInputFiles();
    this.#render();
  }

  remove(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    this.files.splice(index, 1);
    this.#syncInputFiles();
    this.#render();
  }

  // Clear previews after the form submits
  onSubmit() {
    this.files = [];
    this.#render();
  }

  #syncInputFiles() {
    const dt = new DataTransfer();
    this.files.forEach((f) => dt.items.add(f));
    this.fileInputTarget.files = dt.files;
  }

  #render() {
    if (this.files.length === 0) {
      this.previewsTarget.classList.add("hidden");
      this.previewsTarget.classList.remove("flex");
      this.previewsTarget.innerHTML = "";
      return;
    }

    this.previewsTarget.classList.remove("hidden");
    this.previewsTarget.classList.add("flex");
    this.previewsTarget.innerHTML = this.files
      .map((f, i) => {
        const isImage = f.type.startsWith("image/");
        const preview = isImage
          ? `<img src="${URL.createObjectURL(f)}" class="w-10 h-10 object-cover rounded"/>`
          : `<div class="w-10 h-10 flex items-center justify-center bg-surface-inset rounded text-xs font-medium text-secondary">PDF</div>`;
        return `
          <div class="relative group flex items-center gap-2 bg-surface-inset rounded px-1 py-1 pr-6 text-xs">
            ${preview}
            <span class="truncate max-w-[120px]">${escapeHtml(f.name)}</span>
            <button type="button"
              data-action="click->chat-attachments#remove"
              data-index="${i}"
              title="Remove"
              class="absolute top-0 right-0 w-5 h-5 flex items-center justify-center text-secondary hover:text-primary">
              ✕
            </button>
          </div>`;
      })
      .join("");
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
