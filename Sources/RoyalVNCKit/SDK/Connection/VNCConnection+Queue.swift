#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Queue Management
extension VNCConnection {
	func enqueueKeyEvent(key: VNCKeyCode,
						 isDown: Bool) {
		guard settings.inputMode != .none else { return }

		framebufferRequestGate.noteInput()

        let isARD = state.isAppleRemoteDesktop
		let keyCode = key.rawValue(forAppleRemoteDesktop: isARD)

		let keyEvent = VNCProtocol.KeyEvent(isDown: isDown,
											key: keyCode)

		logger.logDebug("Enqueuing Key \(keyEvent.description)")

		enqueueClientToServerMessage(keyEvent)
	}

    func enqueueMouseEvent(nonNormalizedX: UInt16,
                           nonNormalizedY: UInt16, coalesceMove: Bool = false) {
        guard settings.inputMode != .none else { return }

        let normalizedPosition = normalizedMousePosition(x: nonNormalizedX,
                                                         y: nonNormalizedY)

        enqueueMouseEvent(buttons: mouseButtonState,
                          position: normalizedPosition, coalesceMove: coalesceMove)
    }

    func enqueueMouseEvent(buttons: VNCProtocol.MousePointerButton,
                           nonNormalizedX: UInt16,
                           nonNormalizedY: UInt16, coalesceMove: Bool = false) {
        guard settings.inputMode != .none else { return }

        let normalizedPosition = normalizedMousePosition(x: nonNormalizedX,
                                                         y: nonNormalizedY)

        enqueueMouseEvent(buttons: buttons,
                          position: normalizedPosition, coalesceMove: coalesceMove)
    }

	func enqueueMouseEvent(buttons: VNCProtocol.MousePointerButton,
						   position: VNCProtocol.MousePosition, coalesceMove: Bool = false) {
		guard settings.inputMode != .none else { return }

		framebufferRequestGate.noteInput()

        let pointerEvent = VNCProtocol.PointerEvent(buttons: buttons,
													position: position)

		clientToServerMessageQueue.enqueue(pointerEvent, replaceable: coalesceMove)
        outboundWake.signal()
	}

	func enqueueClientCutTextMessage(_ text: String) {
		let clientCutTextMessage = VNCProtocol.ClientCutText(text: text)

		enqueueClientToServerMessage(clientCutTextMessage)
	}

	func enqueueClientToServerMessage(_ message: VNCSendableMessage) {
		clientToServerMessageQueue.enqueue(message)
        outboundWake.signal()
	}

    func normalizedMousePosition(x: UInt16,
                                 y: UInt16) -> VNCProtocol.MousePosition {
        var normalizedX = x
        var normalizedY = y

        let framebufferWidth = framebuffer?.size.width ?? 0
        let framebufferHeight = framebuffer?.size.height ?? 0

        if normalizedY > framebufferHeight {
            normalizedY = framebufferHeight
        }

        if normalizedX > framebufferWidth {
            normalizedX = framebufferWidth
        }

        let normalizedPosition = VNCProtocol.MousePosition(x: normalizedX,
                                                           y: normalizedY)

        return normalizedPosition
    }
}
