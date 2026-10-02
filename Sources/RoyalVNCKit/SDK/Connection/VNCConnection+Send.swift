#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// MARK: - Client to Server Messages
extension VNCConnection {
	func startSendLoop() {
        logger.logDebug("Starting send loop")

		sendTask = Task(priority: taskPriority) {
			while !state.disconnectRequested,
                  connection.isReady {
				do {
					try await send()
				} catch {
					handleBreakingError(error)
				}
			}
		}
	}

	func sendFramebufferUpdateRequest() async throws {
		guard !state.disconnectRequested, connection.isReady, let framebuffer,
              !state.areContinuousUpdatesEnabled else {
            return
        }
        
		let incremental = state.incrementalUpdatesEnabled

		let fullFramebufferRegion = VNCRegion(location: .zero,
											  size: framebuffer.size)

		// Request next update
		try await sendFramebufferUpdateRequest(incremental: incremental,
											   region: fullFramebufferRegion)

		if !incremental {
			state.incrementalUpdatesEnabled = true
		}
	}

	func sendEnableContinuousUpdates() async throws {
		guard !settings.lowDataMode, let framebuffer,
              state.areContinuousUpdatesSupported,
              !state.areContinuousUpdatesEnabled else {
            return
        }

		let fullFramebufferRegion = VNCRegion(location: .zero,
											  size: framebuffer.size)

		try await sendEnableContinuousUpdates(enable: true,
											  region: fullFramebufferRegion)

		state.areContinuousUpdatesEnabled = true
	}
}

private extension VNCConnection {
	func send() async throws {
		guard !state.disconnectRequested, connection.isReady else { return }

        // Input is always sent immediately, independently of the picture request cadence.
        if let message = clientToServerMessageQueue.dequeue() {
            try await sendMessage(message)
        } else {
            let delay = framebufferRequestGate.nextRequestDelay(policy: settings.framebufferRequestPolicy)
            try await Task.sleep(seconds: max(0.000_001, delay))
        }
        if !state.disconnectRequested, settings.lowDataMode, framebufferRequestGate.takeRequest(policy: settings.framebufferRequestPolicy) {
            try await sendFramebufferUpdateRequest()
        }
	}

	func sendFramebufferUpdateRequest(incremental: Bool,
									  region: VNCRegion) async throws {
		let framebufferUpdateRequest = VNCProtocol.FramebufferUpdateRequest(incremental: incremental,
																			xPosition: region.location.x,
																			yPosition: region.location.y,
																			width: region.size.width,
																			height: region.size.height)

        (delegate as? VNCUpdateTimingObserver)?.framebufferUpdateRequested()
        (delegate as? VNCFramebufferStatisticsObserver)?.framebufferUpdateRequested(incremental: incremental)
		try await sendMessage(framebufferUpdateRequest)
	}

	func sendEnableContinuousUpdates(enable: Bool,
									 region: VNCRegion) async throws {
		let message = VNCProtocol.EnableContinuousUpdates(enable: enable,
														  xPosition: region.x,
														  yPosition: region.y,
														  width: region.width,
														  height: region.height)

		try await sendMessage(message)
	}

	func sendMessage(_ message: VNCSendableMessage) async throws {
		try await message.send(connection: connection)
	}
}
