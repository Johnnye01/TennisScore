import AppIntents

// These intents deliberately expose a small, explicit vocabulary. They never
// listen to the microphone, infer a rally winner, or bypass the user's opt-in.
// The store persists the operation before returning the spoken Siri response.

struct HomePointIntent: AppIntent {
    static var title: LocalizedStringResource = "我方得分"
    static var description = IntentDescription("为当前 CourtCall 比赛的我方增加一分。需先在本设备开启语音记分。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try MatchStore.shared.performVoicePoint(.home)
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

struct AwayPointIntent: AppIntent {
    static var title: LocalizedStringResource = "对方得分"
    static var description = IntentDescription("为当前 CourtCall 比赛的对方增加一分。需先在本设备开启语音记分。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try MatchStore.shared.performVoicePoint(.away)
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

struct UndoPointIntent: AppIntent {
    static var title: LocalizedStringResource = "撤销上一分"
    static var description = IntentDescription("撤销当前比赛最后一分，并恢复发球、接发和场地状态。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try MatchStore.shared.performVoiceUndo()
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

struct ReadScoreIntent: AppIntent {
    static var title: LocalizedStringResource = "报比分"
    static var description = IntentDescription("用英文播报当前 CourtCall 比分。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try MatchStore.shared.performVoiceRead()
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

struct ChooseDeuceReceiverIntent: AppIntent {
    static var title: LocalizedStringResource = "选择右区接发"
    static var description = IntentDescription("无占先决胜分时，选择从发球人右区发球。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try MatchStore.shared.performVoiceReceiver(.deuce)
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

struct ChooseAdReceiverIntent: AppIntent {
    static var title: LocalizedStringResource = "选择左区接发"
    static var description = IntentDescription("无占先决胜分时，选择从发球人左区发球。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try MatchStore.shared.performVoiceReceiver(.ad)
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

struct CourtCallShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HomePointIntent(),
            phrases: ["用\(.applicationName)给我方加分"],
            shortTitle: "我方得分",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: AwayPointIntent(),
            phrases: ["用\(.applicationName)给对方加分"],
            shortTitle: "对方得分",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: UndoPointIntent(),
            phrases: ["用\(.applicationName)撤销上一分"],
            shortTitle: "撤销上一分",
            systemImageName: "arrow.uturn.backward"
        )
        AppShortcut(
            intent: ReadScoreIntent(),
            phrases: ["用\(.applicationName)报比分"],
            shortTitle: "报比分",
            systemImageName: "speaker.wave.2"
        )
        AppShortcut(
            intent: ChooseDeuceReceiverIntent(),
            phrases: ["用\(.applicationName)选择右区接发"],
            shortTitle: "右区接发",
            systemImageName: "arrow.right"
        )
        AppShortcut(
            intent: ChooseAdReceiverIntent(),
            phrases: ["用\(.applicationName)选择左区接发"],
            shortTitle: "左区接发",
            systemImageName: "arrow.left"
        )
    }
}
