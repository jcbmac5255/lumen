import { Application } from "@hotwired/stimulus";

const application = Application.start();

// Configure Stimulus development experience
application.debug = false;
window.Stimulus = application;

Turbo.config.forms.confirm = (data) => {
  const confirmDialogController =
    application.getControllerForElementAndIdentifier(
      document.getElementById("confirm-dialog"),
      "confirm-dialog",
    );

  return confirmDialogController.handleConfirm(data);
};

// Clear modal/drawer turbo-frames before Turbo snapshots the page so a
// cached snapshot doesn't re-open the dialog when you navigate back.
document.addEventListener("turbo:before-cache", () => {
  document
    .querySelectorAll('turbo-frame[id="modal"], turbo-frame[id="drawer"]')
    .forEach((frame) => {
      frame.innerHTML = "";
    });
});

export { application };
