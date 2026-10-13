# Phone native bridge integration

Runner source membership (app owner): `Runner/PhoneWatchBridgePlugin.swift`,
`Runner/DailyStepsReader.swift`; existing `Runner/AppDelegate.swift` initializes
the bridge before WatchConnectivity activation and registers both Flutter channels.
Link local product `PhoneWatchBridge` from `ios/PhoneWatchBridge` to Runner.
Its relative dependency is `../Watch/SyncContract` product `WatchSyncContract`.
Runner also imports that product; preserve the existing Watch target product link.

## Frozen channel API

Method channel `com.beomq.balmatchum/watch`; event channel
`com.beomq.balmatchum/watch/events` emits the string `inboxChanged`.
Events are hints; enumeration is authoritative without a listener.

| Method | Input | Result |
| --- | --- | --- |
| `activateContext` | `{accountId: String}` | `{contextId: String, boundaryRevision: Int, latestDisplayRevision: Int}` |
| `clearContext` | none | null |
| `publishDisplaySnapshot` | String JSON v1 display | null |
| `listPendingRecords` | none | List of String JSON v1 GPS envelopes, active context only |
| `acknowledgeServerReceipt` | `{contextId: String, clientRecordId: String, recordId: String, persistedAt: String, schemaVersion: 1}` | null |
| `requestDailySteps` | none | `{status: String, dailySteps: Map or null}` |

The activation result defaults to display revision `0` (caller next revision `1`);
the internal unpublished high-water remains `-1`, permitting v1 revision zero.
Receipt recordId is the server UUID,
clientRecordId is the original Watch record UUID, and persistedAt is UTC ISO8601.
Only the actual authenticated Dart adapter can activate an account, and only the
uploader with a matching real generated-client receipt can acknowledge it.
Native validation is not independent proof of a server transaction.

Health statuses are `available`, `capabilityUnavailable`, `unavailable`, `empty`,
and `error`. Only `available` carries steps; a real integrated zero remains zero.
No empty/denied result becomes zero. The query is cumulativeSum from Seoul midnight
to query initiation. A boundary change during permission/query completion discards
the result. `NSHealthShareUsageDescription` must exist before authorization.

**Capability is unavailable by default.** iOS SDK does not expose macOS
`SecTaskCreateFromSelf`/`SecTaskCopyValueForEntitlement`. No private-symbol workaround
is used. The app owner may set the Info.plist Boolean
`BalmatchumHealthKitCapabilityVerified` to true only in a configuration whose
actual signed `com.apple.developer.healthkit` entitlement and provisioning profile
have been verified. The flag does not inspect or grant an entitlement. Current
distribution entitlement is absent and development profile is not installed per
the lead's read-only inspection; leave the flag absent/false. Never enable it just
to show a permission dialog. Parent owns plist, entitlements and profiles.

## Persistence and failures

One atomic `Application Support/PhoneWatchBridge/state-v1.json` replacement stores
installation UUID, account map, active boundary, display high-water, complete inbox
payloads with their receipts, and unknown-context quarantine. A receipt's presence
is the durable serverSaved stage; there is no separately writable ACK flag.
File names never contain input IDs. This increment retains every original record.

All native store operations/publication are serialized; the store itself also
locks its public operations. A write failure poisons the instance, preventing
publication or a stale handshake. Restart reloads the last complete state and
durably deactivates any active context before WC activation. Corruption or failed
cold deactivation cannot silently reset installation ordering. Known old contexts
remain queued; unknown contexts remain quarantined with no ACK and no adoption.
Semantic duplicates re-emit the confirmed stage without another record write.

ACK scheduling allows at most 16 concurrent record identities; an outstanding
phoneReceived completes before the same record's serverSaved is scheduled.
Successful WC transfer is only transport completion, not another persistence stage.
Failed transfers retry on duplicate/reconnect/reactivation, not a tight loop.

## Verification and troubleshooting

Run `cd ios/PhoneWatchBridge && swift test`. Tests inject failed inbox, receipt,
display, logout, activation and cold-launch writes, and exercise cold restart,
semantic duplicates/conflicts, unknown quarantine, late receipt isolation, exact
metadata, handshake shape and bounded scheduling without sleeps.

First inspect channel error and native-store availability, then account boundary,
then receipt client identity and outstanding WC transfers. Do not delete the store
to repair a problem: doing so destroys the installation ordering and account map.
Whole-file replacement deliberately favors coherent state over scaling; large
inboxes may require a transactional database in a separately reviewed increment.

Simulator transferFile is unsupported; deterministic callback tests are not live
transport proof. Physical connectivity and HealthKit measurements remain NOT RUN.
Parent owns Xcode membership and integrated app build/UI checks.

### Local evidence (2026-10-13)

- `cd ios/PhoneWatchBridge && swift test`: exit 0, 13 Swift Testing tests passed.
  The cross-store test reopens actual temporary phone and Watch files after a
  lost ACK. Its server receipt is a fixture, not live server evidence.
- iPhoneSimulator 27.0 SDK, arm64 iOS 13 target: emitted `WatchSyncContract` and
  `PhoneWatchBridge` modules, then `xcrun swiftc -typecheck` on
  `DailyStepsReader.swift`, `PhoneWatchBridgePlugin.swift`, `AppDelegate.swift`
  with Flutter 3.47.5 simulator framework and `GeneratedPluginRegistrant.h`:
  exit 0, no warnings. This is native typechecking, not an integrated app build.
- `git diff --check`: exit 0.
- SourceKit in this standalone workspace cannot resolve the Swift package/Flutter
  module search paths (`No such module WatchSyncContract`, `Flutter`, `Testing`);
  the actual compiler invocations above resolve them and pass.
- No physical transport, HealthKit authorization/read, provisioning change,
  commit, push, or upload performed.

### Integrated simulator build

On local Xcode 27, Flutter's direct `build ios --simulator` passes a global SDK
that resolves the shared package for only one target platform. Use the same
source package for both targets and select the destination instead:

```sh
fvm flutter build ios --config-only --simulator --debug --flavor dev
cd ios
xcodebuild -workspace Runner.xcworkspace -scheme dev \
  -configuration Debug-dev -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/balmatchum-simulator \
  BUILD_DIR="$PWD/../build/ios" CODE_SIGNING_ALLOWED=NO build
```

This path and the unsigned Prod device Release build passed on the integrated
tree. Apple CI also uses destination-only builds, on hosted Xcode 26.3. Do not
add a global SDK override or duplicate the shared Swift source to work around it.
The simulator proves compilation/rendering, not physical transfer or HealthKit.
