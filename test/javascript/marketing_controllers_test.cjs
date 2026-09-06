const assert = require("assert").strict
const fs = require("fs")
const path = require("path")

function controllerClass(name) {
  const source = fs.readFileSync(path.join(__dirname, "../../app/javascript/controllers", `${name}_controller.js`), "utf8")
    .replace(/^import .*\n/m, "")
    .replace("export default", "return")
  return new Function("Controller", source)(class {})
}

function node() {
  return {
    hidden: false,
    attributes: {},
    classList: { toggle() {} },
    append(child) { child.parent = this },
    setAttribute(name, value) { this.attributes[name] = value },
    removeAttribute(name) { delete this.attributes[name] }
  }
}

function auditFixture(desktopMotion, tops) {
  const media = { matches: desktopMotion, addEventListener() {}, removeEventListener() {} }
  global.window = { innerHeight: 1000, matchMedia: () => media, addEventListener() {}, removeEventListener() {} }
  global.cancelAnimationFrame = () => {}
  const controller = new (controllerClass("audit"))()
  controller.stepTargets = tops.map(top => ({ ...node(), getBoundingClientRect: () => ({ top }) }))
  controller.panelTargets = tops.map(node)
  controller.slotTargets = tops.map(node)
  controller.markerTargets = tops.map(node)
  controller.panelsTarget = node()
  controller.connect()
  return { controller, media }
}

let passed = 0
function check(name, assertion) {
  assertion()
  passed += 1
  console.log(`PASS: ${name}`)
}

check("desktop evidence anchor selects evidence instead of the next visible step", () => {
  const { controller } = auditFixture(true, [-318, 32, 420, 808])
  assert.deepEqual(controller.panels.map(panel => panel.hidden), [true, false, true, true])
  assert.equal(controller.markerTargets[1].attributes["aria-current"], "step")
  controller.disconnect()
})

check("reduced-motion or mobile layout exposes all stages beside their own text", () => {
  const { controller } = auditFixture(false, [-800, -400, 32, 600])
  controller.panels.forEach((panel, index) => {
    assert.equal(panel.hidden, false)
    assert.equal(panel.parent, controller.slotTargets[index])
  })
  controller.disconnect()
})

check("resizing back to desktop restores one current panel without losing stages", () => {
  const { controller, media } = auditFixture(false, [-700, -350, 32, 420])
  media.matches = true
  controller.arrangePanels()
  controller.panels.forEach(panel => assert.equal(panel.parent, controller.panelsTarget))
  assert.deepEqual(controller.panels.map(panel => panel.hidden), [true, true, false, true])
  media.matches = false
  controller.arrangePanels()
  assert.equal(controller.panels.filter(panel => !panel.hidden).length, 4)
  controller.disconnect()
})

check("trading-day controls expose the selected content and corresponding pressed state", () => {
  const controller = new (controllerClass("priorities"))()
  controller.controlsTarget = node()
  controller.buttonTargets = ["normal", "sale"].map(mode => ({ ...node(), dataset: { mode } }))
  controller.panelTargets = ["normal", "sale"].map(mode => ({ ...node(), dataset: { mode } }))
  controller.connect()
  controller.change({ currentTarget: controller.buttonTargets[1] })
  assert.deepEqual(controller.panelTargets.map(panel => panel.hidden), [true, false])
  assert.deepEqual(controller.buttonTargets.map(button => button.attributes["aria-pressed"]), ["false", "true"])
  controller.change({ currentTarget: controller.buttonTargets[0] })
  assert.deepEqual(controller.panelTargets.map(panel => panel.hidden), [false, true])
})

console.log(`${passed} JavaScript checks passed.`)
