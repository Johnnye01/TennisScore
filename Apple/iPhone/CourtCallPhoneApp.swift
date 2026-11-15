import SwiftUI

@main
@MainActor
struct CourtCallPhoneApp: App {
    @StateObject private var store = MatchStore.shared

    var body: some Scene {
        WindowGroup {
            PhoneRootView(store: store)
        }
    }
}

@MainActor
struct PhoneRootView: View {
    @ObservedObject var store: MatchStore
    @State private var showingSetup = false
    @State private var showingMatch = false
    @State private var openMatchAfterSetup = false

    var body: some View {
        TabView {
            NavigationStack {
                PhoneHomeView(store: store, newMatch: { showingSetup = true }, resume: {
                    if let match = store.activeDocument { store.resume(match) }
                    showingMatch = true
                })
            }
            .tabItem { Label("上场", systemImage: "tennisball.fill") }
            NavigationStack {
                PhoneHistoryView(store: store, openMatch: { document in
                    store.resume(document)
                    showingMatch = true
                })
            }
            .tabItem { Label("比赛", systemImage: "clock.arrow.circlepath") }
            NavigationStack { PhoneSettingsView(store: store) }
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .tint(CourtPalette.lime)
        .preferredColorScheme(.dark)
        .toolbarBackground(CourtPalette.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $showingSetup, onDismiss: {
            if openMatchAfterSetup {
                openMatchAfterSetup = false
                showingMatch = true
            }
        }) {
            PhoneMatchSetupView(store: store) { openMatchAfterSetup = true }
        }
        .fullScreenCover(isPresented: $showingMatch) {
            PhoneMatchView(store: store)
        }
        .alert("操作未完成", isPresented: Binding(get: { store.lastError != nil && !showingSetup && !showingMatch }, set: { if !$0 { store.clearError() } })) {
            Button("知道了") { store.clearError() }
        } message: {
            Text(store.lastError ?? "请重试。")
        }
    }
}

@MainActor
struct PhoneHomeView: View {
    @ObservedObject var store: MatchStore
    let newMatch: () -> Void
    let resume: () -> Void

    private var recent: [MatchDocument] { Array(store.documents.prefix(3)) }
    private var live: MatchDocument? {
        guard let match = store.activeDocument, match.snapshot.winner == nil, !match.isAbandoned else { return nil }
        return match
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 9) {
                    Image(systemName: "tennisball.fill").foregroundStyle(CourtPalette.lime)
                    Text("COURTCALL").font(.system(.headline, design: .rounded, weight: .semibold)).tracking(3)
                    Spacer()
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .foregroundStyle(CourtPalette.secondary)
                        .accessibilityLabel(store.connectionStatus)
                }
                .padding(.top, 12)
                VStack(alignment: .leading, spacing: 14) {
                    CourtTag(text: "YOUR COURT. EVERY POINT.", highlighted: true)
                    Text("把注意力\n留给下一球。")
                        .font(.system(size: 41, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("抬腕记分，听见每一分。")
                        .font(.body).foregroundStyle(CourtPalette.secondary)
                }
                if let live {
                    Button(action: resume) {
                        CourtCard {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Circle().fill(CourtPalette.lime).frame(width: 6, height: 6)
                                        Text(live.isPaused ? "比赛已暂停" : "比赛进行中")
                                            .font(.caption.weight(.medium)).foregroundStyle(CourtPalette.lime)
                                    }
                                    Spacer()
                                    Text(live.createdAt, style: .date).font(.caption).foregroundStyle(CourtPalette.secondary)
                                }
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 9) {
                                        Text(live.configuration.teamName(for: .home)).lineLimit(1)
                                        Text(live.configuration.teamName(for: .away)).lineLimit(1)
                                    }
                                    .font(.headline).foregroundStyle(.white)
                                    Spacer()
                                    VStack(spacing: 9) {
                                        Text(live.snapshot.pointLabels[0])
                                        Text(live.snapshot.pointLabels[1])
                                    }
                                    .font(.system(.title2, design: .rounded, weight: .semibold))
                                    .monospacedDigit().foregroundStyle(CourtPalette.lime)
                                }
                                HStack {
                                    Text("继续记分").font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                                .foregroundStyle(CourtPalette.lime)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("继续当前比赛")
                }
                Button(action: newMatch) {
                    Label("开始新比赛", systemImage: "plus")
                }
                .buttonStyle(CourtPrimaryButtonStyle())
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "applewatch").font(.title2).foregroundStyle(CourtPalette.lime)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("手机留在场边").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text("手表可独立手动记分，恢复连接后同步。语音输入和英文报分都由你选择。")
                            .font(.footnote).foregroundStyle(CourtPalette.secondary)
                    }
                }
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        CourtSectionTitle(title: "最近的比赛")
                        ForEach(recent) { match in
                            NavigationLink {
                                PhoneMatchDetailView(document: match)
                            } label: {
                                PhoneHistoryRow(document: match)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text(store.connectionStatus)
                    .font(.caption).foregroundStyle(CourtPalette.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(22)
            .padding(.bottom, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .courtScreen()
        .toolbar(.hidden, for: .navigationBar)
    }
}

@MainActor
struct PhoneHistoryView: View {
    @ObservedObject var store: MatchStore
    let openMatch: (MatchDocument) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("每一场，都有记录。")
                    .font(.title2.weight(.semibold)).foregroundStyle(.white)
                if store.documents.isEmpty {
                    CourtCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "tennisball").font(.largeTitle).foregroundStyle(CourtPalette.lime)
                            Text("第一场比赛，等你开场。")
                                .font(.headline).foregroundStyle(.white)
                            Text("完成或提前结束的比赛都会保存在这里。")
                                .font(.subheadline).foregroundStyle(CourtPalette.secondary)
                        }
                        .padding(.vertical, 15)
                    }
                } else {
                    ForEach(store.documents) { match in
                        NavigationLink {
                            PhoneMatchDetailView(document: match)
                        } label: {
                            PhoneHistoryRow(document: match)
                        }
                        .buttonStyle(.plain)
                        if !match.isAbandoned && match.snapshot.winner == nil {
                            Button { openMatch(match) } label: {
                                Label("继续这场比赛", systemImage: "play.fill")
                            }
                            .buttonStyle(CourtSecondaryButtonStyle())
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("比赛记录")
        .courtScreen()
    }
}

struct PhoneHistoryRow: View {
    let document: MatchDocument
    private var result: String {
        if let winner = document.snapshot.winner {
            return "\(document.configuration.teamName(for: winner)) 获胜"
        }
        return document.isAbandoned ? "提前结束" : document.isPaused ? "已暂停" : "进行中"
    }

    var body: some View {
        CourtCard(padding: 17) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(document.configuration.kind == .doubles ? "双打" : "单打")
                    Text("·")
                    Text(document.createdAt, style: .date)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.caption).foregroundStyle(CourtPalette.secondary)
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(document.configuration.teamName(for: .home))
                        Text(document.configuration.teamName(for: .away))
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    VStack(spacing: 7) {
                        Text("\(document.snapshot.setsWon[0])")
                        Text("\(document.snapshot.setsWon[1])")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit().foregroundStyle(CourtPalette.lime)
                }
                Text(result).font(.caption).foregroundStyle(CourtPalette.secondary)
            }
        }
    }
}

struct PhoneMatchDetailView: View {
    let document: MatchDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    CourtTag(text: document.configuration.kind == .doubles ? "DOUBLES" : "SINGLES", highlighted: true)
                    Spacer()
                    Text(document.createdAt, style: .date).font(.caption).foregroundStyle(CourtPalette.secondary)
                }
                Text(document.snapshot.winner.map { "\(document.configuration.teamName(for: $0)) 获胜" } ?? (document.isAbandoned ? "比赛已保存" : "比赛进行中"))
                    .font(.largeTitle.weight(.semibold)).foregroundStyle(.white)
                PhoneScoreboard(configuration: document.configuration, snapshot: document.snapshot)
                CourtCard {
                    VStack(alignment: .leading, spacing: 14) {
                        CourtSectionTitle(title: "逐盘比分")
                        if document.snapshot.completedSets.isEmpty {
                            Text("尚未完成一盘").font(.subheadline).foregroundStyle(CourtPalette.secondary)
                        }
                        ForEach(Array(document.snapshot.completedSets.enumerated()), id: \.offset) { index, set in
                            HStack {
                                Text(set.isMatchTiebreak ? "决胜抢十" : "第 \(index + 1) 盘")
                                    .foregroundStyle(CourtPalette.secondary)
                                Spacer()
                                Text(set.display).font(.system(.headline, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                            }
                        }
                    }
                }
                Text("\(document.configuration.bestOf) 盘制 · 每盘目标 \(document.configuration.gamesToWinSet) 局 · \(document.configuration.gameScoring == .advantage ? "占先制" : "无占先制")")
                    .font(.footnote).foregroundStyle(CourtPalette.secondary)
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("比赛详情")
        .navigationBarTitleDisplayMode(.inline)
        .courtScreen()
    }
}
