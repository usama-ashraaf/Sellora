import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "panel", "panels", "slot", "marker"]

  connect() {
    this.update = this.update.bind(this)
    this.schedule = this.schedule.bind(this)
    this.arrangePanels = this.arrangePanels.bind(this)
    this.desktopMotion = window.matchMedia("(min-width: 761px) and (prefers-reduced-motion: no-preference)")
    this.desktopMotion.addEventListener("change", this.arrangePanels)
    window.addEventListener("scroll", this.schedule, { passive: true })
    window.addEventListener("resize", this.schedule)
    this.panels = [...this.panelTargets]
    this.arrangePanels()
  }

  disconnect() {
    this.desktopMotion.removeEventListener("change", this.arrangePanels)
    window.removeEventListener("scroll", this.schedule)
    window.removeEventListener("resize", this.schedule)
    cancelAnimationFrame(this.frame)
  }

  arrangePanels() {
    this.panels.forEach((panel, index) => {
      const parent = this.desktopMotion.matches ? this.panelsTarget : this.slotTargets[index]
      parent.append(panel)
    })
    this.update()
  }

  schedule() {
    if (!this.frame) this.frame = requestAnimationFrame(this.update)
  }

  update() {
    this.frame = null
    const readingLine = Math.min(window.innerHeight * 0.3, 200)
    let active = 0
    this.stepTargets.forEach((step, index) => {
      if (step.getBoundingClientRect().top <= readingLine) active = index
    })
    this.stepTargets.forEach((step, index) => step.classList.toggle("is-current", index === active))
    this.panels.forEach((panel, index) => { panel.hidden = this.desktopMotion.matches && index !== active })
    this.markerTargets.forEach((marker, index) => {
      if (index === active) marker.setAttribute("aria-current", "step")
      else marker.removeAttribute("aria-current")
    })
  }
}
