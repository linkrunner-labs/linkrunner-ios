# Changelog

All notable changes to the LinkRunner iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.7.1] - 2025-02-02

### Added
- **GA Session ID Support**: Added `gaSessionId` field to `UserData` model
  - Allows tracking Google Analytics session ID alongside `gaAppInstanceId`

## [3.7.0] - 2025-12-16

### Added
- **AdServices Attribution Token**: Added support for Apple's AdServices attribution token
  - Automatically retrieves attribution token using `AAAttribution.attributionToken()` during SDK initialization
  - Attribution token is included in init requests for improved ad attribution tracking
  - Gracefully handles cases where AdServices framework is unavailable
  - Available on iOS 14.3+

## [3.3.0] - 2025-09-26

### Added
- **Retry Mechanism**: Implemented exponential backoff retry mechanism for API calls
  - Retries up to 4 times for HTTP server errors and network failures
  - Exponential backoff delays: 2s, 4s, 8s, 16s between retry attempts

### Changed
- **Enhanced Error Handling**: Non-blocking error handling for all public methods
  - All public methods now log errors instead of throwing them
  - Prevents SDK errors from crashing the application

- **Backward Compatibility**: 
  - Returns empty `LRAttributionDataResponse` object instead of `nil` on errors to maintain backward compatibility

### Removed
- **Trigger Deeplink**: Removed the deprecated trigger deeplink method


---

*This changelog follows the [Keep a Changelog](https://keepachangelog.com/) format.*
