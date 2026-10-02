#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch

// MARK: - Server to Client Messages
extension VNCConnection {
	func startReceiveLoop() {
        logger.logDebug("Starting receive loop")

        receiveTask = Task(priority: taskPriority) {
			while !state.disconnectRequested,
                  connection.isReady {
				do {
					try await receive()
				} catch {
					handleBreakingError(error)
				}
			}
		}
	}
}

private extension VNCConnection {
	func receive() async throws {
		guard !state.disconnectRequested else {
			// Just ignore, since disconnect has already been requested
			return
		}

        guard connection.isReady else {
			throw VNCError.connection(.notReady)
		}

		let serverToClientMessage = try await VNCProtocol.ServerToClientMessage.receive(connection: connection)

		try await didReceive(messageType: serverToClientMessage.messageType)
	}

	func didReceive(messageType: UInt8) async throws {
		switch messageType {
			case VNCProtocol.FramebufferUpdate.messageType:
                (delegate as? VNCUpdateTimingObserver)?.framebufferUpdateReceived()
				try await handleFramebufferUpdateMessage()

			case VNCProtocol.SetColourMapEntries.messageType:
				try await handleSetColourMapEntriesMessage()

			case VNCProtocol.ServerCutText.messageType:
				try await handleServerCutTextMessage()

			case VNCProtocol.Bell.messageType:
				try await handleBellMessage()

			case VNCProtocol.EndOfContinuousUpdates.messageType:
				try await handleEndOfContinuousUpdatesMessage()

			default:
				throw VNCError.protocol(.unsupportedServerToClientMessage(messageType: messageType))
		}
	}

	func handleFramebufferUpdateMessage() async throws {
        await framebufferAccess.acquire()
        do {
            try await decodeFramebufferUpdateMessage()
            await framebufferAccess.release()
        } catch {
            await framebufferAccess.release()
            throw error
        }
    }

    private func decodeFramebufferUpdateMessage() async throws {
		guard let framebuffer = framebuffer else {
			throw VNCError.protocol(.framebufferUpdateReceivedWithoutFramebuffer)
		}

		logger.logDebug("Receiving Framebuffer Update")

		let startBytes = connection.receivedByteCount
        let started = DispatchTime.now().uptimeNanoseconds
        let framebufferUpdate = try await VNCProtocol.FramebufferUpdate.receive(connection: connection,
																				framebuffer: framebuffer,
																				encodings: encodings,
																				logger: logger)

		logger.logDebug("Received Framebuffer Update: \(framebufferUpdate)")

		/*
		// Write out the framebuffer for testing purposes
		try framebuffer.writeSurface()
		*/

        let statistics = VNCFramebufferUpdateStatistics(
            receivedBytes: connection.receivedByteCount - startBytes + 1,
            transferAndDecodeSeconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000,
            encodingBytes: framebufferUpdate.encodingBytes,
            pixelRectangleCount: framebufferUpdate.rectangles.count,
            updatedPixels: framebufferUpdate.rectangles.reduce(0) {
                $0 + UInt64($1.width) * UInt64($1.height)
            }
        )
        (delegate as? VNCFramebufferStatisticsObserver)?.framebufferUpdateCompleted(statistics)
        if let completedFramebuffer = self.framebuffer {
            (delegate as? VNCFramebufferCompletionObserver)?.connection(self,
                didCompleteFramebufferUpdate: completedFramebuffer, statistics: statistics)
        }
        if settings.lowDataMode {
            framebufferRequestGate.completedUpdate(hasPixelChanges: statistics.updatedPixels > 0)
        } else {
            try await sendFramebufferUpdateRequest()
        }
	}

	func handleSetColourMapEntriesMessage() async throws {
		guard let framebuffer = framebuffer else {
			throw VNCError.protocol(.setColourMapEntriesReceivedWithoutFramebuffer)
		}

		logger.logDebug("Receiving Colour Map Entries")

		let colourMapEntries = try await VNCProtocol.SetColourMapEntries.receive(connection: connection,
																				 logger: logger)

		logger.logDebug("Received Colour Map Entries")

        await framebufferAccess.acquire()
        framebuffer.updateColorMap(colourMapEntries)
        await framebufferAccess.release()
	}

	func handleServerCutTextMessage() async throws {
		logger.logDebug("Receiving Clipboard Text from Server")

		let serverCutText = try await VNCProtocol.ServerCutText.receive(connection: connection,
																		logger: logger)

		let text = serverCutText.text

		logger.logDebug("Received Clipboard Text from Server")

		guard settings.isClipboardRedirectionEnabled else { return }

		clipboard.text = text
	}

	func handleBellMessage() async throws {
		logger.logDebug("Receiving Bell Message from Server")

		_ = try await VNCProtocol.Bell.receive(connection: connection,
											   logger: logger)

		logger.logDebug("Received Bell Message from Server")

		systemSound.play()
	}

	func handleEndOfContinuousUpdatesMessage() async throws {
		let first = !state.areContinuousUpdatesSupported

		state.areContinuousUpdatesSupported = true
		state.areContinuousUpdatesEnabled = false

		if first {
			logger.logDebug("Continuous Updates supported (server sent EndOfContinuousUpdates)")
		} else {
			logger.logDebug("Disabling Continuous Updates")
		}

        if !settings.lowDataMode {
            try await sendFramebufferUpdateRequest()
        }
	}
}
