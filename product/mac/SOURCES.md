# Primary references — recovery bibliography

Reconstructed 17 September 2026 because the original SOURCES.md was not supplied. Identifier mappings below are recovery entry points, not a claim to reproduce the lost bibliography exactly. Stage owners verify API behavior, dependency revisions and licenses before adoption.

| Original identifier | Primary entry point |
|---|---|
| A01 | [Apple Xcode support](https://developer.apple.com/xcode/system-requirements): currently lists Xcode 27 / Swift 6.4 and macOS 26.6+ host requirement. Recovery host has Xcode 26.6; no new app build was attempted. |
| A02 | [Apple: What's new in TextKit and text views](https://developer.apple.com/videos/play/wwdc2022/10090/), [AppKit TextKit](https://developer.apple.com/documentation/appkit/textkit) |
| A03 | [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) |
| A04 | [NSDocument](https://developer.apple.com/documentation/appkit/nsdocument) |
| A05 | [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) |
| A06 | [NSApplication presentation options](https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.struct) |
| G01 | [Google: Drive for desktop](https://support.google.com/drive/answer/10838124) |
| R02 | [Pinned NostrShot Package.swift](https://github.com/mariusschober/NostrShot/blob/cf28e9652dc8eb7bbd85008163071820cd781998/mac/Package.swift) — recovered live through GitHub; P256K 0.23.2, KeyboardShortcuts 3.0.1 |
| N03 | [Pinned NIP-44](https://github.com/nostr-protocol/nips/blob/a2494f4f81d46684e5814a9bf35e2b1df978f955/44.md) — extended length and 65535/65536/65537 boundaries confirmed |
| N04 | [NIP-44 reference implementations](https://github.com/paulmillr/nip44) — review and pin exact Swift implementation before use; project-level audit claims do not imply every port is audited |

N01–N09 is recovered as a reference group rather than inventing the lost one-to-one numbering. All normative NIPs below use the original pin `a2494f4f81d46684e5814a9bf35e2b1df978f955`:

- [NIP-01: events and relays](https://github.com/nostr-protocol/nips/blob/a2494f4f81d46684e5814a9bf35e2b1df978f955/01.md).
- [NIP-19: identifiers](https://github.com/nostr-protocol/nips/blob/a2494f4f81d46684e5814a9bf35e2b1df978f955/19.md).
- [NIP-23: long form](https://github.com/nostr-protocol/nips/blob/a2494f4f81d46684e5814a9bf35e2b1df978f955/23.md).
- [NIP-37: drafts](https://github.com/nostr-protocol/nips/blob/a2494f4f81d46684e5814a9bf35e2b1df978f955/37.md).
- [NIP-44: encryption](https://github.com/nostr-protocol/nips/blob/a2494f4f81d46684e5814a9bf35e2b1df978f955/44.md).
- [NIP-42: relay authentication](https://github.com/nostr-protocol/nips/blob/a2494f4f81d46684e5814a9bf35e2b1df978f955/42.md).
- [NIP-65: relay lists](https://github.com/nostr-protocol/nips/blob/a2494f4f81d46684e5814a9bf35e2b1df978f955/65.md).
- [NIP-40: expiration](https://github.com/nostr-protocol/nips/blob/a2494f4f81d46684e5814a9bf35e2b1df978f955/40.md).
- [NIP-09: deletion](https://github.com/nostr-protocol/nips/blob/a2494f4f81d46684e5814a9bf35e2b1df978f955/09.md).
- [NIP-11: relay information](https://github.com/nostr-protocol/nips/blob/a2494f4f81d46684e5814a9bf35e2b1df978f955/11.md).

Normative HWP sources remain in the frozen [SOURCES.md](../../protocol/v0/SOURCES.md). Named Swift dependencies are implementation selections in ARCHITECTURE.md; versions/licenses not established by the supplied artifacts remain Stage 01 verification work. This bibliography alone does not validate the historical NostrShot code audit.
