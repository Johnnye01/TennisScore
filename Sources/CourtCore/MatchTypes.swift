import Foundation

public enum Side: Int, Codable, CaseIterable, Equatable, Hashable {
    case home = 0, away = 1
    public var opponent: Side { self == .home ? .away : .home }
    public var index: Int { rawValue }
}

public enum MatchKind: String, Codable, CaseIterable { case singles, doubles }
public enum MatchPreset: String, Codable, CaseIterable { case custom, atpSingles, atpDoubles }
public enum GameScoring: String, Codable, CaseIterable { case advantage, noAd }
public enum ServiceCourt: String, Codable, CaseIterable { case deuce, ad }
public enum CourtEnd: String, Codable, CaseIterable {
    case near, far
    public var opposite: CourtEnd { self == .near ? .far : .near }
}
public enum PlayerGender: String, Codable, CaseIterable { case unspecified, female, male }

public struct PlayerProfile: Codable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var spokenName: String
    public var gender: PlayerGender

    public init(id: String = UUID().uuidString, displayName: String,
                spokenName: String = "", gender: PlayerGender = .unspecified) {
        self.id = id
        self.displayName = displayName
        self.spokenName = spokenName
        self.gender = gender
    }

    public var spokenLabel: String {
        let spoken = spokenName.trimmingCharacters(in: .whitespacesAndNewlines)
        return spoken.isEmpty ? displayName : spoken
    }
}

public struct SetLineup: Codable, Equatable {
    public var homeFirstServer: Int
    public var awayFirstServer: Int
    public var homeDeuceReceiver: Int
    public var awayDeuceReceiver: Int

    public init(homeFirstServer: Int = 0, awayFirstServer: Int = 0,
                homeDeuceReceiver: Int = 0, awayDeuceReceiver: Int = 0) {
        self.homeFirstServer = homeFirstServer
        self.awayFirstServer = awayFirstServer
        self.homeDeuceReceiver = homeDeuceReceiver
        self.awayDeuceReceiver = awayDeuceReceiver
    }

    public func firstServer(for side: Side) -> Int {
        side == .home ? homeFirstServer : awayFirstServer
    }
    public func deuceReceiver(for side: Side) -> Int {
        side == .home ? homeDeuceReceiver : awayDeuceReceiver
    }
}

public struct MatchConfiguration: Codable, Equatable {
    public var kind: MatchKind = .singles
    public var preset: MatchPreset = .custom
    public var homePlayers: [PlayerProfile] = [
        PlayerProfile(id: "home-1", displayName: "Alex", spokenName: "Alex"),
        PlayerProfile(id: "home-2", displayName: "Jamie", spokenName: "Jamie")
    ]
    public var awayPlayers: [PlayerProfile] = [
        PlayerProfile(id: "away-1", displayName: "Sam", spokenName: "Sam"),
        PlayerProfile(id: "away-2", displayName: "Taylor", spokenName: "Taylor")
    ]
    public var homeTeamName: String = ""
    public var awayTeamName: String = ""
    public var bestOf: Int = 3
    public var gamesToWinSet: Int = 6
    public var gameScoring: GameScoring = .advantage
    public var decidingMatchTiebreak: Bool = true
    public var firstServingSide: Side = .home
    public var homeFirstServer: Int = 0
    public var awayFirstServer: Int = 0
    public var homeDeuceReceiver: Int = 0
    public var awayDeuceReceiver: Int = 0
    public var initialHomeEnd: CourtEnd = .near
    public var mixedDoubles: Bool = false

    public init() {}

    public mutating func applyPreset(_ preset: MatchPreset) {
        self.preset = preset
        switch preset {
        case .custom: break
        case .atpSingles:
            kind = .singles
            bestOf = 3
            gamesToWinSet = 6
            gameScoring = .advantage
            decidingMatchTiebreak = false
            mixedDoubles = false
        case .atpDoubles:
            kind = .doubles
            bestOf = 3
            gamesToWinSet = 6
            gameScoring = .noAd
            decidingMatchTiebreak = true
            mixedDoubles = false
        }
    }

    public func players(for side: Side) -> [PlayerProfile] {
        let slots = side == .home ? homePlayers : awayPlayers
        return Array(slots.prefix(kind == .singles ? 1 : 2))
    }

    public func teamName(for side: Side) -> String {
        let custom = (side == .home ? homeTeamName : awayTeamName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return players(for: side).map(\.displayName).joined(separator: " / ")
    }

    public func spokenTeamName(for side: Side) -> String {
        players(for: side).map(\.spokenLabel).joined(separator: " and ")
    }

    public var initialLineup: SetLineup {
        SetLineup(homeFirstServer: homeFirstServer, awayFirstServer: awayFirstServer,
                  homeDeuceReceiver: homeDeuceReceiver, awayDeuceReceiver: awayDeuceReceiver)
    }

    public var validationIssues: [String] {
        var issues: [String] = []
        if ![1, 3, 5].contains(bestOf) { issues.append("整场赛制须为 1、3 或 5 盘。") }
        if ![2, 4, 6].contains(gamesToWinSet) { issues.append("每盘目标局数须为 2、4 或 6。") }
        let count = kind == .singles ? 1 : 2
        let active = players(for: .home) + players(for: .away)
        if homePlayers.count < count || awayPlayers.count < count { issues.append("请填写所有参赛球员。") }
        if active.contains(where: { $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append("球员姓名不能为空。")
        }
        if Set(active.map(\.id)).count != active.count || active.contains(where: { $0.id.isEmpty }) {
            issues.append("每位球员需要独立的标识。")
        }
        if kind == .doubles {
            if [homeFirstServer, awayFirstServer, homeDeuceReceiver, awayDeuceReceiver]
                .contains(where: { ![0, 1].contains($0) }) {
                issues.append("双打发球和接发球顺序无效。")
            }
        }
        if mixedDoubles {
            if kind != .doubles { issues.append("混双设置只适用于双打。") }
            for side in Side.allCases {
                let genders = players(for: side).map(\.gender)
                if genders.filter({ $0 == .female }).count != 1 || genders.filter({ $0 == .male }).count != 1 {
                    issues.append("混双每队需指定一位男球员和一位女球员，以提示决胜分接发球人。")
                    break
                }
            }
        }
        return issues
    }
}

public enum MatchAction: Codable, Equatable {
    case point(Side)
    case receiverChoice(ServiceCourt)
    case lineup(SetLineup)
}

public enum MatchPhase: String, Codable { case regular, setTiebreak, matchTiebreak, finished }
public enum MatchAlertKind: String, Codable { case changeEnds, changeServer, setBreak, matchComplete }

public struct MatchAlert: Codable, Equatable {
    public var kind: MatchAlertKind
    public var message: String
    public var restSeconds: Int?
    public init(kind: MatchAlertKind, message: String, restSeconds: Int? = nil) {
        self.kind = kind
        self.message = message
        self.restSeconds = restSeconds
    }
}

public struct SetScore: Codable, Equatable {
    public var homeGames: Int
    public var awayGames: Int
    public var tiebreakPoints: [Int]?
    public var isMatchTiebreak: Bool
    public var winner: Side

    public init(homeGames: Int, awayGames: Int, tiebreakPoints: [Int]? = nil,
                isMatchTiebreak: Bool = false, winner: Side) {
        self.homeGames = homeGames
        self.awayGames = awayGames
        self.tiebreakPoints = tiebreakPoints
        self.isMatchTiebreak = isMatchTiebreak
        self.winner = winner
    }

    public var display: String {
        if isMatchTiebreak, let points = tiebreakPoints, points.count == 2 {
            return "[\(points[0])–\(points[1])]"
        }
        return "\(homeGames)–\(awayGames)"
    }
}

public struct MatchSnapshot: Codable, Equatable {
    public var points: [Int]
    public var games: [Int]
    public var setsWon: [Int]
    public var completedSets: [SetScore]
    public var phase: MatchPhase
    public var servingSide: Side
    public var server: PlayerProfile
    public var receiver: PlayerProfile
    public var serviceCourt: ServiceCourt
    public var homeEnd: CourtEnd
    public var winner: Side?
    public var receiverChoiceNeeded: Bool
    public var canChangeLineup: Bool
    public var lineup: SetLineup
    public var lastAnnouncement: String
    public var alerts: [MatchAlert]

    public var pointLabels: [String] {
        if phase == .finished { return ["—", "—"] }
        if isTiebreak { return points.map(String.init) }
        if points[0] >= 3 && points[1] >= 3 {
            if points[0] == points[1] { return ["40", "40"] }
            return points[0] > points[1] ? ["AD", "40"] : ["40", "AD"]
        }
        return points.map { ["0", "15", "30", "40"][min($0, 3)] }
    }
    public var setNumber: Int { phase == .finished ? max(1, completedSets.count) : completedSets.count + 1 }
    public var isTiebreak: Bool { phase == .setTiebreak || phase == .matchTiebreak }
}

public enum MatchEngineError: Error, LocalizedError, Equatable {
    case invalidConfiguration([String])
    case invalidAction(String)
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let errors): return errors.joined(separator: "\n")
        case .invalidAction(let message): return message
        }
    }
}
