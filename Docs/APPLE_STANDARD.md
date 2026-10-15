# Experimental Apple Standard physical-desktop session

`VNCConnection.Settings.isAppleStandardEnabled` opts into an enhanced RFB 003.889 physical-desktop profile. Default settings and generic RFB behavior remain unchanged. RemoteLah exposes this only in Debug builds.

The profile implements enhanced ClientInit, extended ServerInit and permitted console selection, type-30 account authentication and session-key retention, session encryption at complete-update boundaries, automatic framebuffer subscriptions, alpha cursor caching, display transitions, RGB555/zlib 1002, and existing experimental MVS decoding. It never advertises HP 1010/media 1110 or configures virtual displays/UDP. Full quality is expressed by omitting lossy Apple image codecs from settings.frameEncodings. The independent HP backend is outside this library path.

Protocol format research: https://github.com/peetinc/noVNC-ARD/blob/main/ard/ard-patch.js and its `ard-constants.js`, `session-select.js`, and `decoders/zlib-thousands.js`. The Swift session, record, and RGB555 implementations are independently written. The already-bundled JavaScript MVS decoder has its original provenance and MPL-2.0 license under Resources/AppleMVS.

The automatic-update message uses a zero/default 32-bit field as in noVNC-ARD. A separate HP-oriented reference labels the field differently; this has not been independently captured from native Standard here. Native session proof is required before production promotion.

Bounds: ServerInit names 65535 bytes, session messages 4096 bytes, cursor compressed payload 1 MiB and 512x512 pixels, cursor cache 256 entries/16 MiB, RGB555/MVS payload 8 MiB, canvas 16384 per side/33554432 pixels, ciphertext 65520 bytes, and uint32 record-sequence exhaustion. Any record framing/integrity failure is terminal; do not reuse its transport for a fallback. Codec reference state is decoded serially; only completed presentation snapshots may be dropped.

Tests use generated pixels/dummy credentials and deliberately fragment TCP reads and encrypted records. They cover enhanced login, encryption activation, server-pushed pixels, input, idle subscription renewal, resize, tamper/replay/poison behavior, encoding separation and refused virtual-only sessions. These are synthetic fixtures, not native-client or real-Mac codec captures. Type-33 Standard login, native geometry/display selection, and real MVS refinement/cache replay remain unvalidated.
