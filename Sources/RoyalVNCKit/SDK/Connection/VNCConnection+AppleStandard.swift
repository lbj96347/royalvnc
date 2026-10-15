import Foundation

extension VNCConnection {
    func selectApplePhysicalSession() async throws {
        let length = Int(try await connection.readUInt16())
        guard (10...4096).contains(length) else { throw AppleStandardError.invalidMessage }
        let info = try await connection.read(length: length)
        try await connection.write(data: AppleStandardWire.physicalSession(info: info))
        // A permitted request can be pending while the console user approves it.
        while !state.disconnectRequested {
            try Task.checkCancellation()
            let size = Int(try await connection.readUInt16())
            guard (6...4096).contains(size) else { throw AppleStandardError.invalidMessage }
            let result = try await connection.read(length: size)
            let status = AppleStandardWire.u32(result, 2)
            if status == 0 || status == 4 { return }
            guard status == 2 || status == 3 else { throw AppleStandardError.physicalDesktopUnavailable }
        }
        throw CancellationError()
    }

    func finishAppleStandardEncryption() async throws {
        // No input sender starts until the cleartext FBU carrying the rekey has completed.
        if state.framebufferWidth > 0, state.framebufferHeight > 0 {
            try await armAppleStandard(full: true)
        }
        while !connection.isAppleEncrypted, !state.disconnectRequested {
            try Task.checkCancellation()
            try await receive()
        }
        guard connection.isAppleEncrypted else { throw AppleStandardError.encryptionRequired }
        state.incrementalUpdatesEnabled = false
    }

    func completeAppleStandardUpdate() async throws {
        if let rekey = appleStandard.pendingRekey {
            guard let key = appleStandard.authKey else { throw AppleStandardError.encryptionRequired }
            await outboundAccess.acquire()
            do {
                // Initial acknowledgement uses cleartext; subsequent ones use the previous keys.
                try await connection.write(data: AppleStandardWire.encryptionAck)
                try connection.installAppleEncryption(payload: rekey, wrapKey: key)
                appleStandard.authKey = try AppleStandardRecords.unwrap(rekey, key: key).0
                appleStandard.pendingRekey = nil
                await outboundAccess.release()
            } catch { await outboundAccess.release(); throw error }
        }
        if appleStandard.needsRearm {
            appleStandard.needsRearm = false
            try await armAppleStandard(full: true)
        }
    }

    func armAppleStandard(full: Bool) async throws {
        guard !state.disconnectRequested, let framebuffer,
              state.framebufferWidth > 0, state.framebufferHeight > 0 else { return }
        let w = framebuffer.size.width, h = framebuffer.size.height
        guard w > 0, h > 0 else { return }
        var message = Data()
        if full {
            message = Data([3,0,0,0,0,0]) + AppleStandardWire.be(w) + AppleStandardWire.be(h)
            (delegate as? VNCFramebufferStatisticsObserver)?.framebufferUpdateRequested(incremental: false)
            (delegate as? VNCUpdateTimingObserver)?.framebufferUpdateRequested()
        }
        message += AppleStandardWire.automaticUpdates(width: w, height: h)
        await outboundAccess.acquire()
        do {
            try await connection.write(data: message)
            state.incrementalUpdatesEnabled = true
            await outboundAccess.release()
        } catch { await outboundAccess.release(); throw error }
    }

    func receiveAppleControl(_ type: UInt8) async throws -> Bool {
        switch type {
        case 4,7: return true // acknowledgement / no-op; no payload
        case 0x14:
            try await connection.readPadding()
            let size = Int(try await connection.readUInt16())
            guard (4...4096).contains(size) else { throw AppleStandardError.invalidMessage }
            let body = try await connection.read(length: size)
            let status = Int(body[2]) * 256 + Int(body[3])
            switch status {
            case 1: throw AppleStandardError.physicalDesktopUnavailable
            case 4,6: try await armAppleStandard(full: false)
            case 11: framebuffer?.updateCursor(.empty)
            case 12: framebuffer?.updateCursor(appleStandard.currentCursor)
            default: break
            }
            return true
        case 0x51:
            let length = Int(try await connection.readUInt16())
            let payload = try await connection.read(length: length)
            applyAppleLayout(payload)
            try await armAppleStandard(full: true)
            return true
        case 0x1f:
            // Clipboard remains disabled. Consume bounded unsolicited contents without retaining them.
            let header = try await connection.read(length: 15)
            let size = Int(AppleStandardWire.u32(header, 11))
            guard size <= 1_048_576 else { throw AppleStandardError.invalidMessage }
            var remaining = size
            while remaining > 0 {
                let chunk = min(remaining, 16384)
                _ = try await connection.read(length: chunk); remaining -= chunk
            }
            return true
        default: return false
        }
    }

    func applyAppleLayout(_ payload: Data) {
        let layout = VNCAppleDisplayLayout.parse(payload)
        if let layout, let pixelFormat = state.pixelFormat, layout.width > 0, layout.height > 0,
           layout.width <= 16384, layout.height <= 16384,
           layout.width * layout.height <= 33_554_432 {
            let size = VNCSize(width: UInt16(layout.width), height: UInt16(layout.height))
            if framebuffer?.size != size { recreateFramebuffer(size: size, screens: [], pixelFormat: pixelFormat) }
            state.framebufferWidth = size.width; state.framebufferHeight = size.height
        }
        framebuffer?.updateAppleDisplayLayout(layout)
        appleStandard.needsRearm = true
    }
}
