# Architecture

```text
iPhone Core Motion (50 Hz)              future Watch adapter (NOT implemented)
  userAcceleration · -gravity            workout lifetime + sensor calibration
  signed vertical g                           |
  smoothing / hysteresis / cadence       future iPhone bridge
              |                               |
              +---- MotionPacket v1 <----------+
                         |
            Bonjour discovery + QR out-of-band key
            Network.framework TLS PSK / TCP, 10 Hz NDJSON
                         |
                   native tvOS
              validate + freshness + pause latch
                         |
            PlaybackEngine -> virtual distance / m/s
               |                          |
       procedural SceneKit loop    AVPlayer flat / 360 sphere
```

## Boundaries

`StrideCore` is a dependency-free Swift package. It does not import CoreMotion, Network, SceneKit, UIKit, SwiftUI, or AVFoundation. Timestamps are injected into the detector and engine so tests run deterministically on Linux and macOS.

`LocalLink` owns the network lifecycle. Its callbacks and all native model mutations are scheduled on the main queue. Each channel has independent framing, handshake deadline, close-once guard, inbound rate limit, and bounded outbound coalescing. Closing, rotating, or losing the active source resets the playback session gate and stops velocity.

`MotionController` converts Core Motion samples to estimates. It does not treat HealthKit's cumulative step count as an immediate control signal. Sensor data gaps send stopped state; the source must stay foreground. Detector counts remain monotonic across source restarts within the same connection session.

`PlaybackEngine` maps cadence to a virtual speed with a configurable step length (default 0.65 m). Speed ramps up over 0.25 seconds; explicit stop, disconnection, and manual pause do not ramp down slowly. Receiver timeout is 1.2 seconds. Integration time is capped at 0.1 seconds and a tick gap over 0.5 seconds does not advance distance. A resumed TV pause requires a fresh source frame.

`Route` is a local-coordinate polyline, not a routing service. The built-in loop is an original approximately 503 m procedural route. GPX projection, elevation, route selection, street imagery retrieval, and persistent sessions are not implemented.

## Future adapters

Do not silently substitute simulated activity when a Watch, an API key, an image, or a sensor is unavailable. Keep unsupported capabilities visibly disabled.

Apple Watch needs its own step heuristics, workout lifecycle, authorization, reconnection, and battery tests. `WatchConnectivity` integration and whether a foreground iPhone bridge is acceptable must be verified separately. This repository contains no fake Watch target.

Street-view providers must expose explicit license, attribution, image sequence, route distance, errors, and cache policy. A thumbnail sequence is not a continuous 360-degree video. A provider integration must not turn a website's public visibility into permission to scrape or redistribute its content.

SceneKit is isolated to `Apps/TV`. A future RealityKit renderer can consume the same route pose and playback state while selecting a suitable minimum OS version. The MVP's use of a legacy renderer is not a claim that newer Apple APIs are unavailable.

## Primary API references

- Core Motion: https://developer.apple.com/documentation/coremotion/cmmotionmanager
- Network peer-to-peer sample: https://developer.apple.com/documentation/network/building-a-custom-peer-to-peer-protocol
- NWListener: https://developer.apple.com/documentation/network/nwlistener
- TLS PSK options: https://developer.apple.com/documentation/security/sec_protocol_options_add_pre_shared_key(_:_:_:)
- Local network privacy: https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription
- AVPlayer: https://developer.apple.com/documentation/avfoundation/avplayer
- WatchConnectivity: https://developer.apple.com/documentation/watchconnectivity
- XcodeGen: https://github.com/yonaskolb/XcodeGen

These references describe framework APIs; actual build logs and integration tests, not the links themselves, are the verification evidence for this app.
