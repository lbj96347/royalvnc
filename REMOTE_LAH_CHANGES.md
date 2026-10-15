# RemoteLah's RoyalVNC dependency

Source: https://github.com/lbj96347/royalvnc at
`f803193d26502c0f32d42d4f010d9aaf2181f967` (`remotelah-adaptive`).
The upstream MIT license is retained in LICENSE. Sources and tests are vendored so
SPM and Xcode use the same reproducible implementation without an unpublished remote revision.

Local changes:

- Opt-in Apple display-layout (1105) reception for authenticated ARD connections.
- Immutable backing-pixel display records including Apple's main-display flag.
- Metadata lives with the framebuffer and is read under its existing completed-update gate.
- Unknown or invalid layouts clear selection metadata and preserve standard framebuffer decoding.
- Resize and subsequent rectangles in one framebuffer update use the replacement surface;
  pixel statistics exclude rectangles painted into the discarded surface.

Protocol references: iShareScreen's `src/isharescreen/proxy/protocol/rfb.py` (20-byte
version-5 header and 56-byte records), and `docs/apple_vnc_rfc.md` (per-display main
flag). These are independently reverse engineered; synthetic fixtures do not
establish interoperability with every macOS version.

## Screen Sharing startup and MVS — 2026-10-15

- Add optional pixel-rectangle begin/completion observers under the framebuffer gate, without changing complete-update statistics or framebuffer request pacing.
- Allow an explicitly requested Apple half-size message between the ARD handshake and first full request. This remains experimental until a real Mac confirms geometry and input semantics.
- Add opt-in encoding 1011 (Apple MVS) with a JavaScriptCore adapter for the bundled noVNC-ARD decoder, revision d699293635083c9e0c30c8f9480993865653772a. Full-image Rice/DCT, partial refinement/Huffman, quantization, match tiles, and caches are implemented. Payload/canvas limits, strict decode failures, framebuffer identity resets, and BGRA/native framebuffer integration are enforced. Quantization and skip-only updates do not claim pixel readiness.
- JavaScript source and MPL-2.0 license ship in the AppleMVS resource bundle. Source modules are loaded locally, with module declarations flattened; warnings become fatal decode failures. There is no remote script loading. See the bundled PROVENANCE.md.
- Add synthetic decoder tests for expected pixels, refinement against a full baseline, cache reuse, quantization, unaligned/edge tiles, truncation, invalid markers, and malformed geometry. Live Mac capture interoperability and device performance are not established.
