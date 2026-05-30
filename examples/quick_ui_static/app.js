const form = document.querySelector("[data-convert-form]");
const submitButton = document.querySelector("[data-submit-button]");
const readyLabel = document.querySelector("[data-ready-label]");
const busyLabel = document.querySelector("[data-busy-label]");

if (form && submitButton && readyLabel && busyLabel) {
  form.addEventListener("submit", () => {
    submitButton.disabled = true;
    submitButton.setAttribute("aria-busy", "true");
    readyLabel.hidden = true;
    busyLabel.hidden = false;

    const fields = form.querySelectorAll("input, select, textarea");
    fields.forEach((field) => {
      if (field !== submitButton) {
        field.setAttribute("readonly", "readonly");
      }
    });
  });
}
