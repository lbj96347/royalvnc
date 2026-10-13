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
