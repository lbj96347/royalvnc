import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

extension VNCProtocol {
    /// Opt-in only. Apple MVS is a TCP still-image codec, separate from HEVC media.
    final class AppleMVSEncoding: VNCFrameEncoding {
        let encodingType = VNCFrameEncodingType.appleMVS.rawValue
        private(set) var changedPixels = false
        #if canImport(JavaScriptCore)
        private var decoder: AppleMVSDecoder?
        private weak var previousFramebuffer: VNCFramebuffer?
        #endif

        func decodeRectangle(_ rectangle: VNCProtocol.Rectangle, framebuffer: VNCFramebuffer,
                             connection: NetworkConnectionReading, logger: VNCLogger) async throws {
            changedPixels = false
            let length = Int(try await connection.readUInt32())
            guard (1...AppleMVSLimits.maximumPayload).contains(length) else {
                throw VNCError.protocol(.frameDecode(encodingType: encodingType, underlyingError: nil))
            }
            let payload = try await connection.readBuffered(length: length, minimumChunkSize: 1,
                                                             maximumChunkSize: 16_384)
            #if canImport(JavaScriptCore)
            if decoder == nil || previousFramebuffer !== framebuffer {
                decoder = try AppleMVSDecoder()
                previousFramebuffer = framebuffer
            }
            framebuffer.allocator.lockReadWrite()
            defer { framebuffer.allocator.unlockReadWrite() }
            do {
                changedPixels = try decoder!.decode(payload, width: Int(framebuffer.size.width),
                    height: Int(framebuffer.size.height), surface: framebuffer.surfaceAddress,
                    x: Int(rectangle.xPosition), y: Int(rectangle.yPosition),
                    width: Int(rectangle.width), height: Int(rectangle.height))
            } catch {
                decoder = nil
                throw VNCError.protocol(.frameDecode(encodingType: encodingType, underlyingError: error))
            }
            if changedPixels { framebuffer.didUpdate(region: rectangle.region) }
            #else
            throw VNCError.protocol(.notImplemented(feature: "Apple MVS requires JavaScriptCore"))
            #endif
        }
    }
}

enum AppleMVSLimits {
    static let maximumPayload = 8_388_608
    static let maximumPixels = 33_554_432
}

#if canImport(JavaScriptCore)
/// The bundled MPL-2.0 decoder runs in a private interpreter context. Nothing is
/// loaded from the network. Its source and license ship in the resource bundle.
/// The connection's framebuffer gate serializes every call and owns the pixels.
final class AppleMVSDecoder {
    private let context: JSContext
    private let decodeFunction: JSValue

    init() throws {
        guard let context = JSContext() else { throw VNCError.protocol(.invalidData) }
        var source = "const Log = { Warn: function(message) { throw new Error(message); } };\n"
        for name in ["mvs-bitstream", "mvs-tables", "mvs-idct", "mvs-rice", "mvs-huffman", "mvs"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "AppleMVS") else {
                throw VNCError.protocol(.invalidData)
            }
            var script = try String(contentsOf: url, encoding: .utf8)
            script = script.replacingOccurrences(of: #"(?s)import\s+.*?;"#, with: "", options: .regularExpression)
            script = script.replacingOccurrences(of: "export default ", with: "")
                .replacingOccurrences(of: "export ", with: "")
            // A malformed unary coefficient must not consume an entire large payload.
            script = script.replacingOccurrences(of: "count++;", with: "if (++count > 1024) throw new Error('MVS unary overflow');")
            source += script + "\n"
        }
        guard context.evaluateScript(source) != nil, context.exception == nil else {
            throw VNCError.protocol(.invalidData)
        }
        let bridge = #"""
        (function() {
            const decoder = new ArdMVSDecoder();
            // Native framebuffer is BGRA. Coefficient/cache tile buffers stay RGBA.
            decoder._putTile = function(x, y, w, h) {
                const fb = this._fb, tile = this._tileBuf;
                for (let row = 0; row < h; row++) {
                    for (let col = 0; col < w; col++) {
                        const s = (row * 8 + col) * 4;
                        const d = ((y + row) * this._fbWidth + x + col) * 4;
                        fb[d] = tile[s + 2]; fb[d + 1] = tile[s + 1];
                        fb[d + 2] = tile[s]; fb[d + 3] = 255;
                    }
                }
            };
            decoder._blitRegion = function(display, x, y, w, h) {
                if (w > 0 && h > 0) display.changed = true;
            };
            const cache = decoder._loadCacheAndRender;
            decoder._loadCacheAndRender = function(index) {
                if (index <= 0 || index >= 65000) throw new Error('MVS invalid cache slot');
                return cache.call(this, index);
            };
            return function(payload, surface, width, height, x, y, w, h) {
                const data = new Uint8Array(payload.buffer, payload.byteOffset, payload.byteLength);
                if (data[0] > 2 || (data[0] === 2 && data.length !== 129) ||
                    (data[0] === 0 && data.length < 8) || (data[0] === 1 && data.length < 6)) {
                    throw new Error('MVS invalid update');
                }
                if (data[0] !== 2 && (data[1] > 64 || data[2] > 64)) throw new Error('MVS invalid coefficient limit');
                const display = { width, height, changed: false };
                decoder._ensureScreenState(display);
                decoder._fb = surface;
                decoder._fb32 = new Uint32Array(surface.buffer, surface.byteOffset, surface.byteLength / 4);
                const sock = {
                    rQwait: function() { return false; },
                    rQshift32: function() { return data.length; },
                    rQshiftBytes: function() { return data; }
                };
                try {
                    decoder.decodeRect(x, y, w, h, sock, display, 24);
                    return display.changed;
                } finally {
                    // The native surface must never escape the synchronous call.
                    decoder._fb = null; decoder._fb32 = null;
                }
            };
        })()
        """#
        guard let function = context.evaluateScript(bridge), context.exception == nil else {
            throw VNCError.protocol(.invalidData)
        }
        self.context = context
        decodeFunction = function
    }

    func decode(_ payload: Data, width canvasWidth: Int, height canvasHeight: Int,
                surface: UnsafeMutableRawPointer, x: Int, y: Int, width: Int, height: Int) throws -> Bool {
        guard (1...AppleMVSLimits.maximumPayload).contains(payload.count),
              canvasWidth > 0, canvasHeight > 0, canvasWidth <= 16_384, canvasHeight <= 16_384,
              canvasWidth * canvasHeight <= AppleMVSLimits.maximumPixels,
              x >= 0, y >= 0, width >= 0, height >= 0,
              x <= canvasWidth, y <= canvasHeight,
              width <= canvasWidth - x, height <= canvasHeight - y else {
            throw VNCError.protocol(.invalidData)
        }
        context.exception = nil
        // Payload is copied once into a typed array; no NSNumber per byte.
        let input = UnsafeMutableRawPointer.allocate(byteCount: payload.count, alignment: 8)
        payload.copyBytes(to: input.assumingMemoryBound(to: UInt8.self), count: payload.count)
        let freeInput: JSTypedArrayBytesDeallocator = { bytes, _ in bytes?.deallocate() }
        guard let inputObject = JSObjectMakeTypedArrayWithBytesNoCopy(context.jsGlobalContextRef,
            kJSTypedArrayTypeUint8Array, input, payload.count, freeInput, nil, nil) else {
            input.deallocate()
            throw VNCError.protocol(.invalidData)
        }
        guard let pixelsObject = JSObjectMakeTypedArrayWithBytesNoCopy(context.jsGlobalContextRef,
            kJSTypedArrayTypeUint8Array, surface, canvasWidth * canvasHeight * 4, nil, nil, nil) else {
            throw VNCError.protocol(.invalidData)
        }
        let inputValue = JSValue(jsValueRef: inputObject, in: context)!
        let pixelsValue = JSValue(jsValueRef: pixelsObject, in: context)!
        let changed = decodeFunction.call(withArguments: [inputValue, pixelsValue, canvasWidth, canvasHeight, x, y, width, height])
        guard context.exception == nil, let changed, !changed.isUndefined else {
            context.exception = nil
            throw VNCError.protocol(.invalidData)
        }
        return changed.toBool()
    }
}
#endif
