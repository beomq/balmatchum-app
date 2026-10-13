import Flutter
import Foundation
import PhoneWatchBridge
import WatchConnectivity
import WatchSyncContract

final class PhoneWatchBridgePlugin: NSObject, FlutterStreamHandler, WCSessionDelegate {
    private let queue = DispatchQueue(label: "com.beomq.balmatchum.watch.native")
    private var store: PhoneStore?
    private var session: WCSession?
    private let steps = DailyStepsReader()
    private var eventSink: FlutterEventSink?
    private var methods: FlutterMethodChannel?
    private var events: FlutterEventChannel?
    private var completed: [RecordIdentity: Acknowledgement.Stage] = [:]

    override init() {
        super.init()
        queue.sync {
            do {
                let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("PhoneWatchBridge", isDirectory: true)
                // No path component is derived from an incoming account/record identifier.
                self.store = try PhoneStore(persistence: FilePhonePersistence(
                    url: directory.appendingPathComponent("state-v1.json")))
            } catch { report(error) }
        }
        if WCSession.isSupported() {
            session = .default
            session?.delegate = self
            session?.activate()
        }
    }

    func register(messenger: FlutterBinaryMessenger) {
        methods = FlutterMethodChannel(name: "com.beomq.balmatchum/watch", binaryMessenger: messenger)
        events = FlutterEventChannel(name: "com.beomq.balmatchum/watch/events", binaryMessenger: messenger)
        methods?.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(FlutterError(code: "nativeUnavailable", message: nil, details: nil)); return }
            if call.method == "requestDailySteps" {
                self.queue.async {
                    // Permission UI/query can outlive logout or account switching.
                    // Compare the serialized boundary again before releasing its result.
                    let boundary = try? self.store?.contextEnvelope()["boundaryRevision"] as? Int
                    DispatchQueue.main.async {
                        self.steps.request { value in
                            self.queue.async {
                                let current = try? self.store?.contextEnvelope()["boundaryRevision"] as? Int
                                let response: [String: Any] = boundary != nil && boundary == current
                                    ? value : ["status": "error", "dailySteps": NSNull()]
                                DispatchQueue.main.async { result(response) }
                            }
                        }
                    }
                }
                return
            }
            self.queue.async {
                do {
                    guard let store = self.store else { throw PhoneBridgeError.unavailable }
                    var value: Any?
                    switch call.method {
                    case "activateContext":
                        guard let args = call.arguments as? [String: Any], let account = args["accountId"] as? String else {
                            throw PhoneBridgeError.invalidInput
                        }
                        let active = try store.activate(accountId: account)
                        value = ["contextId": active.contextId, "boundaryRevision": active.boundaryRevision,
                                 "latestDisplayRevision": active.latestDisplayRevision]
                        self.publishContext()
                        self.inboxChanged()
                    case "clearContext":
                        try store.clearContext()
                        self.publishContext()
                        self.inboxChanged()
                    case "publishDisplaySnapshot":
                        guard let json = call.arguments as? String else { throw PhoneBridgeError.invalidInput }
                        try store.publishDisplay(Data(json.utf8))
                        self.publishContext()
                    case "listPendingRecords":
                        value = try store.pendingRecords()
                    case "acknowledgeServerReceipt":
                        guard let args = call.arguments as? [String: Any],
                              let context = args["contextId"] as? String,
                              let client = args["clientRecordId"] as? String,
                              let record = args["recordId"] as? String,
                              let time = args["persistedAt"] as? String,
                              PhoneTransport.isVersionOne(args["schemaVersion"]) else { throw PhoneBridgeError.invalidInput }
                        let ack = try store.acknowledge(ServerReceipt(contextId: context, clientRecordId: client,
                            recordId: record, persistedAt: time, schemaVersion: 1))
                        self.completed.removeValue(forKey: ack.identity)
                        self.flushAcknowledgements()
                        self.inboxChanged()
                    default:
                        DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
                        return
                    }
                    DispatchQueue.main.async { result(value) }
                } catch {
                    self.report(error)
                    DispatchQueue.main.async {
                        result(FlutterError(code: "watchBridgeFailure", message: String(describing: error), details: nil))
                    }
                }
            }
        }
        events?.setStreamHandler(self)
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        events("inboxChanged")
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    private func inboxChanged() {
        DispatchQueue.main.async { [weak self] in self?.eventSink?("inboxChanged") }
    }

    private func report(_ error: Error) {
        // No account IDs, route data, token, or raw request is logged.
        NSLog("PhoneWatchBridge: %@", String(describing: type(of: error)))
    }

    private func publishContext() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            guard let store else { throw PhoneBridgeError.unavailable }
            try session.updateApplicationContext(store.contextEnvelope())
        } catch { report(error) }
    }

    private func flushAcknowledgements() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            guard let store else { throw PhoneBridgeError.unavailable }
            let outstanding = session.outstandingUserInfoTransfers.compactMap {
                PhoneTransport.acknowledgement(in: $0.userInfo)
            }
            for ack in PhoneTransport.nextAcknowledgements(durable: try store.acknowledgements(),
                                                           outstanding: outstanding, completed: completed) {
                session.transferUserInfo(["transportVersion": 1, "kind": "ack", "ackJSON": ack.json])
            }
        } catch { report(error) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        queue.async {
            if let error { self.report(error); return }
            self.completed.removeAll()
            self.publishContext()
            self.flushAcknowledgements()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func sessionReachabilityDidChange(_ session: WCSession) {
        queue.async {
            guard session.isReachable else { return }
            self.completed.removeAll()
            self.publishContext()
            self.flushAcknowledgements()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        queue.async {
            do {
                let requestID = try PhoneTransport.contextRequestID(message)
                guard let store = self.store else { throw PhoneBridgeError.unavailable }
                replyHandler(try store.contextEnvelope(requestId: requestID))
            } catch {
                self.report(error)
                // Not a contextReply: never establish trust on unavailable durable state.
                replyHandler(["transportVersion": 1, "kind": "contextUnavailable"])
            }
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WC deletes this URL after callback return. Validation + atomic storage must
        // finish here, not in an asynchronously scheduled block holding only the URL.
        queue.sync {
            do {
                guard let store else { throw PhoneBridgeError.unavailable }
                let bytes = try Data(contentsOf: file.fileURL)
                if let ack = try PhoneTransport.receive(bytes, metadata: file.metadata, into: store) {
                    completed.removeValue(forKey: ack.identity)
                    flushAcknowledgements()
                    inboxChanged()
                }
            } catch { report(error) }
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        queue.async {
            guard let ack = PhoneTransport.acknowledgement(in: userInfoTransfer.userInfo) else { return }
            if let error {
                self.report(error)
                // No tight retry loop; a duplicate, activation, or reachability event retries.
                return
            }
            self.completed[RecordIdentity(contextId: ack.contextId, recordId: ack.recordId)] = ack.stage
            self.flushAcknowledgements()
        }
    }
}
