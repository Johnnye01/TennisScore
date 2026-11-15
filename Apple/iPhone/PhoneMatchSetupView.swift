import SwiftUI

@MainActor
struct PhoneMatchSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MatchStore
    let onStarted: () -> Void
    @State private var configuration = MatchConfiguration()

    private var playerCount: Int { configuration.kind == .doubles ? 2 : 1 }
    private var summary: String {
        let match = configuration.bestOf == 1 ? "一盘定胜负" : configuration.bestOf == 3 ? "三盘两胜" : "五盘三胜"
        return "\(match) · 每盘 \(configuration.gamesToWinSet) 局起胜 · \(configuration.gamesToWinSet)–\(configuration.gamesToWinSet) 抢七"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        CourtTag(text: "LET’S PLAY", highlighted: true)
                        Text("设好比赛，\n专注下一球。")
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    presetSection
                    playersSection
                    scoringSection
                    lineupSection
                    CourtCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("本场规则", systemImage: "checkmark.seal")
                                .font(.headline).foregroundStyle(CourtPalette.lime)
                            Text(summary).font(.subheadline).foregroundStyle(.white)
                            Text(configuration.bestOf > 1 && configuration.decidingMatchTiebreak
                                 ? "普通盘须领先两局；抢七、抢十均须领先两分。决胜盘直接抢十。"
                                 : "普通盘须领先两局；抢七须领先两分。")
                                .font(.footnote).foregroundStyle(CourtPalette.secondary)
                            if !configuration.validationIssues.isEmpty {
                                ForEach(configuration.validationIssues, id: \.self) { issue in
                                    Label(issue, systemImage: "exclamationmark.circle")
                                        .font(.footnote).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    Button {
                        do {
                            try store.start(configuration: configuration)
                            dismiss()
                            onStarted()
                        } catch {
                            // MatchStore also surfaces its validation error to the root view.
                            store.lastError = error.localizedDescription
                        }
                    } label: {
                        Label("开始比赛", systemImage: "play.fill")
                    }
                    .buttonStyle(CourtPrimaryButtonStyle())
                    .disabled(!configuration.validationIssues.isEmpty)
                    .opacity(configuration.validationIssues.isEmpty ? 1 : 0.45)
                    Text("比赛保存在设备上。语音可以随时关闭，手动记分始终可用。")
                        .font(.footnote).foregroundStyle(CourtPalette.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .padding(.bottom, 22)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .courtScreen()
            .navigationTitle("新比赛")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(CourtPalette.secondary)
                }
            }
            .alert("无法开始比赛", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.clearError() } })) {
                Button("知道了") { store.clearError() }
            } message: {
                Text(store.lastError ?? "请检查比赛设置。")
            }
        }
    }

    private var presetSection: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 16) {
                CourtSectionTitle(title: "选择赛制")
                CourtChoice(title: "预设", options: [("自定义", MatchPreset.custom), ("ATP 单打", .atpSingles), ("ATP 双打", .atpDoubles)], selection: Binding(
                    get: { configuration.preset },
                    set: {
                        configuration.applyPreset($0)
                        if configuration.kind == .singles {
                            configuration.homeTeamName = ""
                            configuration.awayTeamName = ""
                        }
                    }
                ))
                CourtChoice(title: "比赛类型", options: [("单打", MatchKind.singles), ("双打", .doubles)], selection: customBinding(\.kind))
                Text(configuration.preset == .custom ? "可自由设置短盘和决胜抢十；发球与轮换遵循网球规则。" : configuration.preset == .atpSingles ? "三盘两胜、有占先；6–6 抢七，决胜盘完整进行。" : "两盘无占先计分；6–6 抢七，盘数 1–1 直接抢十。")
                    .font(.footnote).foregroundStyle(CourtPalette.secondary)
            }
        }
    }

    private var playersSection: some View {
        VStack(spacing: 14) {
            playerTeamSection(title: "我方", players: $configuration.homePlayers, teamName: $configuration.homeTeamName)
            playerTeamSection(title: "对方", players: $configuration.awayPlayers, teamName: $configuration.awayTeamName)
        }
    }

    private func playerTeamSection(title: String, players: Binding<[PlayerProfile]>, teamName: Binding<String>) -> some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    CourtSectionTitle(title: title)
                    Spacer()
                    Image(systemName: configuration.kind == .doubles ? "person.2.fill" : "person.fill")
                        .foregroundStyle(CourtPalette.lime)
                }
                if configuration.kind == .doubles {
                    CourtTextField(title: "队名（可选）", prompt: "例如：周末搭档", text: teamName)
                }
                ForEach(0..<playerCount, id: \.self) { index in
                    VStack(spacing: 10) {
                        CourtTextField(title: configuration.kind == .doubles ? "球员 \(index + 1) 名字" : "球员名字", text: playerNameBinding(players, index: index))
                        HStack(alignment: .bottom, spacing: 10) {
                            CourtTextField(title: "英文播报名（可选）", prompt: "例如：Alex Chen", text: players[index].spokenName)
                            Button {
                                let player = players.wrappedValue[index]
                                store.speakPreview(player.spokenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? player.displayName : player.spokenName)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .frame(width: 46, height: 46)
                                    .foregroundStyle(CourtPalette.lime)
                                    .background(CourtPalette.elevated, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("试听\(players.wrappedValue[index].displayName)的英文播报名")
                        }
                        if configuration.mixedDoubles {
                            CourtChoice(title: "混双球员组别", options: [("女", PlayerGender.female), ("男", .male)], selection: players[index].gender)
                        }
                    }
                    if index + 1 < playerCount { Divider().overlay(CourtPalette.line) }
                }
            }
        }
    }

    private var scoringSection: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 20) {
                CourtSectionTitle(title: "计分规则", subtitle: "修改预设后，将作为自定义赛制保存。")
                CourtChoice(title: "整场最多盘数", options: [("1 盘", 1), ("3 盘", 3), ("5 盘", 5)], selection: customBinding(\.bestOf))
                CourtChoice(title: "每盘目标局数", options: [("2 局", 2), ("4 局", 4), ("6 局", 6)], selection: customBinding(\.gamesToWinSet))
                CourtChoice(title: "40–40 后", options: [("占先，净胜两分", GameScoring.advantage), ("无占先，一分决胜", .noAd)], selection: customBinding(\.gameScoring))
                if configuration.bestOf > 1 {
                    Toggle(isOn: customBinding(\.decidingMatchTiebreak)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("决胜盘直接抢十").font(.subheadline.weight(.medium))
                            Text(configuration.bestOf == 3 ? "盘数 1–1 时，以抢十决定整场胜负" : "盘数 2–2 时，以抢十决定整场胜负")
                                .font(.caption).foregroundStyle(CourtPalette.secondary)
                        }
                    }
                }
                if configuration.kind == .doubles {
                    Toggle("混双", isOn: customBinding(\.mixedDoubles))
                        .font(.subheadline)
                    if configuration.mixedDoubles && configuration.gameScoring == .noAd {
                        Text("无占先决胜分由与发球人同组别的球员接发。请为四人设置组别。")
                            .font(.footnote).foregroundStyle(CourtPalette.secondary)
                    }
                }
            }
        }
    }

    private var lineupSection: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 18) {
                CourtSectionTitle(title: "开场安排", subtitle: "设置一次，之后自动追踪发球和换边。")
                CourtChoice(title: "首先发球", options: [("我方", Side.home), ("对方", .away)], selection: $configuration.firstServingSide)
                CourtChoice(title: "我方起始场地端", options: [("近端", CourtEnd.near), ("远端", .far)], selection: $configuration.initialHomeEnd)
                Text("近端／远端用于场地图示；左右发球区始终按发球人面向球网的视角判断。")
                    .font(.caption).foregroundStyle(CourtPalette.secondary)
                if configuration.kind == .doubles {
                    Divider().overlay(CourtPalette.line)
                    playerPicker(title: "我方首位发球人", players: configuration.homePlayers, selection: $configuration.homeFirstServer)
                    playerPicker(title: "对方首位发球人", players: configuration.awayPlayers, selection: $configuration.awayFirstServer)
                    playerPicker(title: "我方右区接发人", players: configuration.homePlayers, selection: $configuration.homeDeuceReceiver)
                    playerPicker(title: "对方右区接发人", players: configuration.awayPlayers, selection: $configuration.awayDeuceReceiver)
                    Text("右区接发为 Deuce court；另一位球员负责左区。新盘开始前可调整队内顺序。")
                        .font(.caption).foregroundStyle(CourtPalette.secondary)
                }
            }
        }
    }

    private func playerPicker(title: String, players: [PlayerProfile], selection: Binding<Int>) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(0..<min(players.count, 2), id: \.self) { index in
                    Text(players[index].displayName.isEmpty ? "球员 \(index + 1)" : players[index].displayName).tag(index)
                }
            }
            .labelsHidden()
            .tint(CourtPalette.lime)
        }
    }

    private func customBinding<Value>(_ keyPath: WritableKeyPath<MatchConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: keyPath] }, set: {
            configuration[keyPath: keyPath] = $0
            configuration.preset = .custom
            if configuration.kind == .singles {
                configuration.mixedDoubles = false
                configuration.homeTeamName = ""
                configuration.awayTeamName = ""
            }
        })
    }

    private func playerNameBinding(_ players: Binding<[PlayerProfile]>, index: Int) -> Binding<String> {
        Binding(get: { players.wrappedValue[index].displayName }, set: { value in
            let priorName = players.wrappedValue[index].displayName
            if players.wrappedValue[index].spokenName == priorName {
                players.wrappedValue[index].spokenName = ""
            }
            players.wrappedValue[index].displayName = value
        })
    }
}
