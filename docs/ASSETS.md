# Content and asset policy

## Included now

`Apps/TV/SceneRenderer.swift` creates a loop trail, terrain plane, lighting, and low-poly trees from original geometry. It requires no texture downloads, API key, account, remote tile service, or commercial asset. This procedural content is covered by the repository's MIT license.

No real location is represented. No downloaded 360-degree film, Google Street View image, Mapillary image, OSM extract, logo, or third-party audio is bundled.

## User-supplied video

The MVP accepts explicit HTTPS MP4 / HLS media URLs. Supply a source you own or have permission to use in this application. Some signed URLs expire; some codecs, streaming formats, or access policies will fail. The application reports a failure rather than replacing it with an unlicensed source.

The panoramic renderer expects monoscopic 2:1 equirectangular video. It does not convert dual-fisheye or stereo top/bottom footage. A camera must have moved along a route during filming for playback to look like forward movement; a stationary 360-degree clip only changes time and viewing direction.

The app doesn't provide attribution metadata controls yet. Therefore, don't distribute a build that loads attribution-required content until a compliant attribution UI and license record have been added. Private testing is not a blanket exception to copyright terms.

## Future route packs

Before including any third-party asset, record:

- canonical source, creator, exact license version and evidence;
- redistribution, commercial-use, modification and attribution requirements;
- checksum, projection, codec, dimensions, duration and recording-speed/distance mapping;
- privacy/release constraints and any provider-specific API/cache conditions.

Public access is not an open license. CC BY-SA is not CC0, and share-alike obligations do not disappear when an asset is converted. A provider's API access rules and an image's license are separate checks. Do not bulk-download Google or Mapillary content by assuming a generic license grants unrestricted API access.

## Remote Walk

Remote Walk was discussed as a product reference for mapping steps to route progress. No Remote Walk source code, private API, asset catalog, account, or license has been supplied or integrated. This project implements its own route and motion logic.
