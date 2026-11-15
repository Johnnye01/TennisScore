import Foundation
#if canImport(CourtCore)
import CourtCore
#endif

public enum SessionAction: Codable, Equatable {
    case score(MatchAction)
    case undo(pointID: UUID, dependentActionIDs: [UUID])
    case setPaused(Bool)
    case end
}

public struct ActionRecord: Codable, Equatable, Identifiable {
    public var id: UUID
    public var clock: Int64
    public var deviceID: String
    public var date: Date
    public var action: SessionAction

    public init(id: UUID = UUID(), clock: Int64, deviceID: String,
                date: Date = Date(), action: SessionAction) {
        self.id = id
        self.clock = clock
        self.deviceID = deviceID
        self.date = date
        self.action = action
    }

    public static func ordered(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.clock != rhs.clock { return lhs.clock < rhs.clock }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public struct SessionState {
    public var engine: MatchEngine
    public var snapshot: MatchSnapshot
    public var isPaused: Bool
    public var isAbandoned: Bool
    public var acceptedPointIDs: [UUID]
    public var replayIssues: [String]
}

public enum DocumentError: LocalizedError {
    case differentMatch
    case configurationConflict
    case recordConflict
    case recordLimit
    case clockOverflow
    case nothingToUndo
    case invalidArchive

    public var errorDescription: String? {
        switch self {
        case .differentMatch: return "这两份记录不属于同一场比赛。"
        case .configurationConflict: return "同一场比赛的赛制不一致，未覆盖现有记录。"
        case .recordConflict: return "同步记录发生冲突，原始数据已保留。"
        case .recordLimit: return "比赛记录数量过多，无法导入。"
        case .clockOverflow: return "比赛记录序号无效，无法继续记录。"
        case .nothingToUndo: return "目前没有可以撤销的得分。"
        case .invalidArchive: return "备份格式不受支持。"
        }
    }
}

/// A complete local match. Configuration is immutable once play starts.
/// Each device contributes unique operations; merging never replaces a score snapshot.
public struct MatchDocument: Codable, Equatable, Identifiable {
    public var id: UUID
    public var configuration: MatchConfiguration
    public var createdAt: Date
    public private(set) var records: [ActionRecord]

    public init(id: UUID = UUID(), configuration: MatchConfiguration,
                createdAt: Date = Date(), records: [ActionRecord] = []) {
        self.id = id
        self.configuration = configuration
        self.createdAt = createdAt
        self.records = records.sorted(by: ActionRecord.ordered)
    }

    public var updatedAt: Date { records.map(\.date).max() ?? createdAt }
    public var snapshot: MatchSnapshot { state.snapshot }
    public var isPaused: Bool { state.isPaused }
    public var isAbandoned: Bool { state.isAbandoned }

    public var state: SessionState {
        let ordered = records.sorted(by: ActionRecord.ordered)
        var byID: [UUID: ActionRecord] = [:]
        var excluded = Set<UUID>()
        for record in ordered {
            if case let .undo(pointID, dependentIDs) = record.action,
               let target = byID[pointID], case .score(.point) = target.action {
                excluded.insert(pointID)
                for id in dependentIDs {
                    if let dependent = byID[id], ActionRecord.ordered(target, dependent) {
                        switch dependent.action {
                        case .score(.receiverChoice), .score(.lineup): excluded.insert(id)
                        default: break
                        }
                    }
                }
            }
            byID[record.id] = record
        }

        var engine = MatchEngine(configuration: configuration)
        var paused = false
        var ended = false
        var pointIDs: [UUID] = []
        var issues: [String] = []
        for record in ordered where !excluded.contains(record.id) {
            switch record.action {
            case let .score(action):
                do {
                    try engine.apply(action)
                    if case .point = action { pointIDs.append(record.id) }
                } catch {
                    issues.append("\(record.id.uuidString): \(error.localizedDescription)")
                }
            case let .setPaused(value): paused = value
            case .end: ended = true
            case .undo: break
            }
        }
        return SessionState(engine: engine, snapshot: engine.snapshot,
                            isPaused: paused || (ended && engine.snapshot.winner == nil),
                            isAbandoned: ended && engine.snapshot.winner == nil,
                            acceptedPointIDs: pointIDs, replayIssues: issues)
    }

    @discardableResult
    public mutating func append(_ action: SessionAction, deviceID: String,
                                at date: Date = Date()) throws -> ActionRecord {
        guard records.count < 20_000 else { throw DocumentError.recordLimit }
        let previous = records.map(\.clock).max() ?? 0
        guard previous < Int64.max else { throw DocumentError.clockOverflow }
        let record = ActionRecord(clock: previous + 1, deviceID: deviceID, date: date, action: action)
        records.append(record)
        records.sort(by: ActionRecord.ordered)
        return record
    }

    @discardableResult
    public mutating func undoLastPoint(deviceID: String, at date: Date = Date()) throws -> ActionRecord {
        guard let pointID = state.acceptedPointIDs.last,
              let point = records.first(where: { $0.id == pointID }) else {
            throw DocumentError.nothingToUndo
        }
        let dependentIDs = records.filter { record in
            guard ActionRecord.ordered(point, record) else { return false }
            switch record.action {
            case .score(.receiverChoice), .score(.lineup): return true
            default: return false
            }
        }.map(\.id)
        return try append(.undo(pointID: pointID, dependentActionIDs: dependentIDs), deviceID: deviceID, at: date)
    }

    public mutating func merge(_ other: MatchDocument) throws {
        guard id == other.id else { throw DocumentError.differentMatch }
        guard configuration == other.configuration else { throw DocumentError.configurationConflict }
        var merged: [UUID: ActionRecord] = [:]
        for record in records + other.records {
            if let old = merged[record.id], old != record { throw DocumentError.recordConflict }
            merged[record.id] = record
        }
        guard merged.count <= 20_000 else { throw DocumentError.recordLimit }
        guard merged.values.allSatisfy({ $0.clock >= 0 && $0.clock < Int64.max }) else {
            throw DocumentError.clockOverflow
        }
        records = merged.values.sorted(by: ActionRecord.ordered)
    }

    public func containingOnly(_ newRecords: [ActionRecord]) -> MatchDocument {
        MatchDocument(id: id, configuration: configuration, createdAt: createdAt, records: newRecords)
    }
}

public struct MatchArchive: Codable {
    public var schemaVersion: Int = 1
    public var documents: [MatchDocument]

    public init(documents: [MatchDocument]) { self.documents = documents }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 20_000_000 else { throw DocumentError.recordLimit }
        let archive = try JSONDecoder().decode(Self.self, from: data)
        guard archive.schemaVersion == 1, archive.documents.count <= 500 else {
            throw DocumentError.invalidArchive
        }
        var ids = Set<UUID>()
        for document in archive.documents {
            guard ids.insert(document.id).inserted,
                  document.configuration.validationIssues.isEmpty,
                  document.records.count <= 20_000,
                  Set(document.records.map(\.id)).count == document.records.count,
                  document.records.allSatisfy({ $0.clock >= 0 && $0.clock < Int64.max }) else {
                throw DocumentError.invalidArchive
            }
        }
        return archive
    }
}
