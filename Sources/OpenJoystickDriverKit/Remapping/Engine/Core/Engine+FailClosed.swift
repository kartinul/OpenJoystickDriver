import Foundation

extension RemappingEventEngine {

  func failClosed(potentiallyHeld: Set<RemappingHeldOutput>) async {
    state = RemappingEngineState()
    faulted = true
    uncertainHeldOutputs = potentiallyHeld
    uncertainGamepadDevices.formUnion(heldGamepadDevices)
    heldGamepadDevices.removeAll()
    uncertainPhysicalDevices.formUnion(heldPhysicalOwners.keys)
    heldPhysicalOwners.removeAll()
    try? await releaseUncertainOutputs()
  }

  static func accountForDelivered(
    _ action: RemappingSystemInputAction,
    in heldOutputs: inout Set<RemappingHeldOutput>
  ) {
    switch action {
    case .modifierDown(let modifier): heldOutputs.insert(.modifier(modifier))
    case .modifierUp(let modifier): heldOutputs.remove(.modifier(modifier))
    case .keyDown(let key): heldOutputs.insert(.key(key))
    case .keyUp(let key): heldOutputs.remove(.key(key))
    case .mouseButtonDown(let button): heldOutputs.insert(.mouseButton(button))
    case .mouseButtonUp(let button): heldOutputs.remove(.mouseButton(button))
    case .mouseMoved, .pointerDelta, .scrolled, .scrollDelta: break
    }
  }

  static func accountForUncertain(
    _ action: RemappingSystemInputAction,
    in heldOutputs: inout Set<RemappingHeldOutput>
  ) {
    switch action {
    case .modifierDown(let modifier), .modifierUp(let modifier):
      heldOutputs.insert(.modifier(modifier))
    case .keyDown(let key), .keyUp(let key): heldOutputs.insert(.key(key))
    case .mouseButtonDown(let button), .mouseButtonUp(let button):
      heldOutputs.insert(.mouseButton(button))
    case .mouseMoved, .pointerDelta, .scrolled, .scrollDelta: break
    }
  }

  static func releaseOrder(_ outputs: Set<RemappingHeldOutput>) -> [RemappingHeldOutput] {
    outputs.sorted { lhs, rhs in
      if lhs.releaseOrder != rhs.releaseOrder { return lhs.releaseOrder < rhs.releaseOrder }
      if lhs.releaseOrder == 2 { return lhs.stableName > rhs.stableName }
      return lhs.stableName < rhs.stableName
    }
  }
}
