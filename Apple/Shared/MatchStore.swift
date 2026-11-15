import Foundation
import Combine
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

@MainActor
final class MatchStore: ObservableObject {
    static let shared = MatchStore()

    @Published private(set) var activeDocument: MatchDocument?
    @Published private(set) var snapshot: MatchSnapshot?
    @Published private(set) var documents: [MatchDocument] = []
    @Published var preferences: AppPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) {
                UserDefaults.standard.set(data, forKey: "courtcall.preferences.v1")
            }
            if !preferences.speechEnabled { SpeechService.shared.stop() }
        }
    }
    @Published private(set) var isPaused = false
    @Published private(set) var connectionStatus = "本地已保存 · 正在连接"
    @Published var lastError: String?
    @Published private(set) var activeReminder: MatchReminder?

    var history: [MatchDocument] { documents }
    private var activeID: UUID?
    private let deviceID: String
    private let storageURL: URL
    private let bridge = WatchBridge()
    private var lastFeedbackText = ""

    private init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "courtcall.deviceID") {
            deviceID = saved
        } else {
            let newID = UUID().uuidString
            deviceID = newID
            defaults.set(newID, forKey: "courtcall.deviceID")
        }
        if let data = defaults.data(forKey: "courtcall.preferences.v1"),
           let saved = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            preferences = saved
        } else { preferences = AppPreferences() }

        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = base.appendingPathComponent("CourtCall", isDirectory: true).appendingPathComponent("matches-v1.json")
        if let savedID = defaults.string(forKey: "courtcall.activeID") { activeID = UUID(uuidString: savedID) }
        do {
            if FileManager.default.fileExists(atPath: storageURL.path) {
                documents = try MatchArchive.decode(Data(contentsOf: storageURL)).documents.sorted { $0.updatedAt > $1.updatedAt }
            }
        } catch { lastError = "无法读取比赛记录。请保留原文件并尝试导入备份：\(error.localizedDescription)" }
        refresh()
        bridge.onReceive = { [weak self] data in self?.receive(data) }
        bridge.onStatus = { [weak self] value in self?.connectionStatus = value }
        bridge.onReady = { [weak self] in self?.requestSync() }
        SpeechService.shared.onError = { [weak self] message in self?.lastError = message }
        CourtCallShortcuts.updateAppShortcutParameters()
        bridge.start()
    }

    func start(configuration: MatchConfiguration) throws {
        guard configuration.validationIssues.isEmpty else {
            throw MatchEngineError.invalidConfiguration(configuration.validationIssues)
        }
        let document = MatchDocument(configuration: configuration)
        let previousDocuments = documents
        let previousActiveID = activeID
        documents.insert(document, at: 0)
        activeID = document.id
        do { try persist() }
        catch {
            documents = previousDocuments
            activeID = previousActiveID
            throw error
        }
        activeReminder = nil
        refresh()
        send(document)
        if preferences.speechEnabled { SpeechService.shared.speak(document.snapshot.lastAnnouncement) }
    }

    func score(_ side: Side) { handle { try award(side, speak: true) } }
    func chooseReceiver(_ court: ServiceCourt) { handle { try perform(.receiverChoice(court), speak: true) } }
    func changeLineup(_ lineup: SetLineup) { handle { try perform(.lineup(lineup), speak: true) } }
    func undo() { handle { try undoPoint(speak: true) } }

    func togglePause() {
        handle {
            guard var document = activeDocument else { throw AppActionError.noMatch }
            guard !document.isAbandoned, document.snapshot.winner == nil else { return }
            let record = try document.append(.setPaused(!isPaused), deviceID: deviceID)
            try replace(document)
            activeReminder = nil
            SpeechService.shared.stop()
            send(document.containingOnly([record]))
        }
    }

    func endMatch() {
        handle {
            if var document = activeDocument, document.snapshot.winner == nil, !document.isAbandoned {
                let record = try document.append(.end, deviceID: deviceID)
                try replace(document)
                send(document.containingOnly([record]))
            }
            activeID = nil
            activeReminder = nil
            SpeechService.shared.stop()
            try persist()
            refresh()
        }
    }

    func resume(_ document: MatchDocument) {
        activeID = document.id
        activeReminder = nil
        handle { try persist(); refresh() }
    }

    func repeatScore() {
        guard let document = activeDocument else { lastError = AppActionError.noMatch.localizedDescription; return }
        // Explicitly requesting a read-out works even when automatic speech is off.
        SpeechService.shared.speak(currentAnnouncement(document))
    }
    func speakPreview(_ text: String) { SpeechService.shared.speak(text) }
    func dismissReminder() { activeReminder = nil }
    func clearError() { lastError = nil }

    func exportData() throws -> Data { try MatchArchive(documents: documents).encoded() }
    func importData(_ data: Data) throws {
        let archive = try MatchArchive.decode(data)
        var merged = documents
        for imported in archive.documents {
            if let index = merged.firstIndex(where: { $0.id == imported.id }) {
                try merged[index].merge(imported)
            } else { merged.append(imported) }
        }
        guard merged.count <= 500 else { throw DocumentError.recordLimit }
        let previousDocuments = documents
        documents = merged.sorted { $0.updatedAt > $1.updatedAt }
        do { try persist() }
        catch { documents = previousDocuments; throw error }
        refresh()
        archive.documents.forEach(send)
    }

    // Siri supplies its own spoken dialog, so these methods suppress local TTS.
    func performVoicePoint(_ side: Side) throws -> String {
        try checkVoice()
        try award(side, speak: false)
        return lastFeedbackText.isEmpty ? (snapshot?.lastAnnouncement ?? "Point recorded.") : lastFeedbackText
    }
    func performVoiceUndo() throws -> String {
        try checkVoice()
        try undoPoint(speak: false)
        guard let document = activeDocument else { throw AppActionError.noMatch }
        return "Correction. " + currentAnnouncement(document)
    }
    func performVoiceRead() throws -> String {
        try checkVoice()
        guard let document = activeDocument else { throw AppActionError.noMatch }
        return currentAnnouncement(document)
    }
    func performVoiceReceiver(_ court: ServiceCourt) throws -> String {
        try checkVoice()
        try perform(.receiverChoice(court), speak: false)
        return snapshot?.lastAnnouncement ?? "Receiver selected."
    }

    private func checkVoice() throws {
        guard preferences.voiceCommandsEnabled else { throw AppActionError.voiceDisabled }
    }
    private func award(_ side: Side, speak: Bool) throws { try perform(.point(side), speak: speak) }

    private func perform(_ action: MatchAction, speak: Bool) throws {
        guard var document = activeDocument else { throw AppActionError.noMatch }
        guard !document.isAbandoned else { throw AppActionError.ended }
        guard !document.isPaused else { throw AppActionError.paused }
        let before = document.state
        var engine = before.engine
        try engine.apply(action) // Validate before committing an operation.
        let record = try document.append(.score(action), deviceID: deviceID)
        try replace(document)
        send(document.containingOnly([record]))
        if case .point = action { feedback(snapshot: engine.snapshot, before: before.snapshot, at: record.date, speak: speak) }
        else if speak && preferences.speechEnabled { SpeechService.shared.speak(engine.snapshot.lastAnnouncement) }
    }

    private func undoPoint(speak: Bool) throws {
        guard var document = activeDocument else { throw AppActionError.noMatch }
        guard !document.isAbandoned else { throw AppActionError.ended }
        let record = try document.undoLastPoint(deviceID: deviceID)
        try replace(document)
        send(document.containingOnly([record]))
        activeReminder = nil
        haptic(success: false)
        if speak && preferences.speechEnabled {
            SpeechService.shared.speak("Correction. " + currentAnnouncement(document))
        }
    }

    private func feedback(snapshot: MatchSnapshot, before: MatchSnapshot, at date: Date, speak: Bool) {
        activeReminder = nil
        haptic(success: snapshot.alerts.contains { $0.kind == .matchComplete || ($0.kind == .changeEnds && preferences.changeoverRemindersEnabled) })
        let changesEnds = snapshot.alerts.contains { $0.kind == .changeEnds }
        let restSeconds = snapshot.alerts.compactMap(\.restSeconds).max()
        if snapshot.winner == nil {
            let showChange = changesEnds && preferences.changeoverRemindersEnabled
            let showHydration = restSeconds != nil && preferences.hydrationRemindersEnabled
            let showSet = snapshot.alerts.contains { $0.kind == .setBreak }
            if showChange || showHydration || showSet {
                var messages: [String] = []
                if showChange { messages.append("交换场地两端。") }
                if showHydration { messages.append("现在可以休息、补水。") }
                if restSeconds == nil && showChange { messages.append("这次换边不停留休息。") }
                activeReminder = MatchReminder(title: showSet ? "盘间休息" : (showChange ? "换边提醒" : "补水提醒"),
                                               message: messages.joined(),
                                               restUntil: restSeconds.map { date.addingTimeInterval(TimeInterval($0)) })
            }
        }
        var announcement = snapshot.lastAnnouncement
        if !preferences.includeNamesInSpeech {
            let prefix = before.server.spokenLabel + " serving. "
            if announcement.hasPrefix(prefix) { announcement.removeFirst(prefix.count) }
        }
        if !preferences.serveRemindersEnabled {
            for alert in snapshot.alerts where alert.kind == .changeServer {
                announcement = announcement.replacingOccurrences(of: " " + alert.message, with: "")
            }
        } else if snapshot.winner == nil && snapshot.alerts.contains(where: { $0.kind == .changeServer }) {
            let serverCall = snapshot.server.spokenLabel + " to serve."
            if !announcement.contains(serverCall) { announcement += " " + serverCall }
            announcement += " \(snapshot.serviceCourt == .deuce ? "Deuce" : "Ad") court."
            if documentKindIsDoubles { announcement += " \(snapshot.receiver.spokenLabel) receiving." }
        }
        if changesEnds && preferences.changeoverRemindersEnabled && snapshot.winner == nil { announcement += " Change ends." }
        if restSeconds != nil && preferences.hydrationRemindersEnabled && snapshot.winner == nil { announcement += " Time to hydrate." }
        lastFeedbackText = announcement
        if speak && preferences.speechEnabled { SpeechService.shared.speak(announcement) }
    }

    private var documentKindIsDoubles: Bool { activeDocument?.configuration.kind == .doubles }
    private func currentAnnouncement(_ document: MatchDocument) -> String {
        let engine = document.state.engine
        var text = engine.scoreAnnouncement(includeServerName: preferences.includeNamesInSpeech)
        if document.snapshot.winner == nil && preferences.serveRemindersEnabled {
            let next = document.snapshot
            text += " \(next.server.spokenLabel) to serve from the \(next.serviceCourt == .deuce ? "deuce" : "ad") court."
            if document.configuration.kind == .doubles { text += " \(next.receiver.spokenLabel) receiving." }
        }
        return text
    }

    private func haptic(success: Bool) {
        #if os(watchOS)
        WKInterfaceDevice.current().play(success ? .notification : .click)
        #else
        if success { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        #endif
    }

    private func replace(_ document: MatchDocument) throws {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { throw AppActionError.noMatch }
        let previousDocuments = documents
        documents[index] = document
        documents.sort { $0.updatedAt > $1.updatedAt }
        do { try persist() }
        catch { documents = previousDocuments; throw error }
        refresh()
    }
    private func refresh() {
        activeDocument = documents.first { $0.id == activeID }
        if let activeDocument {
            let value = activeDocument.state
            snapshot = value.snapshot
            isPaused = value.isPaused
            if !value.replayIssues.isEmpty { lastError = "同步后有操作顺序冲突，请核对比分并导出备份。" }
        } else { snapshot = nil; isPaused = false }
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: storageURL.path) {
            let backup = storageURL.deletingLastPathComponent().appendingPathComponent("matches-previous.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: storageURL, to: backup)
        }
        try MatchArchive(documents: documents).encoded().write(to: storageURL, options: .atomic)
        if let activeID { UserDefaults.standard.set(activeID.uuidString, forKey: "courtcall.activeID") }
        else { UserDefaults.standard.removeObject(forKey: "courtcall.activeID") }
    }
    private func handle(_ work: () throws -> Void) {
        do { try work() }
        catch { lastError = error.localizedDescription }
    }
    private func requestSync() {
        if let data = try? JSONEncoder().encode(SyncPayload.request) { bridge.send(data) }
    }
    private func send(_ document: MatchDocument) {
        if let data = try? JSONEncoder().encode(SyncPayload.document(document)) { bridge.send(data) }
    }
    private func receive(_ data: Data) {
        guard data.count <= 20_000_000 else { return }
        let previousDocuments = documents
        let previousActiveID = activeID
        do {
            switch try JSONDecoder().decode(SyncPayload.self, from: data) {
            case .request: documents.forEach(send)
            case let .document(incoming):
                guard incoming.configuration.validationIssues.isEmpty, incoming.records.count <= 20_000 else {
                    throw DocumentError.invalidArchive
                }
                if let index = documents.firstIndex(where: { $0.id == incoming.id }) {
                    var updated = documents[index]
                    try updated.merge(incoming)
                    if updated == documents[index] { return }
                    documents[index] = updated
                } else {
                    guard documents.count < 500 else { throw DocumentError.recordLimit }
                    // Normalize and validate IDs/clocks even for a first inbound delta.
                    var fresh = MatchDocument(id: incoming.id, configuration: incoming.configuration, createdAt: incoming.createdAt)
                    try fresh.merge(incoming)
                    documents.append(fresh)
                    let current = documents.first { $0.id == activeID }
                    if (activeID == nil || current?.snapshot.winner != nil || current?.isAbandoned == true),
                       fresh.snapshot.winner == nil, !fresh.isAbandoned { activeID = fresh.id }
                }
                documents.sort { $0.updatedAt > $1.updatedAt }
                try persist()
                refresh()
                // Incoming updates never replay speech or vibrate a second device.
            }
        } catch {
            documents = previousDocuments
            activeID = previousActiveID
            refresh()
            lastError = "同步未完成，当前本地记录已保留：\(error.localizedDescription)"
        }
    }
}
