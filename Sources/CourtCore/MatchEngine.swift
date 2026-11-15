import Foundation

/// Deterministic rules engine. Undo and synchronization replay a retained action log.
/// Receives a winner for each completed point; it never guesses faults or rally outcomes.
public struct MatchEngine {
    public private(set) var configuration: MatchConfiguration
    public private(set) var replayIssues: [String] = []

    private struct ServerPosition { var side: Side; var player: Int }
    private var points: [Int] = [0, 0]
    private var games: [Int] = [0, 0]
    private var setsWon: [Int] = [0, 0]
    private var completedSets: [SetScore] = []
    private var phase: MatchPhase = .regular
    private var winner: Side?
    private var lineup: SetLineup
    private var homeEnd: CourtEnd
    private var serveOrder: [ServerPosition]
    private var serveIndex: Int = 0
    private var tiebreakFirstServerIndex: Int?
    private var chosenReceiverCourt: ServiceCourt?
    private var lastAnnouncement: String = ""
    private var alerts: [MatchAlert] = []

    public init(configuration: MatchConfiguration, events: [MatchAction] = []) {
        self.configuration = configuration
        lineup = configuration.initialLineup
        homeEnd = configuration.initialHomeEnd
        serveOrder = Self.makeServeOrder(configuration: configuration, lineup: configuration.initialLineup,
                                        firstSide: configuration.firstServingSide)
        lastAnnouncement = "\(currentServer.spokenLabel) to serve. Love all."
        for event in events {
            do { try apply(event) }
            catch { replayIssues.append(error.localizedDescription) }
        }
    }

    public var snapshot: MatchSnapshot {
        MatchSnapshot(points: points, games: games, setsWon: setsWon, completedSets: completedSets,
                      phase: phase, servingSide: currentServerPosition.side, server: currentServer,
                      receiver: currentReceiver, serviceCourt: nextServiceCourt, homeEnd: homeEnd,
                      winner: winner, receiverChoiceNeeded: receiverChoiceNeeded,
                      canChangeLineup: canChangeLineup, lineup: lineup,
                      lastAnnouncement: lastAnnouncement, alerts: alerts)
    }

    /// A fresh read-out of the score at this instant, suitable for "repeat score".
    /// The optional prefix applies to ordinary points only; required names in
    /// advantage, tie-break and match-result calls are retained.
    public func scoreAnnouncement(includeServerName: Bool = true) -> String {
        if phase == .finished, let winner {
            return "Game, set and match, \(configuration.spokenTeamName(for: winner)). \(Self.number(setsWon[winner.index]).capitalized) sets to \(setsWon[winner.opponent.index] == 0 ? "love" : Self.number(setsWon[winner.opponent.index]))."
        }
        if phase == .regular { return regularAnnouncement(includeServerName: includeServerName) }
        return tiebreakAnnouncement()
    }

    public mutating func apply(_ action: MatchAction) throws {
        guard configuration.validationIssues.isEmpty else {
            throw MatchEngineError.invalidConfiguration(configuration.validationIssues)
        }
        guard winner == nil else { throw MatchEngineError.invalidAction("比赛已结束；请先撤销上一分或开始新比赛。") }
        switch action {
        case .point(let side):
            guard !receiverChoiceNeeded else {
                throw MatchEngineError.invalidAction("请先选择无占先决胜分的接发球区。")
            }
            alerts = []
            if phase == .regular { awardRegularPoint(to: side) }
            else { awardTiebreakPoint(to: side) }
        case .receiverChoice(let court):
            guard phase == .regular, configuration.gameScoring == .noAd,
                  points[0] == 3, points[1] == 3, !configuration.mixedDoubles else {
                throw MatchEngineError.invalidAction("只能在无占先决胜分前选择接发球区。")
            }
            alerts = []
            chosenReceiverCourt = court
            lastAnnouncement = "Receiver's choice. \(court == .deuce ? "Deuce" : "Ad") court. \(currentReceiver.spokenLabel) receiving."
        case .lineup(let newLineup):
            guard canChangeLineup else {
                throw MatchEngineError.invalidAction("只能在每盘开始、第一分尚未进行时调整队内顺序。")
            }
            if configuration.kind == .doubles,
               [newLineup.homeFirstServer, newLineup.awayFirstServer,
                newLineup.homeDeuceReceiver, newLineup.awayDeuceReceiver].contains(where: { ![0, 1].contains($0) }) {
                throw MatchEngineError.invalidAction("双打发球和接发球顺序无效。")
            }
            let firstSide = currentServerPosition.side
            lineup = newLineup
            serveOrder = Self.makeServeOrder(configuration: configuration, lineup: lineup, firstSide: firstSide)
            serveIndex = 0
            if phase != .regular { tiebreakFirstServerIndex = 0 }
            alerts = []
            lastAnnouncement = "\(currentServer.spokenLabel) to serve."
        }
    }

    private var currentServerPosition: ServerPosition { serveOrder[serveIndex % serveOrder.count] }
    private var currentServer: PlayerProfile { player(on: currentServerPosition.side, index: currentServerPosition.player) }
    private var currentReceiver: PlayerProfile {
        let side = currentServerPosition.side.opponent
        if configuration.kind == .singles { return player(on: side, index: 0) }
        let deuce = validPlayerIndex(lineup.deuceReceiver(for: side))
        return player(on: side, index: nextServiceCourt == .deuce ? deuce : 1 - deuce)
    }
    private var receiverChoiceNeeded: Bool {
        phase == .regular && configuration.gameScoring == .noAd && points == [3, 3]
            && chosenReceiverCourt == nil && !configuration.mixedDoubles
    }
    private var canChangeLineup: Bool { phase != .finished && points == [0, 0] && games == [0, 0] }
    private var nextServiceCourt: ServiceCourt {
        if phase == .regular, configuration.gameScoring == .noAd, points == [3, 3] {
            if configuration.mixedDoubles {
                let receivers = configuration.players(for: currentServerPosition.side.opponent)
                if let matchingIndex = receivers.firstIndex(where: { $0.gender == currentServer.gender }) {
                    return matchingIndex == validPlayerIndex(lineup.deuceReceiver(for: currentServerPosition.side.opponent)) ? .deuce : .ad
                }
            }
            if let selected = chosenReceiverCourt { return selected }
        }
        return (points[0] + points[1]) % 2 == 0 ? .deuce : .ad
    }

    private mutating func awardRegularPoint(to side: Side) {
        points[side.index] += 1
        let wonGame: Bool
        switch configuration.gameScoring {
        case .advantage:
            wonGame = points[side.index] >= 4 && points[side.index] - points[side.opponent.index] >= 2
        case .noAd:
            wonGame = points[side.index] >= 4
        }
        if !wonGame {
            lastAnnouncement = regularAnnouncement()
            return
        }
        games[side.index] += 1
        points = [0, 0]
        chosenReceiverCourt = nil
        serveIndex = (serveIndex + 1) % serveOrder.count
        if games[side.index] >= configuration.gamesToWinSet && games[side.index] - games[side.opponent.index] >= 2 {
            finishSet(wonBy: side, tiebreakPoints: nil, matchTiebreak: false)
            return
        }
        lastAnnouncement = "Game, \(configuration.spokenTeamName(for: side)). \(gameScoreAnnouncement())"
        if games == [configuration.gamesToWinSet, configuration.gamesToWinSet] {
            phase = .setTiebreak
            tiebreakFirstServerIndex = serveIndex
            lastAnnouncement += " Tie-break."
        } else if (games[0] + games[1]) % 2 == 1 {
            toggleEnds(restSeconds: games[0] + games[1] == 1 ? nil : 90)
        }
        announceNextServer()
    }

    private mutating func awardTiebreakPoint(to side: Side) {
        let isMatch = phase == .matchTiebreak
        let target = isMatch ? 10 : 7
        points[side.index] += 1
        if points[side.index] >= target && points[side.index] - points[side.opponent.index] >= 2 {
            let result = points
            serveIndex = ((tiebreakFirstServerIndex ?? 0) + 1) % serveOrder.count
            if !isMatch { games[side.index] += 1 }
            finishSet(wonBy: side, tiebreakPoints: result, matchTiebreak: isMatch)
            return
        }
        let oldServer = currentServer.id
        let played = points[0] + points[1]
        serveIndex = ((tiebreakFirstServerIndex ?? 0) + (played + 1) / 2) % serveOrder.count
        lastAnnouncement = tiebreakAnnouncement()
        if played % 6 == 0 { toggleEnds(restSeconds: nil) }
        if oldServer != currentServer.id {
            alerts.append(MatchAlert(kind: .changeServer, message: "\(currentServer.spokenLabel) to serve."))
        }
    }

    private mutating func finishSet(wonBy side: Side, tiebreakPoints: [Int]?, matchTiebreak: Bool) {
        let finishedGameCount = games[0] + games[1]
        let result = SetScore(homeGames: games[0], awayGames: games[1], tiebreakPoints: tiebreakPoints,
                              isMatchTiebreak: matchTiebreak, winner: side)
        completedSets.append(result)
        setsWon[side.index] += 1
        // A completed tie-break counts as one game. Do not also execute the
        // in-tie-break six-point changeover on this same final point.
        if !matchTiebreak && finishedGameCount % 2 == 1 { homeEnd = homeEnd.opposite }
        chosenReceiverCourt = nil
        if setsWon[side.index] >= configuration.bestOf / 2 + 1 {
            winner = side
            phase = .finished
            lastAnnouncement = "Game, set and match, \(configuration.spokenTeamName(for: side)). \(Self.number(setsWon[side.index]).capitalized) sets to \(setsWon[side.opponent.index] == 0 ? "love" : Self.number(setsWon[side.opponent.index]))."
            alerts.append(MatchAlert(kind: .matchComplete, message: lastAnnouncement))
            return
        }
        if !matchTiebreak && finishedGameCount % 2 == 1 {
            alerts.append(MatchAlert(kind: .changeEnds, message: "Change ends."))
        }
        let ordinals = ["first", "second", "third", "fourth", "fifth"]
        let ordinal = ordinals[min(completedSets.count - 1, ordinals.count - 1)]
        let winnerGames = side == .home ? result.homeGames : result.awayGames
        let loserGames = side == .home ? result.awayGames : result.homeGames
        lastAnnouncement = "Game and \(ordinal) set, \(configuration.spokenTeamName(for: side)), \(Self.gameNumber(winnerGames)) games to \(Self.gameNumber(loserGames))."
        alerts.append(MatchAlert(kind: .setBreak, message: "Set break. Time to hydrate.", restSeconds: 120))
        let nextSide = currentServerPosition.side
        serveOrder = Self.makeServeOrder(configuration: configuration, lineup: lineup, firstSide: nextSide)
        serveIndex = 0
        games = [0, 0]
        points = [0, 0]
        if configuration.decidingMatchTiebreak && configuration.bestOf > 1 &&
            setsWon[0] == configuration.bestOf / 2 && setsWon[1] == configuration.bestOf / 2 {
            phase = .matchTiebreak
            tiebreakFirstServerIndex = 0
            lastAnnouncement += " Match tie-break."
        } else {
            phase = .regular
            tiebreakFirstServerIndex = nil
        }
        announceNextServer()
    }

    private mutating func toggleEnds(restSeconds: Int?) {
        homeEnd = homeEnd.opposite
        alerts.append(MatchAlert(kind: .changeEnds, message: "Change ends.", restSeconds: restSeconds))
    }

    private mutating func announceNextServer() {
        let message = "\(currentServer.spokenLabel) to serve."
        lastAnnouncement += " \(message)"
        alerts.append(MatchAlert(kind: .changeServer, message: message))
    }

    private func regularAnnouncement(includeServerName: Bool = true) -> String {
        if points[0] >= 3 && points[1] >= 3 {
            if points[0] == points[1] {
                if configuration.gameScoring == .noAd {
                    return configuration.mixedDoubles
                        ? "Deuce. Deciding point. \(currentReceiver.spokenLabel) receiving."
                        : "Deuce. Deciding point, receiver's choice."
                }
                return "Deuce."
            }
            let leader: Side = points[0] > points[1] ? .home : .away
            return "Advantage \(configuration.spokenTeamName(for: leader))."
        }
        let scoreWords = ["love", "fifteen", "thirty", "forty"]
        let servingSide = currentServerPosition.side
        let a = scoreWords[min(points[servingSide.index], 3)]
        let b = scoreWords[min(points[servingSide.opponent.index], 3)]
        let score = points[0] == points[1] ? "\(a.capitalized)-all" : "\(a.capitalized)–\(b)"
        return includeServerName ? "\(currentServer.spokenLabel) serving. \(score)." : "\(score)."
    }

    private func tiebreakAnnouncement() -> String {
        if points[0] == points[1] { return "\(Self.number(points[0]).capitalized) all." }
        let leading: Side = points[0] > points[1] ? .home : .away
        return "\(Self.number(points[leading.index]).capitalized)–\(Self.number(points[leading.opponent.index])), \(configuration.spokenTeamName(for: leading))."
    }

    private func gameScoreAnnouncement() -> String {
        if games[0] == games[1] { return "\(Self.gameNumber(games[0]).capitalized) game\(games[0] == 1 ? "" : "s") all." }
        let leading: Side = games[0] > games[1] ? .home : .away
        return "\(configuration.spokenTeamName(for: leading)) lead\(configuration.kind == .singles ? "s" : "") \(Self.gameNumber(games[leading.index])) game\(games[leading.index] == 1 ? "" : "s") to \(Self.gameNumber(games[leading.opponent.index]))."
    }

    private func player(on side: Side, index: Int) -> PlayerProfile {
        let players = configuration.players(for: side)
        guard players.indices.contains(index) else {
            return players.first ?? PlayerProfile(id: "missing-\(side.rawValue)", displayName: "Player")
        }
        return players[index]
    }

    private func validPlayerIndex(_ index: Int) -> Int { [0, 1].contains(index) ? index : 0 }

    private static func makeServeOrder(configuration: MatchConfiguration, lineup: SetLineup,
                                       firstSide: Side) -> [ServerPosition] {
        if configuration.kind == .singles {
            return [ServerPosition(side: firstSide, player: 0), ServerPosition(side: firstSide.opponent, player: 0)]
        }
        let firstIndex = [0, 1].contains(lineup.firstServer(for: firstSide)) ? lineup.firstServer(for: firstSide) : 0
        let otherIndex = [0, 1].contains(lineup.firstServer(for: firstSide.opponent)) ? lineup.firstServer(for: firstSide.opponent) : 0
        return [ServerPosition(side: firstSide, player: firstIndex),
                ServerPosition(side: firstSide.opponent, player: otherIndex),
                ServerPosition(side: firstSide, player: 1 - firstIndex),
                ServerPosition(side: firstSide.opponent, player: 1 - otherIndex)]
    }

    private static let smallNumbers = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    private static func gameNumber(_ value: Int) -> String { value == 0 ? "love" : number(value) }

    /// Most scoring calls are single digits. Avoid allocating NumberFormatter
    /// while replaying an entire match on a watch after an undo or merge.
    private static func number(_ value: Int) -> String {
        if value < 0 { return "minus \(number(-value))" }
        if value < 20 { return smallNumbers[value] }
        if value < 100 {
            let rest = value % 10
            return tens[value / 10] + (rest == 0 ? "" : "-\(smallNumbers[rest])")
        }
        if value < 1_000 {
            let rest = value % 100
            return "\(smallNumbers[value / 100]) hundred" + (rest == 0 ? "" : " \(number(rest))")
        }
        if value < 1_000_000 {
            let rest = value % 1_000
            return "\(number(value / 1_000)) thousand" + (rest == 0 ? "" : " \(number(rest))")
        }
        return String(value)
    }
}
