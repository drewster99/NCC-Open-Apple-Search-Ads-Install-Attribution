# Changelog

## 1.2.0

### Fixed
- `error` is now set when the token or attribution record can't be fetched. It was never assigned before.
- A 404 ("not available yet") is retried as Apple recommends: 3 attempts, 5 seconds apart. Previously the
  first 404 gave up, so attribution was often missed on the first launch after install.
- A non-HTTP response throws `responseIsNotHTTPURLResponse` instead of crashing.
- A 200 response whose body is malformed or lacks `attribution` throws instead of being treated as
  "not attributed".
- `AAAttribution.attributionToken()` runs on its own dispatch queue instead of blocking a Swift
  Concurrency thread.
- The attribution token and response bodies are logged as private.

### Added
- `AttributionPayload.claimType`, `impressionDate` and `supplyPlacement`, from Apple's current payload.
  Payloads saved by earlier versions still load, with these as `nil`.
- `asAnalyticsDictionary` includes `ASAClaimType`, `ASAImpressionDate` and `ASASupplyPlacement` when present.
- Tests, README, and `.spi.yml` for Swift Package Index documentation.

### Changed
- The license file is now `LICENSE` so GitHub and Swift Package Index detect it.

## 1.1

- Swift 6 strict-concurrency fixes (main-actor isolation); Swift 6.1 tools.

## 1.0

- Initial release.
