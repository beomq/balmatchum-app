import Foundation
import WatchConnectivity
import WatchSyncContract

@MainActor
final class WatchConnectivityStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: DisplaySnapshot?
    @Published private(set) var message = "iPhone 상태 확인 중"
    @Published private(set) var storageError = false
    private var boundary: WatchBoundary?
    private var outbox: DurableOutbox?
    private var directory: URL?
    private var handshakeRequestId: String?
    private var boundaryChangedDuringHandshake = false
    private let session: WCSession

    override init() {
        session = .default
        super.init()
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true).appendingPathComponent("WatchSync", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            directory = root
            boundary = try WatchBoundary(file: root.appendingPathComponent("boundary.json"))
            outbox = try DurableOutbox(file: root.appendingPathComponent("outbox.json"))
            snapshot = boundary?.snapshot
        } catch { storageError = true }
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    /// Called by a future real GPS producer only; no fabricated production records.
    func enqueue(_ data: Data) throws {
        guard let outbox else { throw OutboxError.invalidStore }
        try outbox.enqueue(data)
        resend()
    }

    private func refresh() {
        snapshot = boundary?.snapshot
        message = boundary?.confirmed == true
            ? (session.isReachable ? "iPhone과 연결됨" : "오프라인 · 마지막 정보")
            : "iPhone 상태 확인 중 · 이전 정보일 수 있어요"
    }

    private func handshake() {
        guard !storageError, handshakeRequestId == nil, session.activationState == .activated,
              session.isReachable, let boundary else { refresh(); return }
        let request = boundary.request()
        let requestId = request["requestId"] as! String
        handshakeRequestId = requestId
        session.sendMessage(request, replyHandler: { reply in
            // Extract property-list bytes before crossing the main-actor boundary.
            let bytes = try? PropertyListSerialization.data(fromPropertyList: reply, format: .binary, options: 0)
            Task { @MainActor in
                guard self.handshakeRequestId == requestId else { return }
                self.handshakeRequestId = nil
                do {
                    guard let bytes, let envelope = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any] else { throw BoundaryError.invalidEnvelope }
                    try self.boundary?.receive(envelope, reply: true)
                    self.refresh()
                    self.resend()
                    // A newer boundary can arrive while this request is in flight.
                    // Its callback could not start another handshake while pending.
                    if self.boundaryChangedDuringHandshake {
                        self.boundaryChangedDuringHandshake = false
                        self.handshake()
                    }
                } catch {
                    self.snapshot = self.boundary?.snapshot
                    self.message = "iPhone 상태 응답을 확인할 수 없어요"
                }
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                guard self.handshakeRequestId == requestId else { return }
                self.handshakeRequestId = nil
                self.refresh()
                if self.boundaryChangedDuringHandshake {
                    self.boundaryChangedDuringHandshake = false
                    self.handshake()
                }
            }
        })
    }

    private func resend() {
        guard !storageError, session.activationState == .activated,
              let context = boundary?.sendContext, let outbox, let directory else { return }
        // phoneReceived is durable phone custody. The phone replays its ACKs
        // on reconnect; don't repeatedly send that GPS payload while it uploads.
        for entry in outbox.pending(contextId: context).filter({ $0.stage == .transferQueued }) {
            let record = entry.record
            guard !session.outstandingFileTransfers.contains(where: {
                $0.file.metadata?["contextId"] as? String == context && $0.file.metadata?["recordId"] as? String == record.recordId
            }) else { continue }
            do {
                let file = directory.appendingPathComponent("transfer-\(UUID().uuidString).json")
                try JSONEncoder().encode(record).write(to: file, options: .atomic)
                session.transferFile(file, metadata: ["transportVersion": 1, "kind": "gpsRecord", "contextId": context, "recordId": record.recordId])
            } catch { storageError = true }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.boundary?.reconcile()
            self.handshakeRequestId = nil
            self.boundaryChangedDuringHandshake = false
            if let directory = self.directory, activationState == .activated {
                do {
                    let outstanding = Set(self.session.outstandingFileTransfers.map { $0.file.fileURL.standardizedFileURL })
                    for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    where url.lastPathComponent.hasPrefix("transfer-") && url.pathExtension == "json" && !outstanding.contains(url.standardizedFileURL) {
                        // These are only this adapter's abandoned transport copies.
                        // The authoritative GPS payload remains in outbox.json.
                        try FileManager.default.removeItem(at: url)
                    }
                } catch { self.message = "임시 전송 파일 정리를 완료하지 못했어요" }
            }
            if !self.session.receivedApplicationContext.isEmpty {
                do { try self.boundary?.receive(self.session.receivedApplicationContext, reply: false) }
                catch { self.message = "이전 동기화 정보를 확인할 수 없어요" }
            }
            self.handshake()
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.handshake(); self.refresh() }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let bytes = try? PropertyListSerialization.data(fromPropertyList: applicationContext, format: .binary, options: 0)
        Task { @MainActor in
            do {
                guard let bytes, let envelope = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any] else { throw BoundaryError.invalidEnvelope }
                try self.boundary?.receive(envelope, reply: false)
                self.refresh()
                if self.handshakeRequestId != nil { self.boundaryChangedDuringHandshake = true }
                self.handshake()
            } catch {
                self.snapshot = self.boundary?.snapshot
                self.message = "동기화 정보가 올바르지 않아요"
            }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard userInfo["transportVersion"] as? Int == 1, userInfo["kind"] as? String == "ack",
              let data = userInfo["ackJSON"] as? Data else { return }
        // Invalid transport data is not evidence of a broken disk. A valid ACK
        // that fails durable storage below still stops transmission.
        do { _ = try Acknowledgement.decode(data) }
        catch {
            Task { @MainActor in self.message = "저장 확인 응답이 올바르지 않아요" }
            return
        }
        Task { @MainActor in
            do { try self.outbox?.receive(data) }
            catch { self.storageError = true }
        }
    }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        Task { @MainActor in
            // The authoritative outbox payload remains; this is only the transport copy.
            try? FileManager.default.removeItem(at: url)
            if error != nil { self.message = "전송 보류 · 다시 연결되면 재시도해요" }
        }
    }
}
