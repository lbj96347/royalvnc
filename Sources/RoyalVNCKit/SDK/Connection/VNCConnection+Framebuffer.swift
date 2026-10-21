#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// MARK: - Framebuffer Delegate
extension VNCConnection: VNCFramebufferDelegate {
	func framebuffer(_ framebuffer: VNCFramebuffer,
					 didUpdateRegion updatedRegion: VNCRegion) {
		notifyDelegateAboutFramebuffer(framebuffer,
									   updatedRegion: updatedRegion)
	}

	func framebuffer(_ framebuffer: VNCFramebuffer,
					 didUpdateDesktopName newDesktopName: String) {
		state.desktopName = newDesktopName
	}

	func framebuffer(_ framebuffer: VNCFramebuffer,
					 didUpdateCursor cursor: VNCCursor) {
		notifyDelegateAboutUpdatedCursor(cursor)
	}

	func framebuffer(_ framebuffer: VNCFramebuffer,
					 sizeDidChange newSize: VNCSize,
					 screens newScreens: [VNCScreen]) {
		recreateFramebuffer(size: newSize,
							screens: newScreens,
							pixelFormat: framebuffer.sourcePixelFormat)
	}
}

extension VNCConnection {
	func recreateFramebuffer(size: VNCSize,
							 screens: [VNCScreen],
							 pixelFormat: VNCProtocol.PixelFormat) {
		state.incrementalUpdatesEnabled = false
        if settings.isAppleStandardEnabled { appleStandard.needsRearm = true }

		let newFramebuffer: VNCFramebuffer

		do {
            newFramebuffer = try VNCFramebuffer(logger: logger,
                                                size: size,
                                                screens: screens,
                                                pixelFormat: pixelFormat,
                                                allocator: framebufferAllocator)
		} catch {
			handleBreakingError(error)

			return
		}

        // Metadata can precede DesktopSize in the same update. Preserve it only when
        // its canvas matches the new surface; old geometry must never crop a new size.
        if let layout = self.framebuffer?.appleDisplayLayout,
           layout.width == Int(size.width), layout.height == Int(size.height) {
            newFramebuffer.updateAppleDisplayLayout(layout)
        }
        self.framebuffer?.delegate = nil

		newFramebuffer.delegate = self

		self.framebuffer = newFramebuffer
        // ServerInit may advertise 0x0 while the locked console is starting.
        // DesktopSize is authoritative once a surface has been allocated. Keep
        // the request guard in sync so the first full update can be requested.
        state.framebufferWidth = size.width
        state.framebufferHeight = size.height

		notifyDelegateAboutFramebufferResize(newFramebuffer)
	}
}
