import SwiftUI

@MainActor
struct PhoneMatchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MatchStore
    @State private var confirmingEnd = false
    @State private var showingLineup = false
    @State private var lineupDraft = SetLineup()
    @State private var showCourt = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let document = store.activeDocument, let snapshot = store.snapshot {
                    matchContent(document: document, snapshot: snapshot)
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(CourtPalette.lime)
                        Text("比赛已保存").font(.title2.weight(.semibold)).foregroundStyle(.white)
                        Button("返回") { dismiss() }.buttonStyle(CourtPrimaryButtonStyle())
                    }
                    .padding(30)
                }
            }
            .courtScreen()
            .navigationTitle("记分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("返回首页，保留比赛")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.snapshot?.winner == nil {
                        Menu {
                            Button("返回首页，保留比赛", systemImage: "house") { dismiss() }
                            Button("提前结束并保存", systemImage: "flag.checkered", role: .destructive) { confirmingEnd = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("比赛选项")
                    }
                }
            }
            .confirmationDialog("提前结束本场比赛？", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("结束并保存当前比分", role: .destructive) {
                    store.endMatch()
                    dismiss()
                }
                Button("继续比赛", role: .cancel) { }
            } message: {
                Text("当前比分和已完成的盘会保留在比赛记录中。")
            }
            .sheet(isPresented: $showingLineup) {
                if let configuration = store.activeDocument?.configuration {
                    PhoneLineupView(configuration: configuration, lineup: $lineupDraft) {
                        store.changeLineup(lineupDraft)
                        showingLineup = false
                    }
                }
            }
            .alert("操作未完成", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.clearError() } })) {
                Button("知道了") { store.clearError() }
            } message: {
                Text(store.lastError ?? "请重试。")
            }
        }
    }

    @ViewBuilder
    private func matchContent(document: MatchDocument, snapshot: MatchSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CourtTag(text: phaseTitle(snapshot), highlighted: true)
                Spacer()
                if store.isPaused && snapshot.winner == nil {
                    Label("已暂停", systemImage: "pause.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text(document.configuration.kind == .doubles ? "双打" : "单打")
                        .font(.caption).foregroundStyle(CourtPalette.secondary)
                }
            }
            PhoneScoreboard(configuration: document.configuration, snapshot: snapshot)

            if let winner = snapshot.winner {
                CourtCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("\(document.configuration.teamName(for: winner)) 获胜", systemImage: "trophy.fill")
                            .font(.title2.weight(.semibold)).foregroundStyle(CourtPalette.lime)
                        Text(snapshot.lastAnnouncement)
                            .font(.subheadline).foregroundStyle(CourtPalette.secondary)
                        Button { store.undo() } label: {
                            Label("撤销最后一分", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(CourtSecondaryButtonStyle())
                        Button("完成，返回首页") {
                            store.endMatch()
                            dismiss()
                        }
                        .buttonStyle(CourtPrimaryButtonStyle())
                    }
                }
            } else {
                if snapshot.receiverChoiceNeeded {
                    receiverChoiceCard
                }
                HStack(spacing: 12) {
                    pointButton(.home, name: document.configuration.teamName(for: .home), disabled: store.isPaused || snapshot.receiverChoiceNeeded)
                    pointButton(.away, name: document.configuration.teamName(for: .away), disabled: store.isPaused || snapshot.receiverChoiceNeeded)
                }
                HStack(spacing: 8) {
                    Button { store.undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(CourtSecondaryButtonStyle())
                        .disabled(document.state.acceptedPointIDs.isEmpty)
                    Button { store.togglePause() } label: {
                        Label(store.isPaused ? "继续" : "暂停", systemImage: store.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(CourtSecondaryButtonStyle())
                    Button { store.repeatScore() } label: { Label("报分", systemImage: "speaker.wave.2") }
                        .buttonStyle(CourtSecondaryButtonStyle())
                }
                if store.isPaused {
                    Text("比赛已暂停。点“继续”后可继续手动或语音记分。")
                        .font(.footnote).foregroundStyle(CourtPalette.secondary)
                }
                nextServeCard(configuration: document.configuration, snapshot: snapshot)
            }

            if let reminder = store.activeReminder {
                PhoneReminderCard(reminder: reminder) { store.dismissReminder() }
            }
            if document.configuration.kind == .doubles && snapshot.canChangeLineup && snapshot.winner == nil {
                Button {
                    lineupDraft = snapshot.lineup
                    showingLineup = true
                } label: {
                    HStack {
                        Label("本盘发球与接发顺序", systemImage: "person.2")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(CourtSecondaryButtonStyle())
                .disabled(store.isPaused)
            }
            CourtCard(padding: 17) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $store.preferences.speechEnabled) {
                        Label("英文报分", systemImage: "speaker.wave.2")
                            .font(.subheadline)
                    }
                    Toggle(isOn: $store.preferences.voiceCommandsEnabled) {
                        Label("语音记分", systemImage: "waveform")
                            .font(.subheadline)
                    }
                    if store.preferences.voiceCommandsEnabled {
                        Text("可通过 Siri 运行 CourtCall 加分、撤销和报分指令。手动按钮始终可用。")
                            .font(.caption).foregroundStyle(CourtPalette.secondary)
                    }
                }
            }
            if snapshot.winner == nil && !snapshot.receiverChoiceNeeded {
                DisclosureGroup(isExpanded: $showCourt) {
                    PhoneCourtDiagram(homeName: document.configuration.teamName(for: .home),
                                      awayName: document.configuration.teamName(for: .away),
                                      homeNear: snapshot.homeEnd == .near,
                                      homeServing: snapshot.servingSide == .home,
                                      servingRight: snapshot.serviceCourt == .deuce,
                                      receiverName: snapshot.receiver.displayName)
                    .padding(.top, 16)
                } label: {
                    Label("发球与场地示意", systemImage: "rectangle.split.2x2")
                        .font(.subheadline).foregroundStyle(CourtPalette.secondary)
                }
                .padding(.horizontal, 8)
            }
            Text(store.connectionStatus).font(.caption).foregroundStyle(CourtPalette.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .padding(.bottom, 20)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private var receiverChoiceCard: some View {
        CourtCard(padding: 17) {
            VStack(alignment: .leading, spacing: 12) {
                Label("决胜分 · 接发方选择", systemImage: "arrow.left.arrow.right")
                    .font(.headline).foregroundStyle(CourtPalette.lime)
                Text("请按接发方的选择设置发球区，再记录这一分。")
                    .font(.footnote).foregroundStyle(CourtPalette.secondary)
                HStack(spacing: 10) {
                    Button("右区 Deuce") { store.chooseReceiver(.deuce) }
                    Button("左区 Ad") { store.chooseReceiver(.ad) }
                }
                .buttonStyle(CourtSecondaryButtonStyle())
                .disabled(store.isPaused)
            }
        }
    }

    private func pointButton(_ side: Side, name: String, disabled: Bool) -> some View {
        Button { store.score(side) } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(side == .home ? "我方得分" : "对方得分").font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "plus").font(.headline.weight(.semibold))
                }
                Text(name).font(.headline).lineLimit(2).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(17)
            .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
            .foregroundStyle(side == .home ? CourtPalette.background : Color.white)
            .background(side == .home ? CourtPalette.lime : CourtPalette.elevated,
                        in: RoundedRectangle(cornerRadius: 20))
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel("\(side == .home ? "我方" : "对方")，\(name)，加一分")
        .accessibilityHint("只记录这一分的获胜方；比分和发球轮换自动计算")
    }

    private func nextServeCard(configuration: MatchConfiguration, snapshot: MatchSnapshot) -> some View {
        CourtCard(padding: 17) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "tennis.racket").font(.title2).foregroundStyle(CourtPalette.lime)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("下一分 · \(snapshot.server.displayName) 发球")
                            .font(.headline).foregroundStyle(.white)
                        Text(snapshot.receiverChoiceNeeded ? "等待接发方选择发球区" : "\(snapshot.serviceCourt == .deuce ? "右区 · Deuce court" : "左区 · Ad court")  →  \(snapshot.receiver.displayName) 接发")
                            .font(.footnote).foregroundStyle(CourtPalette.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if !snapshot.lastAnnouncement.isEmpty {
                    Divider().overlay(CourtPalette.line)
                    Text(snapshot.lastAnnouncement)
                        .font(.footnote).foregroundStyle(CourtPalette.secondary)
                        .accessibilityLabel("上一条播报，\(snapshot.lastAnnouncement)")
                }
            }
        }
    }

    private func phaseTitle(_ snapshot: MatchSnapshot) -> String {
        switch snapshot.phase {
        case .regular: return "第 \(snapshot.setNumber) 盘"
        case .setTiebreak: return "第 \(snapshot.setNumber) 盘 · 抢七"
        case .matchTiebreak: return "决胜抢十"
        case .finished: return "MATCH COMPLETE"
        }
    }
}

struct PhoneScoreboard: View {
    let configuration: MatchConfiguration
    let snapshot: MatchSnapshot

    var body: some View {
        CourtCard {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("SCORE").font(.caption.weight(.medium)).tracking(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("盘").frame(width: 28)
                    Text("局").frame(width: 28)
                    Text(snapshot.isTiebreak ? "抢分" : "分").frame(width: 64)
                }
                .font(.caption).foregroundStyle(CourtPalette.secondary)
                ForEach([Side.home, Side.away], id: \.rawValue) { side in
                    HStack(spacing: 8) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(snapshot.servingSide == side && snapshot.winner == nil ? CourtPalette.lime : Color.clear)
                                .frame(width: 6, height: 6)
                            Text(configuration.teamName(for: side))
                                .font(.headline).lineLimit(2).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(snapshot.setsWon[side.index])")
                            .font(.system(.title3, design: .rounded, weight: .medium)).frame(width: 28)
                        Text("\(snapshot.games[side.index])")
                            .font(.system(.title3, design: .rounded, weight: .medium)).frame(width: 28)
                        Text(snapshot.pointLabels[side.index])
                            .font(.system(size: 45, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.55).lineLimit(1).frame(width: 64)
                            .foregroundStyle(CourtPalette.lime)
                    }
                    .foregroundStyle(.white).monospacedDigit()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(configuration.teamName(for: side))，\(snapshot.setsWon[side.index])盘，\(snapshot.games[side.index])局，\(snapshot.pointLabels[side.index])分\(snapshot.servingSide == side && snapshot.winner == nil ? "，发球方" : "")")
                    if side == .home { Divider().overlay(CourtPalette.line) }
                }
                if !snapshot.completedSets.isEmpty {
                    HStack(alignment: .top, spacing: 7) {
                        Text("已完成").foregroundStyle(CourtPalette.secondary)
                        Text(snapshot.completedSets.map(\.display).joined(separator: "  ·  "))
                            .foregroundStyle(.white.opacity(0.8)).monospacedDigit()
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 3)
                }
            }
        }
    }
}

struct PhoneReminderCard: View {
    let reminder: MatchReminder
    let dismiss: () -> Void

    var body: some View {
        CourtCard(padding: 17) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(reminder.title, systemImage: reminder.restUntil == nil ? "arrow.left.arrow.right" : "drop.fill")
                            .font(.headline).foregroundStyle(CourtPalette.lime)
                        Text(reminder.message).font(.footnote).foregroundStyle(CourtPalette.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(action: dismiss) { Image(systemName: "xmark.circle.fill").font(.title3) }
                        .foregroundStyle(CourtPalette.secondary)
                        .accessibilityLabel("关闭提醒")
                }
                if let restUntil = reminder.restUntil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(0, Int(ceil(restUntil.timeIntervalSince(context.date))))
                        HStack(alignment: .firstTextBaseline) {
                            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                                .monospacedDigit().foregroundStyle(.white)
                            Text(seconds > 0 ? "休息剩余" : "休息时间已到")
                                .font(.caption).foregroundStyle(CourtPalette.secondary)
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

struct PhoneLineupView: View {
    @Environment(\.dismiss) private var dismiss
    let configuration: MatchConfiguration
    @Binding var lineup: SetLineup
    let save: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("我方") {
                    picker("首位发球人", players: configuration.homePlayers, selection: $lineup.homeFirstServer)
                    picker("右区接发人", players: configuration.homePlayers, selection: $lineup.homeDeuceReceiver)
                }
                Section("对方") {
                    picker("首位发球人", players: configuration.awayPlayers, selection: $lineup.awayFirstServer)
                    picker("右区接发人", players: configuration.awayPlayers, selection: $lineup.awayDeuceReceiver)
                }
                Section {
                    Text("本盘开始前可以调整队内顺序。首先发球的队伍仍由比赛规则决定。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .courtScreen()
            .navigationTitle("本盘阵容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.semibold) }
            }
        }
    }

    private func picker(_ title: String, players: [PlayerProfile], selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<min(players.count, 2), id: \.self) { index in
                Text(players[index].displayName).tag(index)
            }
        }
    }
}
