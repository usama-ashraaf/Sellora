import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["controls", "button", "panel"]

  connect() {
    this.controlsTarget.hidden = false
    this.select("normal")
  }

  change(event) {
    this.select(event.currentTarget.dataset.mode)
  }

  select(mode) {
    this.buttonTargets.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.mode === mode)))
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.mode !== mode })
  }
}
