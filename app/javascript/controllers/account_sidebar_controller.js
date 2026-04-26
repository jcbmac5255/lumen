import { Controller } from "@hotwired/stimulus";

// Updates the active-account highlight on the account sidebar without re-rendering.
// The sidebar is marked turbo-permanent, so it doesn't re-render on navigation —
// this controller listens for turbo:load and toggles classes based on the URL.
// If account state has changed (different version), it lets Turbo replace the sidebar.
export default class extends Controller {
  static targets = ["link"];
  static values = { version: String };

  connect() {
    this.boundUpdate = this.update.bind(this);
    this.boundCheckVersion = this.checkVersion.bind(this);
    document.addEventListener("turbo:load", this.boundUpdate);
    document.addEventListener("turbo:before-render", this.boundCheckVersion);
    this.update();
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.boundUpdate);
    document.removeEventListener("turbo:before-render", this.boundCheckVersion);
  }

  checkVersion(event) {
    const newSidebar = event.detail.newBody.querySelector("#default-account-sidebar");
    if (!newSidebar) return;
    const newVersion = newSidebar.dataset.accountSidebarVersionValue;
    if (newVersion && newVersion !== this.versionValue) {
      this.element.removeAttribute("data-turbo-permanent");
    }
  }

  update() {
    const currentPath = window.location.pathname;
    this.linkTargets.forEach((link) => {
      const active = link.getAttribute("href") === currentPath;
      link.classList.toggle("bg-container", active);
      link.classList.toggle("hover:bg-surface-hover", !active);
      if (active) {
        const details = link.closest("details");
        if (details && !details.open) details.open = true;
      }
    });
  }
}
