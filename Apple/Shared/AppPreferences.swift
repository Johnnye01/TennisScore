import Foundation

struct AppPreferences: Codable, Equatable {
    var speechEnabled = true
    var voiceCommandsEnabled = false
    var changeoverRemindersEnabled = true
    var hydrationRemindersEnabled = true
    var serveRemindersEnabled = true
    var includeNamesInSpeech = true
}

struct MatchReminder: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var message: String
    var restUntil: Date?
}

enum AppActionError: LocalizedError {
    case noMatch, paused, ended, voiceDisabled
    var errorDescription: String? {
        switch self {
        case .noMatch: return "请先在 CourtCall 开始或恢复一场比赛。"
        case .paused: return "比赛已暂停，请先恢复比赛。"
        case .ended: return "这场比赛已提前结束，请开始新比赛。"
        case .voiceDisabled: return "语音记分已关闭，请在 CourtCall 设置中开启。手动记分仍可使用。"
        }
    }
}
