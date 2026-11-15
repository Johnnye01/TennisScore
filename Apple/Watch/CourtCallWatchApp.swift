import SwiftUI

@main
@MainActor
struct CourtCallWatchApp: App {
    @StateObject private var store = MatchStore.shared

    var body: some Scene {
        WindowGroup {
            CourtCallWatchRoot(store: store)
                .preferredColorScheme(.dark)
                .tint(WatchPalette.lime)
        }
    }
}

@MainActor
struct CourtCallWatchRoot: View {
    @ObservedObject var store: MatchStore
    @State private var showsSettings = false
    @State private var showsMatches = false
    @State private var showsEndConfirmation = false
    @State private var showsLineup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let document = store.activeDocument, let snapshot = store.snapshot {
                        liveMatch(document: document, snapshot: snapshot)
                    } else {
                        home
                    }
                }
                .padding(.horizontal, 3)
                .padding(.bottom, 12)
            }
            .background(WatchPalette.background)
            .navigationTitle("CourtCall")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsMatches = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("切换或新建比赛")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("记分与语音设置")
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            WatchSettingsView(store: store)
        }
        .sheet(isPresented: $showsMatches) {
            WatchMatchPicker(store: store)
        }
        .sheet(isPresented: $showsLineup) {
            if let configuration = store.activeDocument?.configuration,
               let snapshot = store.snapshot {
                WatchLineupEditor(store: store, configuration: configuration, initial: snapshot.lineup)
            }
        }
        .confirmationDialog("结束当前比赛？", isPresented: $showsEndConfirmation, titleVisibility: .visible) {
            Button("结束并保留记录", role: .destructive) { store.endMatch() }
            Button("继续比赛", role: .cancel) { }
        } message: {
            Text("未完成的比赛会保存在历史记录中。")
        }
        .alert("未能完成操作", isPresented: errorIsPresented) {
            Button("知道了") { store.clearError() }
        } message: {
            Text(store.lastError ?? "请稍后重试。")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { store.lastError != nil }, set: { if !$0 { store.clearError() } })
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: "tennisball.fill")
                    .font(.title)
                    .foregroundStyle(WatchPalette.lime)
                Text("下一分，\n轻松记下。")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text("全程手动可用，语音由你选择。")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.muted)
            }

            NavigationLink {
                WatchNewMatchView(store: store)
            } label: {
                Label("新建比赛", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.borderedProminent)

            Text("也可以在 iPhone 设置名字和赛制，之后同步到手表。")
                .font(.caption2)
                .foregroundStyle(WatchPalette.muted)

            if !store.documents.isEmpty {
                Text("最近比赛")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WatchPalette.muted)
                ForEach(Array(store.documents.prefix(4))) { document in
                    Button {
                        store.resume(document)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(document.configuration.teamName(for: .home)) · \(document.configuration.teamName(for: .away))")
                                .font(.caption.weight(.medium))
                                .lineLimit(2)
                            HStack(spacing: 4) {
                                Text(document.createdAt, style: .date)
                                Spacer(minLength: 0)
                                Text(historyStatus(document))
                            }
                            .font(.caption2)
                            .foregroundStyle(WatchPalette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(store.connectionStatus)
                .font(.caption2)
                .foregroundStyle(WatchPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func liveMatch(document: MatchDocument, snapshot: MatchSnapshot) -> some View {
        if let reminder = store.activeReminder {
            if let deadline = reminder.restUntil {
                WatchRestCard(title: reminder.title, deadline: deadline, dismiss: store.dismissReminder)
            } else {
                WatchNotice(title: reminder.title, detail: reminder.message)
                Button("知道了", action: store.dismissReminder)
                    .font(.caption2)
                    .buttonStyle(.bordered)
            }
        }

        if snapshot.receiverChoiceNeeded && !document.isAbandoned {
            VStack(alignment: .leading, spacing: 8) {
                Text("决胜分 · 接发方选择")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WatchPalette.lime)
                Text("选定接发区后，再记录这一分。")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.muted)
                HStack(spacing: 6) {
                    Button("右区") { store.chooseReceiver(.deuce) }
                    Button("左区") { store.chooseReceiver(.ad) }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(store.isPaused)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        }

        WatchScoreSurface(
            match: presentation(document: document, snapshot: snapshot),
            scoreHome: { store.score(.home) },
            scoreAway: { store.score(.away) },
            undo: store.undo,
            repeatScore: store.repeatScore,
            togglePause: store.togglePause
        )

        if snapshot.canChangeLineup && document.configuration.kind == .doubles && snapshot.winner == nil {
            Button("本盘发球／接发顺序") { showsLineup = true }
                .font(.caption2)
                .buttonStyle(.bordered)
        }

        if !snapshot.completedSets.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("逐盘比分").font(.caption2).foregroundStyle(WatchPalette.muted)
                ForEach(Array(snapshot.completedSets.enumerated()), id: \.offset) { index, set in
                    HStack {
                        Text(set.isMatchTiebreak ? "决胜抢十" : "第 \(index + 1) 盘")
                        Spacer(minLength: 0)
                        Text(set.display).monospacedDigit()
                    }
                    .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        }

        Button(snapshot.winner == nil && !document.isAbandoned ? "结束比赛" : "返回首页") {
            if snapshot.winner != nil || document.isAbandoned { store.endMatch() }
            else { showsEndConfirmation = true }
        }
        .font(.caption2)
        .foregroundStyle(snapshot.winner == nil && !document.isAbandoned ? Color.red : WatchPalette.muted)
        .buttonStyle(.plain)
        .padding(.top, 4)

        Text(store.connectionStatus)
            .font(.caption2)
            .foregroundStyle(WatchPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presentation(document: MatchDocument, snapshot: MatchSnapshot) -> WatchScorePresentation {
        let configuration = document.configuration
        let finished = snapshot.winner != nil
        let phase: String
        switch snapshot.phase {
        case .regular: phase = "第 \(snapshot.setNumber) 盘"
        case .setTiebreak: phase = "抢七"
        case .matchTiebreak: phase = "抢十"
        case .finished: phase = "比赛结束"
        }
        return WatchScorePresentation(
            homeName: configuration.teamName(for: .home),
            awayName: configuration.teamName(for: .away),
            homePoints: finished ? String(snapshot.setsWon[0]) : snapshot.pointLabels[0],
            awayPoints: finished ? String(snapshot.setsWon[1]) : snapshot.pointLabels[1],
            sets: "\(snapshot.setsWon[0])–\(snapshot.setsWon[1])",
            games: "\(snapshot.games[0])–\(snapshot.games[1])",
            phase: phase,
            server: snapshot.server.displayName,
            receiver: snapshot.receiverChoiceNeeded ? "待选择" : snapshot.receiver.displayName,
            serviceCourt: snapshot.receiverChoiceNeeded ? "等待接发方选择" : (snapshot.serviceCourt == .deuce ? "右区 · Deuce court" : "左区 · Ad court"),
            homeIsNear: snapshot.homeEnd == .near,
            serverIsHome: snapshot.servingSide == .home,
            isDeuceCourt: snapshot.serviceCourt == .deuce,
            isPaused: store.isPaused,
            isFinished: finished || document.isAbandoned,
            needsReceiverChoice: snapshot.receiverChoiceNeeded,
            canUndo: !document.isAbandoned && !document.state.acceptedPointIDs.isEmpty,
            announcement: snapshot.lastAnnouncement
        )
    }

    private func historyStatus(_ document: MatchDocument) -> String {
        if document.snapshot.winner != nil { return "已完成" }
        return document.isAbandoned ? "已结束" : "可继续"
    }
}

@MainActor
struct WatchSettingsView: View {
    @ObservedObject var store: MatchStore

    var body: some View {
        NavigationStack {
            Form {
                Section("语音") {
                    Toggle("英文报分", isOn: $store.preferences.speechEnabled)
                    Toggle("语音记分", isOn: $store.preferences.voiceCommandsEnabled)
                    Toggle("报出名字", isOn: $store.preferences.includeNamesInSpeech)
                    Text("语音记分开启后，可通过 Siri 运行 CourtCall 的记分快捷指令。抬腕对话需在手表系统设置中开启。")
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.muted)
                    Text("关闭语音后，仍可全程点按记分。")
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.muted)
                    Text("本页开关仅作用于这块手表；iPhone 的播报和语音可独立设置。")
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.muted)
                    Button("试听英文播报") { store.speakPreview("Thirty–fifteen. Advantage Chen.") }
                }
                Section("提醒") {
                    Toggle("发球提醒", isOn: $store.preferences.serveRemindersEnabled)
                    Toggle("换边提醒", isOn: $store.preferences.changeoverRemindersEnabled)
                    Toggle("补水提醒", isOn: $store.preferences.hydrationRemindersEnabled)
                }
                Section("抬腕继续记分") {
                    Text("在手表“设置 → 通用 → 返回表盘”中，为 CourtCall 选择“一小时后”。落腕不需要结束比赛。")
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.muted)
                    Text("\(store.connectionStatus)")
                        .font(.caption2)
                }
            }
            .navigationTitle("设置")
        }
    }
}

@MainActor
struct WatchNewMatchView: View {
    @ObservedObject var store: MatchStore
    var onStarted: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = MatchConfiguration()
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section("比赛类型") {
                Picker("类型", selection: $configuration.kind) {
                    Text("单打").tag(MatchKind.singles)
                    Text("双打").tag(MatchKind.doubles)
                }
            }
            Section("双方名字") {
                TextField("我方球员", text: playerName(.home, 0))
                if configuration.kind == .doubles {
                    TextField("我方搭档", text: playerName(.home, 1))
                }
                TextField("对方球员", text: playerName(.away, 0))
                if configuration.kind == .doubles {
                    TextField("对方搭档", text: playerName(.away, 1))
                }
            }
            Section("赛制") {
                Picker("整场", selection: $configuration.bestOf) {
                    Text("一盘定胜负").tag(1)
                    Text("三盘两胜").tag(3)
                    Text("五盘三胜").tag(5)
                }
                Picker("每盘目标局数", selection: $configuration.gamesToWinSet) {
                    Text("2 局").tag(2)
                    Text("4 局").tag(4)
                    Text("6 局").tag(6)
                }
                Picker("平分规则", selection: $configuration.gameScoring) {
                    Text("占先 · Ad").tag(GameScoring.advantage)
                    Text("一分决胜 · No-Ad").tag(GameScoring.noAd)
                }
                Text("每盘需领先两局，2–2／4–4／6–6 抢七。多盘赛平盘后直接抢十。")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.muted)
            }
            Section("首发与场地") {
                Picker("先发球队", selection: $configuration.firstServingSide) {
                    Text("我方").tag(Side.home)
                    Text("对方").tag(Side.away)
                }
                if configuration.kind == .doubles {
                    indexPicker("我方首发", selection: $configuration.homeFirstServer, side: .home)
                    indexPicker("对方首发", selection: $configuration.awayFirstServer, side: .away)
                    indexPicker("我方右区接发", selection: $configuration.homeDeuceReceiver, side: .home)
                    indexPicker("对方右区接发", selection: $configuration.awayDeuceReceiver, side: .away)
                }
                Picker("我方起始位置", selection: $configuration.initialHomeEnd) {
                    Text("球场图下端").tag(CourtEnd.near)
                    Text("球场图上端").tag(CourtEnd.far)
                }
            }
            Section {
                Button("开始比赛") { startMatch() }
                    .foregroundStyle(WatchPalette.lime)
                Text("完整预设、英文播报名和更多设置也可在 iPhone 上完成。")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.muted)
            }
        }
        .navigationTitle("新建比赛")
        .onChange(of: configuration.kind) { _, kind in
            configuration.gameScoring = kind == .doubles ? .noAd : .advantage
        }
        .alert("请检查比赛设置", isPresented: Binding(get: { validationMessage != nil }, set: { if !$0 { validationMessage = nil } })) {
            Button("知道了") { validationMessage = nil }
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private func playerName(_ side: Side, _ index: Int) -> Binding<String> {
        Binding(
            get: { side == .home ? configuration.homePlayers[index].displayName : configuration.awayPlayers[index].displayName },
            set: { value in
                if side == .home {
                    configuration.homePlayers[index].displayName = value
                    configuration.homePlayers[index].spokenName = ""
                } else {
                    configuration.awayPlayers[index].displayName = value
                    configuration.awayPlayers[index].spokenName = ""
                }
            }
        )
    }

    private func indexPicker(_ title: String, selection: Binding<Int>, side: Side) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(configuration.players(for: side).enumerated()), id: \.offset) { index, player in
                Text(player.displayName).tag(index)
            }
        }
    }

    private func startMatch() {
        configuration.preset = .custom
        configuration.decidingMatchTiebreak = configuration.bestOf > 1
        do {
            try store.start(configuration: configuration)
            if let onStarted { onStarted() }
            else { dismiss() }
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

@MainActor
struct WatchMatchPicker: View {
    @ObservedObject var store: MatchStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        WatchNewMatchView(store: store, onStarted: { dismiss() })
                    } label: {
                        Label("新建比赛", systemImage: "plus")
                            .foregroundStyle(WatchPalette.lime)
                    }
                }
                Section("本机与已同步比赛") {
                    if store.documents.isEmpty {
                        Text("尚无比赛。在 iPhone 新建的比赛会在连接后同步。")
                            .font(.caption2)
                            .foregroundStyle(WatchPalette.muted)
                    }
                    ForEach(store.documents) { document in
                        Button {
                            store.resume(document)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text(document.configuration.teamName(for: .home))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if store.activeDocument?.id == document.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(WatchPalette.lime)
                                    }
                                }
                                Text("对 \(document.configuration.teamName(for: .away))")
                                    .lineLimit(1)
                                HStack {
                                    Text(document.createdAt, style: .date)
                                    Spacer(minLength: 0)
                                    Text(status(document))
                                }
                                .font(.caption2)
                                .foregroundStyle(WatchPalette.muted)
                            }
                            .font(.caption)
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("选择比赛")
        }
    }

    private func status(_ document: MatchDocument) -> String {
        if document.snapshot.winner != nil { return "已完成" }
        if document.isAbandoned { return "已结束" }
        return document.isPaused ? "已暂停" : "可继续"
    }
}

@MainActor
struct WatchLineupEditor: View {
    @ObservedObject var store: MatchStore
    let configuration: MatchConfiguration
    @State private var lineup: SetLineup
    @Environment(\.dismiss) private var dismiss

    init(store: MatchStore, configuration: MatchConfiguration, initial: SetLineup) {
        self.store = store
        self.configuration = configuration
        _lineup = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("本盘顺序") {
                    picker("我方先发", value: $lineup.homeFirstServer, side: .home)
                    picker("对方先发", value: $lineup.awayFirstServer, side: .away)
                    picker("我方右区接发", value: $lineup.homeDeuceReceiver, side: .home)
                    picker("对方右区接发", value: $lineup.awayDeuceReceiver, side: .away)
                }
                Section {
                    Button("保存顺序") {
                        store.changeLineup(lineup)
                        dismiss()
                    }
                    .foregroundStyle(WatchPalette.lime)
                    Text("仅在本盘尚未开始计分时可调整队内顺序。")
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.muted)
                }
            }
            .navigationTitle("发球与接发")
        }
    }

    private func picker(_ title: String, value: Binding<Int>, side: Side) -> some View {
        Picker(title, selection: value) {
            ForEach(Array(configuration.players(for: side).enumerated()), id: \.offset) { index, player in
                Text(player.displayName).tag(index)
            }
        }
    }
}
