import SwiftUI

/// View data is deliberately separate from the scoring engine so the watch stays a
/// lightweight controller for the same persisted match used by the phone.
struct WatchScorePresentation {
    var homeName: String
    var awayName: String
    var homePoints: String
    var awayPoints: String
    var sets: String
    var games: String
    var phase: String
    var server: String
    var receiver: String
    var serviceCourt: String
    var homeIsNear: Bool
    var serverIsHome: Bool
    var isDeuceCourt: Bool
    var isPaused: Bool
    var isFinished: Bool
    var needsReceiverChoice: Bool
    var canUndo: Bool
    var announcement: String
}

enum WatchPalette {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.055)
    static let surface = Color(red: 0.09, green: 0.12, blue: 0.115)
    static let muted = Color(red: 0.62, green: 0.69, blue: 0.66)
    static let lime = Color(red: 0.83, green: 0.96, blue: 0.33)
    static let line = Color.white.opacity(0.18)
}

struct WatchScoreSurface: View {
    let match: WatchScorePresentation
    let scoreHome: () -> Void
    let scoreAway: () -> Void
    let undo: () -> Void
    let repeatScore: () -> Void
    let togglePause: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle()
                    .fill(match.isPaused ? WatchPalette.muted : WatchPalette.lime)
                    .frame(width: 5, height: 5)
                Text(match.isFinished ? "比赛结束" : (match.isPaused ? "已暂停" : match.phase))
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("盘 \(match.sets) · 局 \(match.games)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(WatchPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .center, spacing: 4) {
                playerScore(name: match.homeName, points: match.homePoints, isServing: match.serverIsHome)
                Text(":")
                    .font(.title2.weight(.light))
                    .foregroundStyle(WatchPalette.muted)
                    .padding(.top, 12)
                playerScore(name: match.awayName, points: match.awayPoints, isServing: !match.serverIsHome)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(match.homeName) \(match.homePoints)，\(match.awayName) \(match.awayPoints)。局数 \(match.games)，盘数 \(match.sets)")

            HStack(spacing: 6) {
                pointButton("我方 +1", isPrimary: true, action: scoreHome)
                pointButton("对方 +1", isPrimary: false, action: scoreAway)
            }
            .disabled(match.isPaused || match.isFinished || match.needsReceiverChoice)

            if !match.isFinished {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "tennisball.fill")
                            .font(.caption2)
                            .foregroundStyle(WatchPalette.lime)
                        Text("\(match.server) 发球")
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    Text(match.serviceCourt)
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.muted)
                    Text("接发：\(match.receiver)")
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.muted)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 12))

                if !match.needsReceiverChoice {
                    WatchCourtDiagram(
                        homeIsNear: match.homeIsNear,
                        serverIsHome: match.serverIsHome,
                        isDeuceCourt: match.isDeuceCourt
                    )
                    .frame(height: 74)
                    .accessibilityLabel("下一分从\(match.serviceCourt)发球。\(match.server)发球，\(match.receiver)接发。")
                }
            }

            HStack(spacing: 6) {
                Button(action: undo) {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                        .font(.caption2)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .disabled(!match.canUndo)
                Button(action: repeatScore) {
                    Label("报分", systemImage: "speaker.wave.2")
                        .font(.caption2)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
            }
            .buttonStyle(.bordered)

            if !match.isFinished {
                Button(action: togglePause) {
                    Label(match.isPaused ? "继续比赛" : "暂停比赛", systemImage: match.isPaused ? "play.fill" : "pause")
                        .font(.caption)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(WatchPalette.muted)
            }
        }
    }

    private func playerScore(name: String, points: String, isServing: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if isServing && !match.isFinished {
                    Circle().fill(WatchPalette.lime).frame(width: 4, height: 4)
                }
            }
            .foregroundStyle(WatchPalette.muted)
            Text(points)
                .font(.system(size: 43, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    private func pointButton(_ title: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(isPrimary ? WatchPalette.background : Color.white)
                .background(isPrimary ? WatchPalette.lime : WatchPalette.surface, in: RoundedRectangle(cornerRadius: 13))
                .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPrimary ? "我方得一分" : "对方得一分")
        .accessibilityHint("记分后可使用撤销恢复")
    }
}

struct WatchCourtDiagram: View {
    let homeIsNear: Bool
    let serverIsHome: Bool
    let isDeuceCourt: Bool

    var body: some View {
        Canvas { context, size in
            let court = CGRect(x: size.width * 0.17, y: 5, width: size.width * 0.66, height: size.height - 10)
            let left = court.minX
            let right = court.maxX
            let top = court.minY
            let bottom = court.maxY
            let midX = court.midX
            let midY = court.midY
            var outline = Path()
            outline.addRect(court)
            for x in [left + court.width * 0.125, right - court.width * 0.125] {
                outline.move(to: CGPoint(x: x, y: top))
                outline.addLine(to: CGPoint(x: x, y: bottom))
            }
            for y in [top + court.height * 0.27, bottom - court.height * 0.27] {
                outline.move(to: CGPoint(x: left + court.width * 0.125, y: y))
                outline.addLine(to: CGPoint(x: right - court.width * 0.125, y: y))
            }
            outline.move(to: CGPoint(x: midX, y: top + court.height * 0.27))
            outline.addLine(to: CGPoint(x: midX, y: bottom - court.height * 0.27))
            context.stroke(outline, with: .color(WatchPalette.line), lineWidth: 1)

            var net = Path()
            net.move(to: CGPoint(x: left - 5, y: midY))
            net.addLine(to: CGPoint(x: right + 5, y: midY))
            context.stroke(net, with: .color(Color.white.opacity(0.65)), lineWidth: 1.5)

            let serverNear = serverIsHome == homeIsNear
            let serveX: CGFloat = serverNear == isDeuceCourt ? 0.70 : 0.30
            let serverPoint = CGPoint(x: left + court.width * serveX, y: serverNear ? bottom - 3 : top + 3)
            let receiverPoint = CGPoint(x: left + court.width * (1 - serveX), y: serverNear ? top + 3 : bottom - 3)
            context.fill(Path(ellipseIn: CGRect(x: serverPoint.x - 4, y: serverPoint.y - 4, width: 8, height: 8)), with: .color(WatchPalette.lime))
            context.stroke(Path(ellipseIn: CGRect(x: receiverPoint.x - 3, y: receiverPoint.y - 3, width: 6, height: 6)), with: .color(WatchPalette.muted), lineWidth: 1.5)
        }
        .accessibilityElement(children: .ignore)
    }
}

struct WatchRestCard: View {
    let title: String
    let deadline: Date
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Label(title, systemImage: "drop.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(WatchPalette.lime)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let seconds = max(0, Int(ceil(deadline.timeIntervalSince(timeline.date))))
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
            Button("准备好了", action: dismiss)
                .font(.caption2)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct WatchNotice: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "arrow.left.arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WatchPalette.lime)
            if let detail, !detail.isEmpty {
                Text(detail).font(.caption2).foregroundStyle(WatchPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
