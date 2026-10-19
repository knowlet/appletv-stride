# Acceptance and verification

## Initial evidence

- [x] Linux Swift 6.2.1: 43 XCTest cases pass using synthetic motion and protocol inputs.
- [x] Apple-target Swift source syntax parses on the local Linux compiler (not SDK type checking).
- [ ] Exact-head GitHub Actions core job checked.
- [ ] Exact-head Apple SDK iPhone simulator build checked.
- [ ] Exact-head Apple SDK Apple TV simulator build checked.
- [ ] App launch, UI/focus navigation and device integration observed.

CI evidence must be attached to a commit SHA. Do not carry an older commit's green check onto newer code. Update this record only with observed results.

## Real-device checklist — all pending

1. Install both apps with correct bundle IDs/signing. Grant or deny each permission separately. With permissions denied, display a useful error and remain stopped.
2. Scan the TV's QR code. Verify only the matching Bonjour service connects. Verify a wrong key fails, the second controller cannot replace the active one, and key rotation invalidates the old code.
3. Test iPhone + TV on Wi-Fi, then phone Wi-Fi + wired TV. Repeat with network isolation/firewall enabled and disabled; report a connection failure, not fake movement.
4. Test a securely attached phone at roughly 60 / 120 / 180 steps per minute, no movement, ordinary gestures, an isolated bump, sitting down, and placement/orientation changes. Record false positives, missed steps and stop latency. Wrist movement is not validated by this test.
5. At each cadence: walk, stop, restart, pause with TV remote while still moving, and resume. Incoming source frames must not override a latched TV pause.
6. Lock the phone, open Control Center, background the app, remove network, suspend TV, restart either app, and rotate pairing while active. Ensure motion stops and session recovery requires deliberate reconnection where documented.
7. Interrupt samples while leaving networking active. Send malformed, oversized, duplicate, reordered, wrong-session and non-finite packets. Check that the screen stops and memory does not grow with input size or duration.
8. Add loss, jitter and delayed TCP delivery. Receiver arrival-time freshness is not an end-to-end latency proof. Measure a worst-case stop bound; add application-level freshness negotiation before claiming one.
9. Run a 30-minute session to measure battery drain, heat, memory, frame pacing, touch/remote focus and reconnection behavior.
10. Verify a rights-cleared local/hosted HTTPS video in flat and 360 modes; inspect inside-sphere orientation and aspect ratio. Test buffering, unsupported codec, expired URL and end-of-file. No playback control may bypass the motion/pause authority.

## Not acceptance evidence

A core unit-test pass does not establish real-motion accuracy. A simulator build does not establish device signing or TLS interoperability. A generated 3D scene does not establish a licensed real-world route library. A source interface or roadmap is not implemented Apple Watch or Mapillary support.
