import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.focus({ preventScroll: true })
    this.element.scrollIntoView({ behavior: "instant", block: "center" })
  }
}
