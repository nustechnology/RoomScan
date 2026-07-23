# iOS Security Checklist

Use this checklist when reviewing security-sensitive changes in a native iOS application written in Swift.

Focus on practical vulnerabilities with realistic impact. Do not report purely theoretical issues without a plausible attack path.

---

## Authentication & Session

* Store access tokens, refresh tokens, and session credentials in Keychain.
* Never store authentication credentials in `UserDefaults`.
* Handle token expiration correctly.
* Prevent concurrent token-refresh requests from creating race conditions.
* Clear authentication state correctly on logout.
* Do not trust stale cached authentication state after app launch.
* Handle revoked or invalid sessions safely.
* Validate Sign in with Apple / OAuth results through the backend when applicable.
* Never treat client-side authentication state as backend authorization.

## Authorization

* Sensitive permissions must be enforced by the backend.
* Do not rely on hidden/disabled UI for access control.
* Do not trust user IDs, roles, subscription state, or permissions supplied only by the client.
* Premium or restricted functionality should be verified server-side when appropriate.
* Ensure users cannot access another user's resources by changing request parameters.

## Keychain & Local Storage

Store sensitive information in Keychain:

* Access tokens
* Refresh tokens
* Session credentials
* Private keys
* Sensitive account information when persistence is required

Avoid sensitive information in:

* `UserDefaults`
* `@AppStorage`
* plain files
* plist files
* unencrypted local databases
* application caches

Remember that Keychain items may survive application uninstall depending on their configuration and platform behavior.

Review Keychain accessibility settings such as:

```swift
kSecAttrAccessibleWhenUnlocked
kSecAttrAccessibleAfterFirstUnlock
kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

Choose the least permissive option compatible with application requirements.

## Secrets & Configuration

Assume anything shipped inside the application bundle can be extracted.

Never embed true secrets such as:

* Backend private keys
* Service account credentials
* Database passwords
* Signing secrets
* Private API credentials

Review:

* Swift constants
* `.xcconfig`
* `Info.plist`
* configuration files
* bundled JSON/plist files
* build scripts
* CI configuration

Public client API keys should be restricted by the provider whenever possible.

Do not treat obfuscation as secure secret storage.

## Network Security

* Production traffic should use HTTPS.
* Respect App Transport Security (ATS).
* Do not disable TLS validation.
* Do not accept arbitrary certificates.
* Development networking exceptions must not accidentally reach production.
* Use secure WebSocket connections (`wss://`) when applicable.
* Sensitive information should not be included unnecessarily in URL query parameters.

Flag insecure implementations such as:

```swift
urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: ...
)
```

when they blindly trust the server certificate.

Certificate pinning should only be recommended when justified by the application's threat model.

## API Security

Check that API requests:

* attach authentication correctly
* handle `401` and `403` correctly
* validate response data
* use reasonable timeouts
* do not expose tokens in URLs
* do not accidentally retry non-idempotent requests
* do not leak sensitive request or response data into logs

Authorization must ultimately be enforced by the backend.

## Logging & Analytics

Never log:

* passwords
* access tokens
* refresh tokens
* authorization headers
* private keys
* payment information
* sensitive personal information

Review:

```swift
print(...)
debugPrint(...)
NSLog(...)
Logger(...)
os_log(...)
```

Debug logging should not expose sensitive information in production.

Also review data sent to:

* analytics
* crash reporting
* monitoring services

Avoid attaching entire API request/response payloads when they may contain private data.

## Deep Links & Universal Links

Treat incoming URLs as untrusted input.

Validate:

* scheme
* host
* path
* parameters
* expected navigation destination

Do not execute sensitive actions solely because a deep link requests them.

Universal Links should use properly configured Associated Domains.

Prevent malicious URLs from navigating users into unauthorized application states.

## WebView Security

When using `WKWebView`:

* Load only trusted content when possible.
* Validate external URLs.
* Avoid exposing unnecessary JavaScript bridges.
* Treat messages from `WKScriptMessageHandler` as untrusted input.
* Avoid injecting sensitive information into JavaScript.
* Do not disable security protections without strong justification.

Review navigation delegates carefully.

## Sensitive UI & Clipboard

Avoid copying sensitive information to the system clipboard unless required.

Remember that clipboard contents may be accessible outside the application.

For highly sensitive screens, consider whether screenshots or screen recording require protection.

Do not apply screenshot blocking indiscriminately.

## File Security

Sensitive files should use appropriate iOS Data Protection.

Review protection classes such as:

```swift
FileProtectionType.complete
FileProtectionType.completeUnlessOpen
FileProtectionType.completeUntilFirstUserAuthentication
```

Avoid storing sensitive files in publicly accessible or unnecessarily persistent locations.

Temporary sensitive files should be removed when no longer needed.

## Privacy & Permissions

Request only permissions required by application functionality.

Examples:

* Camera
* Microphone
* Photos
* Location
* Contacts
* Bluetooth

Ensure `Info.plist` usage descriptions clearly explain why the permission is needed.

Do not request permissions significantly earlier than necessary.

Handle:

```swift
.notDetermined
.denied
.restricted
.authorized
```

appropriately.

Check privacy-sensitive APIs against Apple's current privacy manifest requirements when relevant.

## Biometrics

When using LocalAuthentication:

* Handle unavailable biometrics.
* Handle enrollment changes.
* Handle failed authentication.
* Provide appropriate fallback behavior.
* Do not treat successful Face ID / Touch ID as server authorization.

Prefer:

```swift
LAContext()
```

and evaluate the appropriate policy for the feature.

## Notifications

Do not expose sensitive information unnecessarily in push notification payloads or notification previews.

Do not trust notification payloads as authorization.

Validate identifiers before navigating or requesting protected resources.

## Third-Party Dependencies

Review dependencies for:

* known security issues
* unnecessary permissions
* abandoned packages
* unexpected tracking
* unsafe binary frameworks

Prefer maintained dependencies and official SDKs.

Review changes to:

* `Package.swift`
* Swift Package Manager dependencies
* CocoaPods dependencies
* manually embedded frameworks

## Production Configuration

Ensure production builds do not contain:

* development API endpoints
* debug menus
* authentication bypasses
* mock users
* test credentials
* certificate-validation bypasses
* excessive logging
* internal-only feature flags accidentally enabled

Pay particular attention to code guarded by:

```swift
#if DEBUG
```

and verify the intended behavior outside DEBUG builds.

## Reporting Guidance

Use the project's canonical finding taxonomy defined by the review skill and `AGENTS.md`.

Do not introduce an additional severity scale.

Security findings should be classified using the existing categories such as:

- `Required`
- `Critical`
- `Optional`
- `Nit`
- `FYI`

Only report findings with a realistic security impact or plausible attack path.

Do not report speculative or purely theoretical security concerns.
