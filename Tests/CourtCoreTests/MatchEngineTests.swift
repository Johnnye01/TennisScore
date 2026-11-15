import XCTest
@testable import CourtCore

final class MatchEngineTests: XCTestCase {
    private func configuration(bestOf: Int = 3, games: Int = 2, kind: MatchKind = .singles,
                               scoring: GameScoring = .advantage, deciding: Bool = true) -> MatchConfiguration {
        var config = MatchConfiguration()
        config.bestOf = bestOf
        config.gamesToWinSet = games
        config.kind = kind
        config.gameScoring = scoring
        config.decidingMatchTiebreak = deciding
        return config
    }

    private func game(_ side: Side, in engine: inout MatchEngine) throws {
        for _ in 0..<4 { try engine.apply(.point(side)) }
    }

    private func set(_ side: Side, in engine: inout MatchEngine) throws {
        for _ in 0..<engine.configuration.gamesToWinSet { try game(side, in: &engine) }
    }

    private func enterTiebreak(_ engine: inout MatchEngine) throws {
        for _ in 0..<engine.configuration.gamesToWinSet {
            try game(.home, in: &engine)
            try game(.away, in: &engine)
        }
        XCTAssertEqual(engine.snapshot.phase, .setTiebreak)
    }

    func testInitialMatchAndOneSetDoNotBeginWithMatchTiebreak() {
        let engine = MatchEngine(configuration: configuration(bestOf: 1))
        XCTAssertEqual(engine.snapshot.phase, .regular)
        XCTAssertEqual(engine.snapshot.pointLabels, ["0", "0"])
        XCTAssertEqual(engine.snapshot.server.id, "home-1")
        XCTAssertEqual(engine.snapshot.receiver.id, "away-1")
        XCTAssertEqual(engine.snapshot.serviceCourt, .deuce)
        XCTAssertEqual(engine.snapshot.homeEnd, .near)
        XCTAssertTrue(engine.snapshot.canChangeLineup)
        XCTAssertNil(engine.snapshot.winner)
    }

    func testShortSetRequiresTwoGameMargin() throws {
        var engine = MatchEngine(configuration: configuration(bestOf: 1))
        try game(.home, in: &engine)
        try game(.away, in: &engine)
        try game(.home, in: &engine)
        XCTAssertEqual(engine.snapshot.games, [2, 1])
        XCTAssertNil(engine.snapshot.winner)
        try game(.home, in: &engine)
        XCTAssertEqual(engine.snapshot.winner, .home)
        XCTAssertEqual(engine.snapshot.completedSets.first?.display, "3–1")
    }

    func testShortSetTiebreakAtTwoAllNotOneAll() throws {
        var engine = MatchEngine(configuration: configuration(bestOf: 1))
        try game(.home, in: &engine)
        try game(.away, in: &engine)
        XCTAssertEqual(engine.snapshot.phase, .regular)
        try game(.home, in: &engine)
        try game(.away, in: &engine)
        XCTAssertEqual(engine.snapshot.phase, .setTiebreak)
        XCTAssertEqual(engine.snapshot.games, [2, 2])
        for _ in 0..<7 { try engine.apply(.point(.away)) }
        XCTAssertEqual(engine.snapshot.winner, .away)
        XCTAssertEqual(engine.snapshot.completedSets.first?.display, "2–3")
        XCTAssertEqual(engine.snapshot.completedSets.first?.tiebreakPoints, [0, 7])
    }

    func testSixGameSetContinuesAtSixFiveAndEndsAtSevenFive() throws {
        var engine = MatchEngine(configuration: configuration(bestOf: 1, games: 6))
        for _ in 0..<5 { try game(.home, in: &engine); try game(.away, in: &engine) }
        try game(.home, in: &engine)
        XCTAssertEqual(engine.snapshot.games, [6, 5])
        XCTAssertEqual(engine.snapshot.phase, .regular)
        try game(.home, in: &engine)
        XCTAssertEqual(engine.snapshot.completedSets.first?.display, "7–5")
    }

    func testSevenPointTiebreakRequiresTwoPointMargin() throws {
        var engine = MatchEngine(configuration: configuration(bestOf: 1, games: 6))
        try enterTiebreak(&engine)
        for _ in 0..<6 { try engine.apply(.point(.home)); try engine.apply(.point(.away)) }
        try engine.apply(.point(.home))
        XCTAssertNil(engine.snapshot.winner)
        XCTAssertEqual(engine.snapshot.points, [7, 6])
        try engine.apply(.point(.home))
        XCTAssertEqual(engine.snapshot.completedSets.first?.display, "7–6")
        XCTAssertEqual(engine.snapshot.completedSets.first?.tiebreakPoints, [8, 6])
    }

    func testDecidingMatchTiebreakAtOneSetAllAndWinsByTwo() throws {
        var engine = MatchEngine(configuration: configuration())
        try set(.home, in: &engine)
        XCTAssertEqual(engine.snapshot.phase, .regular)
        try set(.away, in: &engine)
        XCTAssertEqual(engine.snapshot.setsWon, [1, 1])
        XCTAssertEqual(engine.snapshot.phase, .matchTiebreak)
        for _ in 0..<9 { try engine.apply(.point(.home)); try engine.apply(.point(.away)) }
        try engine.apply(.point(.home))
        XCTAssertNil(engine.snapshot.winner)
        XCTAssertEqual(engine.snapshot.points, [10, 9])
        try engine.apply(.point(.home))
        XCTAssertEqual(engine.snapshot.winner, .home)
        XCTAssertEqual(engine.snapshot.setsWon, [2, 1])
        XCTAssertTrue(engine.snapshot.completedSets.last!.isMatchTiebreak)
        XCTAssertEqual(engine.snapshot.completedSets.last?.display, "[11–9]")
    }

    func testFiveSetMatchUsesMatchTiebreakOnlyAtTwoSetsAll() throws {
        var engine = MatchEngine(configuration: configuration(bestOf: 5))
        try set(.home, in: &engine)
        try set(.away, in: &engine)
        XCTAssertEqual(engine.snapshot.phase, .regular)
        try set(.home, in: &engine)
        XCTAssertEqual(engine.snapshot.phase, .regular)
        try set(.away, in: &engine)
        XCTAssertEqual(engine.snapshot.phase, .matchTiebreak)
        XCTAssertEqual(engine.snapshot.setsWon, [2, 2])
    }

    func testATPPresetsDistinguishSinglesAndDoubles() {
        var config = MatchConfiguration()
        config.applyPreset(.atpSingles)
        XCTAssertEqual(config.kind, .singles)
        XCTAssertEqual(config.bestOf, 3)
        XCTAssertEqual(config.gamesToWinSet, 6)
        XCTAssertEqual(config.gameScoring, .advantage)
        XCTAssertFalse(config.decidingMatchTiebreak)
        config.applyPreset(.atpDoubles)
        XCTAssertEqual(config.kind, .doubles)
        XCTAssertEqual(config.gameScoring, .noAd)
        XCTAssertTrue(config.decidingMatchTiebreak)
    }

    func testFullDecidingSetWhenMatchTiebreakDisabled() throws {
        var engine = MatchEngine(configuration: configuration(deciding: false))
        try set(.home, in: &engine)
        try set(.away, in: &engine)
        XCTAssertEqual(engine.snapshot.phase, .regular)
        try set(.away, in: &engine)
        XCTAssertEqual(engine.snapshot.winner, .away)
        XCTAssertEqual(engine.snapshot.completedSets.count, 3)
        XCTAssertFalse(engine.snapshot.completedSets.last!.isMatchTiebreak)
    }

    func testDeuceAdvantageAndReturnToDeuce() throws {
        var engine = MatchEngine(configuration: configuration())
        for _ in 0..<3 { try engine.apply(.point(.home)); try engine.apply(.point(.away)) }
        XCTAssertEqual(engine.snapshot.lastAnnouncement, "Deuce.")
        try engine.apply(.point(.home))
        XCTAssertEqual(engine.snapshot.pointLabels, ["AD", "40"])
        XCTAssertEqual(engine.snapshot.lastAnnouncement, "Advantage Alex.")
        try engine.apply(.point(.away))
        XCTAssertEqual(engine.snapshot.lastAnnouncement, "Deuce.")
        try engine.apply(.point(.away))
        try engine.apply(.point(.away))
        XCTAssertEqual(engine.snapshot.games, [0, 1])
        XCTAssertTrue(engine.snapshot.lastAnnouncement.hasPrefix("Game, Sam."))
    }

    func testNoAdRequiresReceiverChoiceAndResetsItNextGame() throws {
        var engine = MatchEngine(configuration: configuration(kind: .doubles, scoring: .noAd))
        for _ in 0..<3 { try engine.apply(.point(.home)); try engine.apply(.point(.away)) }
        XCTAssertTrue(engine.snapshot.receiverChoiceNeeded)
        let before = engine.snapshot
        XCTAssertThrowsError(try engine.apply(.point(.home)))
        XCTAssertEqual(engine.snapshot, before)
        try engine.apply(.receiverChoice(.ad))
        XCTAssertFalse(engine.snapshot.receiverChoiceNeeded)
        XCTAssertEqual(engine.snapshot.serviceCourt, .ad)
        XCTAssertEqual(engine.snapshot.receiver.id, "away-2")
        try engine.apply(.point(.home))
        XCTAssertEqual(engine.snapshot.games, [1, 0])
        XCTAssertEqual(engine.snapshot.serviceCourt, .deuce)
        XCTAssertEqual(engine.snapshot.points, [0, 0])
    }

    func testMixedNoAdAutomaticallyUsesSameGenderReceiver() throws {
        var config = configuration(kind: .doubles, scoring: .noAd)
        config.mixedDoubles = true
        config.homePlayers[0].gender = .male
        config.homePlayers[1].gender = .female
        config.awayPlayers[0].gender = .female
        config.awayPlayers[1].gender = .male
        var engine = MatchEngine(configuration: config)
        for _ in 0..<3 { try engine.apply(.point(.home)); try engine.apply(.point(.away)) }
        XCTAssertFalse(engine.snapshot.receiverChoiceNeeded)
        XCTAssertEqual(engine.snapshot.server.gender, .male)
        XCTAssertEqual(engine.snapshot.receiver.gender, .male)
        XCTAssertEqual(engine.snapshot.receiver.id, "away-2")
        XCTAssertEqual(engine.snapshot.serviceCourt, .ad)
        XCTAssertThrowsError(try engine.apply(.receiverChoice(.deuce)))
        try engine.apply(.point(.home))
        XCTAssertEqual(engine.snapshot.games, [1, 0])
    }

    func testMixedDoublesRequiresCompleteGenderSetup() {
        var config = configuration(kind: .doubles, scoring: .noAd)
        config.mixedDoubles = true
        XCTAssertFalse(config.validationIssues.isEmpty)
        var engine = MatchEngine(configuration: config)
        XCTAssertThrowsError(try engine.apply(.point(.home)))
    }

    func testDoublesRegularServerRotation() throws {
        var engine = MatchEngine(configuration: configuration(games: 6, kind: .doubles))
        var servers: [String] = []
        for winner in [Side.home, .away, .home, .away, .home] {
            servers.append(engine.snapshot.server.id)
            try game(winner, in: &engine)
        }
        XCTAssertEqual(servers, ["home-1", "away-1", "home-2", "away-2", "home-1"])
    }

    func testDoublesTiebreakServeReceiveCourtAndEndSequence() throws {
        var engine = MatchEngine(configuration: configuration(games: 6, kind: .doubles))
        try enterTiebreak(&engine)
        let expectedServers = ["home-1", "away-1", "away-1", "home-2", "home-2", "away-2", "away-2", "home-1", "home-1"]
        let expectedReceivers = ["away-1", "home-2", "home-1", "away-2", "away-1", "home-2", "home-1", "away-2", "away-1"]
        for i in 0..<expectedServers.count {
            XCTAssertEqual(engine.snapshot.server.id, expectedServers[i], "Point \(i + 1)")
            XCTAssertEqual(engine.snapshot.receiver.id, expectedReceivers[i], "Point \(i + 1)")
            XCTAssertEqual(engine.snapshot.serviceCourt, i % 2 == 0 ? .deuce : .ad)
            XCTAssertEqual(engine.snapshot.homeEnd, i < 6 ? .near : .far)
            try engine.apply(.point(i % 2 == 0 ? .home : .away))
        }
    }

    func testNoAdDoesNotRequireReceiverChoiceInsideTiebreak() throws {
        var engine = MatchEngine(configuration: configuration(scoring: .noAd))
        try enterTiebreak(&engine)
        for _ in 0..<3 { try engine.apply(.point(.home)); try engine.apply(.point(.away)) }
        XCTAssertFalse(engine.snapshot.receiverChoiceNeeded)
        XCTAssertNoThrow(try engine.apply(.point(.home)))
    }

    func testTiebreakFirstServingTeamReceivesFirstNextSet() throws {
        var config = configuration()
        config.firstServingSide = .away
        var engine = MatchEngine(configuration: config)
        try enterTiebreak(&engine)
        XCTAssertEqual(engine.snapshot.servingSide, .away)
        for _ in 0..<7 { try engine.apply(.point(.home)) }
        XCTAssertEqual(engine.snapshot.phase, .regular)
        XCTAssertEqual(engine.snapshot.servingSide, .home)
        XCTAssertEqual(engine.snapshot.receiver.id, "away-1")
    }

    func testSixPointChangeoverHasNoRestAndOnlyLatestAlerts() throws {
        var engine = MatchEngine(configuration: configuration())
        try enterTiebreak(&engine)
        for _ in 0..<3 { try engine.apply(.point(.home)); try engine.apply(.point(.away)) }
        XCTAssertEqual(engine.snapshot.homeEnd, .far)
        XCTAssertEqual(engine.snapshot.alerts.filter { $0.kind == .changeEnds }.count, 1)
        XCTAssertTrue(engine.snapshot.alerts.allSatisfy { $0.restSeconds == nil })
        try engine.apply(.point(.home))
        XCTAssertFalse(engine.snapshot.alerts.contains { $0.kind == .changeEnds })
    }

    func testTiebreakEndingOnTwelfthPointChangesEndsOnce() throws {
        var engine = MatchEngine(configuration: configuration())
        try enterTiebreak(&engine)
        for _ in 0..<5 { try engine.apply(.point(.home)); try engine.apply(.point(.away)) }
        try engine.apply(.point(.home))
        XCTAssertEqual(engine.snapshot.points, [6, 5])
        XCTAssertEqual(engine.snapshot.homeEnd, .far)
        try engine.apply(.point(.home))
        XCTAssertEqual(engine.snapshot.completedSets.first?.tiebreakPoints, [7, 5])
        XCTAssertEqual(engine.snapshot.homeEnd, .near)
        XCTAssertEqual(engine.snapshot.alerts.filter { $0.kind == .changeEnds }.count, 1)
        XCTAssertEqual(engine.snapshot.alerts.first { $0.kind == .setBreak }?.restSeconds, 120)
    }

    func testFirstGameChangeoverHasNoRestLaterOddGamesHaveNinetySeconds() throws {
        var engine = MatchEngine(configuration: configuration(games: 6))
        try game(.home, in: &engine)
        XCTAssertEqual(engine.snapshot.homeEnd, .far)
        XCTAssertNil(engine.snapshot.alerts.first { $0.kind == .changeEnds }?.restSeconds)
        try game(.away, in: &engine)
        XCTAssertFalse(engine.snapshot.alerts.contains { $0.kind == .changeEnds })
        try game(.home, in: &engine)
        XCTAssertEqual(engine.snapshot.homeEnd, .near)
        XCTAssertEqual(engine.snapshot.alerts.first { $0.kind == .changeEnds }?.restSeconds, 90)
    }

    func testEvenGameSetDoesNotAddAnExtraChangeoverAndNextFirstGameDoes() throws {
        var engine = MatchEngine(configuration: configuration())
        try set(.home, in: &engine)
        XCTAssertEqual(engine.snapshot.homeEnd, .far)
        XCTAssertFalse(engine.snapshot.alerts.contains { $0.kind == .changeEnds })
        XCTAssertEqual(engine.snapshot.alerts.first { $0.kind == .setBreak }?.restSeconds, 120)
        try game(.away, in: &engine)
        XCTAssertEqual(engine.snapshot.homeEnd, .near)
        XCTAssertNil(engine.snapshot.alerts.first { $0.kind == .changeEnds }?.restSeconds)
    }

    func testLineupCanChangeOnlyBeforeFirstPointOfSet() throws {
        var engine = MatchEngine(configuration: configuration(kind: .doubles))
        try engine.apply(.lineup(SetLineup(homeFirstServer: 1, awayFirstServer: 1, homeDeuceReceiver: 1, awayDeuceReceiver: 1)))
        XCTAssertEqual(engine.snapshot.server.id, "home-2")
        XCTAssertEqual(engine.snapshot.receiver.id, "away-2")
        try engine.apply(.point(.home))
        XCTAssertThrowsError(try engine.apply(.lineup(SetLineup())))
        for _ in 0..<3 { try engine.apply(.point(.home)) }
        try game(.home, in: &engine)
        XCTAssertTrue(engine.snapshot.canChangeLineup)
        XCTAssertNoThrow(try engine.apply(.lineup(SetLineup())))
    }

    func testReplayAndDroppingLastPointRestoreAllStateExactly() throws {
        let config = configuration(kind: .doubles)
        var actions: [MatchAction] = []
        for _ in 0..<2 {
            actions += Array(repeating: .point(.home), count: 4)
            actions += Array(repeating: .point(.away), count: 4)
        }
        actions += [.point(.home), .point(.away), .point(.home), .point(.away), .point(.home), .point(.away)]
        let before = MatchEngine(configuration: config, events: actions)
        var after = before
        try after.apply(.point(.home))
        let replayed = MatchEngine(configuration: config, events: actions + [.point(.home)])
        XCTAssertEqual(after.snapshot, replayed.snapshot)
        XCTAssertTrue(replayed.replayIssues.isEmpty)
        let undone = MatchEngine(configuration: config, events: actions)
        XCTAssertEqual(before.snapshot, undone.snapshot)
        XCTAssertNotEqual(undone.snapshot.serviceCourt, after.snapshot.serviceCourt)
    }

    func testUndoAcrossSetBoundaryRestoresPriorServerAndCourtEnds() throws {
        let config = configuration(kind: .doubles)
        let actions = Array(repeating: MatchAction.point(.home), count: 7)
        let before = MatchEngine(configuration: config, events: actions)
        let completed = MatchEngine(configuration: config, events: actions + [.point(.home)])
        XCTAssertEqual(completed.snapshot.completedSets.count, 1)
        let undone = MatchEngine(configuration: config, events: actions)
        XCTAssertEqual(before.snapshot, undone.snapshot)
        XCTAssertEqual(undone.snapshot.completedSets.count, 0)
        XCTAssertEqual(undone.snapshot.server.id, "away-1")
    }

    func testEnglishCallsUseServerFirstAndLeaderFirstInsideTiebreak() throws {
        var config = configuration()
        config.firstServingSide = .away
        var engine = MatchEngine(configuration: config)
        try engine.apply(.point(.home))
        XCTAssertEqual(engine.snapshot.lastAnnouncement, "Sam serving. Love–fifteen.")
        XCTAssertEqual(engine.scoreAnnouncement(includeServerName: false), "Love–fifteen.")
        var tb = MatchEngine(configuration: config)
        try enterTiebreak(&tb)
        try tb.apply(.point(.home))
        XCTAssertEqual(tb.snapshot.lastAnnouncement, "One–zero, Alex.")
        try tb.apply(.point(.away))
        XCTAssertEqual(tb.snapshot.lastAnnouncement, "One all.")
    }

    func testRepeatScoreAfterGameReadsCurrentScoreNotPreviousGameCall() throws {
        var engine = MatchEngine(configuration: configuration())
        try game(.home, in: &engine)
        XCTAssertTrue(engine.snapshot.lastAnnouncement.hasPrefix("Game, Alex."))
        XCTAssertEqual(engine.scoreAnnouncement(), "Sam serving. Love-all.")
    }

    func testGameAndSetCallsUseLoveForZeroAndSingularGame() throws {
        var engine = MatchEngine(configuration: configuration())
        try game(.home, in: &engine)
        XCTAssertTrue(engine.snapshot.lastAnnouncement.contains("Alex leads one game to love."))
        try game(.home, in: &engine)
        XCTAssertTrue(engine.snapshot.lastAnnouncement.contains("two games to love."))
    }

    func testFourGameShortSetAndItsTiebreakTrigger() throws {
        var engine = MatchEngine(configuration: configuration(bestOf: 1, games: 4))
        for _ in 0..<3 { try game(.home, in: &engine); try game(.away, in: &engine) }
        XCTAssertEqual(engine.snapshot.phase, .regular)
        try game(.home, in: &engine)
        XCTAssertEqual(engine.snapshot.games, [4, 3])
        XCTAssertNil(engine.snapshot.winner)
        try game(.away, in: &engine)
        XCTAssertEqual(engine.snapshot.phase, .setTiebreak)
        for _ in 0..<7 { try engine.apply(.point(.home)) }
        XCTAssertEqual(engine.snapshot.completedSets.first?.display, "5–4")
    }

    func testActionRoundTripAndInvalidReplayDiagnostics() throws {
        let actions: [MatchAction] = [.lineup(SetLineup(homeFirstServer: 1)), .point(.away), .receiverChoice(.ad)]
        let data = try JSONEncoder().encode(actions)
        XCTAssertEqual(try JSONDecoder().decode([MatchAction].self, from: data), actions)
        let engine = MatchEngine(configuration: configuration(kind: .doubles), events: actions)
        XCTAssertEqual(engine.snapshot.points, [0, 1])
        XCTAssertEqual(engine.replayIssues.count, 1)
    }

    func testFinishedMatchRejectsFurtherPoints() throws {
        var engine = MatchEngine(configuration: configuration(bestOf: 1))
        try set(.home, in: &engine)
        let before = engine.snapshot
        XCTAssertThrowsError(try engine.apply(.point(.away)))
        XCTAssertEqual(engine.snapshot, before)
    }

    func testInvalidConfigurationIsInspectableAndCannotScore() {
        var config = MatchConfiguration()
        config.homePlayers = []
        config.gamesToWinSet = 0
        config.bestOf = 2
        var engine = MatchEngine(configuration: config)
        XCTAssertFalse(config.validationIssues.isEmpty)
        XCTAssertThrowsError(try engine.apply(.point(.home)))
        XCTAssertEqual(engine.snapshot.points, [0, 0])
    }
}
