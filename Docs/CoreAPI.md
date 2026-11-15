# CourtCore API

Pure Foundation Swift package. `import CourtCore`.

```swift
enum Side: Int, Codable, CaseIterable { case home, away; var opponent: Side; var index: Int }
enum MatchKind: String, Codable, CaseIterable { case singles, doubles }
enum MatchPreset: String, Codable, CaseIterable { case custom, atpSingles, atpDoubles }
enum GameScoring: String, Codable, CaseIterable { case advantage, noAd }
enum ServiceCourt: String, Codable, CaseIterable { case deuce, ad }
enum CourtEnd: String, Codable, CaseIterable { case near, far }
enum PlayerGender: String, Codable, CaseIterable { case unspecified, female, male }
struct PlayerProfile: Codable, Equatable, Identifiable {
  var id: String; var displayName: String; var spokenName: String; var gender: PlayerGender
  init(id: String = UUID().uuidString, displayName: String, spokenName: String = "", gender: PlayerGender = .unspecified)
}
struct MatchConfiguration: Codable, Equatable {
  init()
  var kind: MatchKind = .singles
  var preset: MatchPreset = .custom
  var homePlayers: [PlayerProfile] // two configured slots; active count depends on kind
  var awayPlayers: [PlayerProfile]
  var homeTeamName: String; var awayTeamName: String
  var bestOf: Int = 3
  var gamesToWinSet: Int = 6
  var gameScoring: GameScoring = .advantage
  var decidingMatchTiebreak: Bool = true
  var firstServingSide: Side = .home
  var homeFirstServer: Int = 0; var awayFirstServer: Int = 0
  var homeDeuceReceiver: Int = 0; var awayDeuceReceiver: Int = 0
  var initialHomeEnd: CourtEnd = .near
  var mixedDoubles: Bool = false
  var validationIssues: [String] { get }
  mutating func applyPreset(_ preset: MatchPreset)
  func players(for side: Side) -> [PlayerProfile]
  func teamName(for side: Side) -> String
  func spokenTeamName(for side: Side) -> String
}
struct SetLineup: Codable, Equatable {
  var homeFirstServer: Int; var awayFirstServer: Int
  var homeDeuceReceiver: Int; var awayDeuceReceiver: Int
  init(homeFirstServer: Int = 0, awayFirstServer: Int = 0,
       homeDeuceReceiver: Int = 0, awayDeuceReceiver: Int = 0)
}
enum MatchAction: Codable, Equatable {
  case point(Side), receiverChoice(ServiceCourt), lineup(SetLineup)
}
enum MatchPhase: String, Codable { case regular, setTiebreak, matchTiebreak, finished }
enum MatchAlertKind: String, Codable { case changeEnds, changeServer, setBreak, matchComplete }
struct MatchAlert: Codable, Equatable {
  var kind: MatchAlertKind; var message: String; var restSeconds: Int?
}
struct SetScore: Codable, Equatable {
  var homeGames: Int; var awayGames: Int
  var tiebreakPoints: [Int]? // nil for a set without a tie-break
  var isMatchTiebreak: Bool // for match tie-break, homeGames/awayGames are 0, points hold result
  var winner: Side
  var display: String { get }
}
struct MatchSnapshot: Codable, Equatable {
  var points: [Int]; var games: [Int]; var setsWon: [Int]
  var completedSets: [SetScore]; var phase: MatchPhase
  var servingSide: Side; var server: PlayerProfile; var receiver: PlayerProfile
  var serviceCourt: ServiceCourt; var homeEnd: CourtEnd
  var winner: Side?; var receiverChoiceNeeded: Bool
  var canChangeLineup: Bool // true only before any play in current set
  var lineup: SetLineup
  var lastAnnouncement: String; var alerts: [MatchAlert]
  var pointLabels: [String] { get } // Love rendered as 0; advantage as AD
  var setNumber: Int { get }
  var isTiebreak: Bool { get }
}
struct MatchEngine {
  init(configuration: MatchConfiguration, events: [MatchAction] = [])
  var configuration: MatchConfiguration { get }
  var snapshot: MatchSnapshot { get }
  var replayIssues: [String] { get } // invalid replay actions skipped, surfaced for diagnostics
  func scoreAnnouncement(includeServerName: Bool = true) -> String
  mutating func apply(_ action: MatchAction) throws
}
```

`apply` rejects invalid configuration, scoring after completion, choosing a receiver court outside a No-Ad deciding point, and changing lineup after play has begun. An unchosen No-Ad deciding-point receiver court must be selected before awarding the next point. Mixed doubles automatically resolves the required same-gender receiver from configured gender values.

Root store performs undo by replaying retained action records; the engine has no separate undo mutation. Notifications describe the **next point** after scoring. `alerts` and `lastAnnouncement` are the latest action's feedback and must only be spoken on newly handled user actions, not on every render/replay/sync.
