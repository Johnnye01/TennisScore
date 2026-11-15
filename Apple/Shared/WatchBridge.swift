import Foundation
import WatchConnectivity

/// Durable operation delivery plus an immediate channel while both apps are reachable.
/// This transports data only; scoring never waits for a companion or the network.
final class WatchBridge: NSObject, WCSessionDelegate {
    var onReceive: ((Data) -> Void)?
    var onStatus: ((String) -> Void)?
    var onReady: (() -> Void)?
    private var pending: [Data] = []
    private var session: WCSession?

    func start() {
        guard WCSession.isSupported() else {
            onStatus?("当前设备不支持手表同步")
            return
        }
        let connection = WCSession.default
        session = connection
        connection.delegate = self
        connection.activate()
    }

    func send(_ data: Data) {
        guard let session, session.activationState == .activated else {
            pending.append(data)
            return
        }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        if data.count < 45_000 {
            // Unique record IDs make reception on both channels idempotent.
            session.transferUserInfo(["payload": data])
            if session.isReachable {
                session.sendMessageData(data, replyHandler: nil, errorHandler: { _ in })
            }
        } else {
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CourtCallSync", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
                try data.write(to: file, options: .atomic)
                session.transferFile(file, metadata: ["courtcall": true])
            } catch {
                onStatus?("已本地保存；同步文件暂时无法发送")
            }
        }
    }

    private func status() -> String {
        guard let session else { return "本地模式" }
        #if os(iOS)
        if !session.isPaired { return "未配对 Apple Watch · 可在手机记分" }
        if !session.isWatchAppInstalled { return "请在手表安装 CourtCall" }
        return session.isReachable ? "手表已连接" : "本地已保存 · 连接后同步"
        #else
        return session.isReachable ? "手机已连接" : "本地已保存 · 连接后同步"
        #endif
    }

    private func receive(_ data: Data) {
        DispatchQueue.main.async { [weak self] in self?.onReceive?(data) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onStatus?(error == nil ? self.status() : "同步暂不可用 · 可继续本地记分")
            if activationState == .activated {
                let queued = self.pending
                self.pending.removeAll()
                queued.forEach(self.send)
                self.onReady?()
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onStatus?(self.status())
            if session.isReachable { self.onReady?() }
        }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) { receive(messageData) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo["payload"] as? Data { receive(data) }
    }
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WCSession removes its inbound temporary file when this delegate returns.
        if let data = try? Data(contentsOf: file.fileURL) { receive(data) }
    }
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onStatus?(self.status())
            if session.isWatchAppInstalled { self.onReady?() }
        }
    }
    #endif
}

enum SyncPayload: Codable {
    case request
    case document(MatchDocument)
}
