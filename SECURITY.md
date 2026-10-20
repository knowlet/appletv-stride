# Security and privacy boundary

This is an exercise-display prototype, not a medical device or a safety-rated motion controller.

## Pairing and transport

- The TV generates a fresh 128-bit key with `SecRandomCopyBytes`. Bonjour advertises only a random service name, never the key.
- The key is transferred through an on-screen QR code or manual 32-hex-character input. Do not publish pairing-screen screenshots. Pairing codes are held in memory and replaced on app restart or explicit rotation.
- Network.framework uses TLS 1.2 with `TLS_PSK_WITH_AES_128_GCM_SHA256`. This authenticates possession of the random key and encrypts motion packets. It is not certificate pinning and does not provide forward secrecy. There is no insecure/plaintext fallback or always-accept trust callback. A six-digit PIN is deliberately not used as a TLS key.
- This pairing format is not a PAKE and must never be weakened to a human-chosen short password. Manual entry validates key shape, not randomness; the TV-generated key is the intended source.
- Only one authenticated motion channel becomes active. At most four incoming handshakes are retained, each with a five-second deadline. The server drops an active source after three seconds without a complete valid packet. Local attackers can still deny availability; do not expose the listener to the public Internet.
- The parser limits each JSON frame to 4096 bytes, each receive to 4096 bytes, decoded packet batches to 64, and each channel to 30 packets/second. Outbound application backlog holds at most one replacement packet plus one in-flight send.
- Packets validate version, finite numeric ranges, motion consistency, counter monotonicity, session identity, and increasing sequence. Out-of-order/replayed packets do not renew the playback engine's freshness timer.

## Stop behavior and clocks

The receiver uses its own monotonic clock, not the phone's wall clock, for its 1.2-second stale-source cutoff. Explicit stop and remote pause stop the target immediately; actual detection/rendering has latency. A long renderer tick is not integrated as traveled distance. Receiver freshness does not measure one-way network latency: delayed, valid TCP traffic is still a real-device test item, not a proven worst-case stop guarantee.

The TV pause is latched until the user resumes. The phone sends stop/disconnect on loss of foreground. There is no fake background-audio service or undocumented background networking entitlement.

## Data and content

The app does not request HealthKit or collect heart rate, location, account identifiers, or a movement history. Raw Core Motion and camera frames remain on the phone. Cadence, cumulative detector events, confidence, a random in-memory session ID, and sequence numbers traverse the paired local connection. No telemetry SDK is included.

Optional media fetching is separate: a user-selected HTTPS media provider sees the normal network request and may have its own policies. Credentials in media URLs and blanket ATS exceptions are rejected. URLs and keys are not persisted or logged by this implementation. There is no Street View scraper, bulk imagery cache, or bundled API token.

## Verification limits

Portable tests cover parsing and state-machine behavior. They do not demonstrate a successful TLS handshake on iOS/tvOS, certify the cipher configuration, or prove the absence of sensor false positives. Apple SDK compilation, simulator/device integration, denial/rotation tests, and real-device stop latency must be checked independently. See `docs/ACCEPTANCE.md`.

Do not put secrets or pairing codes into public issues. Report non-sensitive reproduction details in the repository; use a private channel for exploitable findings and private data.
