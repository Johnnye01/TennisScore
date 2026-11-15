import XCTest
import CourtCore
@testable import CourtSession

final class DocumentTests: XCTestCase {
    func testOfflinePointsMergeWithoutOverwriteOrDuplication() throws {
        var original = MatchDocument(configuration: MatchConfiguration())
        try original.append(.score(.point(.home)), deviceID: "phone")
        var phone = original
        var watch = original
        try phone.append(.score(.point(.away)), deviceID: "phone")
        try watch.append(.score(.point(.home)), deviceID: "watch")
        try phone.merge(watch)
        try watch.merge(phone)
        XCTAssertEqual(phone, watch)
        XCTAssertEqual(phone.snapshot.points, [2, 1])
        try phone.merge(watch)
        XCTAssertEqual(phone.records.count, 3)
    }

    func testTwoDevicesUndoingSamePointOnlyRemoveItOnce() throws {
        var match = MatchDocument(configuration: MatchConfiguration())
        try match.append(.score(.point(.home)), deviceID: "phone")
        try match.append(.score(.point(.away)), deviceID: "phone")
        var watch = match
        try match.undoLastPoint(deviceID: "phone")
        try watch.undoLastPoint(deviceID: "watch")
        try match.merge(watch)
        XCTAssertEqual(match.snapshot.points, [1, 0])
        XCTAssertEqual(match.state.acceptedPointIDs.count, 1)
    }

    func testUndoAcrossGameBoundaryRestoresServerAndCourtEnd() throws {
        var config = MatchConfiguration()
        config.bestOf = 1
        var match = MatchDocument(configuration: config)
        for _ in 0..<3 { try match.append(.score(.point(.home)), deviceID: "watch") }
        let before = match.snapshot
        try match.append(.score(.point(.home)), deviceID: "watch")
        XCTAssertEqual(match.snapshot.games, [1, 0])
        try match.undoLastPoint(deviceID: "phone")
        XCTAssertEqual(match.snapshot.points, before.points)
        XCTAssertEqual(match.snapshot.games, before.games)
        XCTAssertEqual(match.snapshot.servingSide, before.servingSide)
        XCTAssertEqual(match.snapshot.homeEnd, before.homeEnd)
        XCTAssertEqual(match.snapshot.serviceCourt, before.serviceCourt)
    }

    func testUndoRemovesDependentNoAdReceiverSelection() throws {
        var config = MatchConfiguration()
        config.gameScoring = .noAd
        var match = MatchDocument(configuration: config)
        for _ in 0..<3 {
            try match.append(.score(.point(.home)), deviceID: "watch")
            try match.append(.score(.point(.away)), deviceID: "watch")
        }
        XCTAssertTrue(match.snapshot.receiverChoiceNeeded)
        try match.append(.score(.receiverChoice(.ad)), deviceID: "watch")
        try match.undoLastPoint(deviceID: "watch")
        XCTAssertEqual(match.snapshot.points, [3, 2])
        XCTAssertTrue(match.state.replayIssues.isEmpty)
        try match.append(.score(.point(.away)), deviceID: "phone")
        XCTAssertTrue(match.snapshot.receiverChoiceNeeded)
    }

    func testBackupRoundTripPreservesDocumentAndPause() throws {
        var match = MatchDocument(configuration: MatchConfiguration())
        try match.append(.score(.point(.home)), deviceID: "phone")
        try match.append(.setPaused(true), deviceID: "phone")
        let archive = try MatchArchive.decode(MatchArchive(documents: [match]).encoded())
        XCTAssertEqual(archive.documents, [match])
        XCTAssertTrue(archive.documents[0].isPaused)
    }

    func testDifferentConfigurationsNeverOverwriteLocalMatch() throws {
        let local = MatchDocument(configuration: MatchConfiguration())
        var changed = MatchConfiguration()
        changed.gamesToWinSet = 4
        let remote = MatchDocument(id: local.id, configuration: changed)
        var merged = local
        XCTAssertThrowsError(try merged.merge(remote))
        XCTAssertEqual(merged, local)
    }

    func testDeterministicOrderDoesNotDependOnWallClock() throws {
        var match = MatchDocument(configuration: MatchConfiguration())
        try match.append(.score(.point(.home)), deviceID: "watch", at: Date(timeIntervalSince1970: 100))
        try match.append(.score(.point(.away)), deviceID: "phone", at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(match.records.map(\.clock), [1, 2])
        XCTAssertEqual(match.snapshot.points, [1, 1])
    }
}
