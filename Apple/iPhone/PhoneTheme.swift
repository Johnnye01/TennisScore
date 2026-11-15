import SwiftUI

enum CourtPalette {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.052)
    static let surface = Color(red: 0.075, green: 0.105, blue: 0.095)
    static let elevated = Color(red: 0.11, green: 0.145, blue: 0.125)
    static let lime = Color(red: 0.82, green: 0.97, blue: 0.36)
    static let secondary = Color(red: 0.61, green: 0.69, blue: 0.64)
    static let line = Color.white.opacity(0.10)
}

struct CourtPageBackground: View {
    var body: some View {
        CourtPalette.background
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(CourtPalette.lime.opacity(0.035))
                    .frame(width: 420, height: 420)
                    .blur(radius: 60)
                    .offset(x: 170, y: -190)
            }
            .ignoresSafeArea()
    }
}

struct CourtCard<Content: View>: View {
    var padding: CGFloat
    let content: Content

    init(padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CourtPalette.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(CourtPalette.line, lineWidth: 1)
            }
    }
}

struct CourtPrimaryButtonStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(destructive ? Color.white : CourtPalette.background)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 18)
            .background(destructive ? Color.red.opacity(0.78) : CourtPalette.lime,
                        in: RoundedRectangle(cornerRadius: 17))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct CourtSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 12)
            .background(CourtPalette.elevated, in: RoundedRectangle(cornerRadius: 15))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct CourtSectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
            if let subtitle {
                Text(subtitle).font(.footnote).foregroundStyle(CourtPalette.secondary)
            }
        }
    }
}

struct CourtTag: View {
    let text: String
    var highlighted = false
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(highlighted ? CourtPalette.lime : CourtPalette.secondary)
            .background(highlighted ? CourtPalette.lime.opacity(0.1) : CourtPalette.elevated,
                        in: Capsule())
    }
}

struct CourtChoice<Value: Hashable>: View {
    let title: String
    let options: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.white)
            HStack(spacing: 7) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button { selection = option.1 } label: {
                        Text(option.0)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 45)
                            .padding(.horizontal, 4)
                            .foregroundStyle(selection == option.1 ? CourtPalette.background : .white)
                            .background(selection == option.1 ? CourtPalette.lime : CourtPalette.elevated,
                                        in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option.1 ? .isSelected : [])
                }
            }
        }
    }
}

struct CourtTextField: View {
    let title: String
    var prompt = ""
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(CourtPalette.secondary)
            TextField(title, text: $text, prompt: Text(prompt).foregroundStyle(CourtPalette.secondary))
                .font(.body)
                .foregroundStyle(.white)
                .padding(13)
                .background(CourtPalette.elevated, in: RoundedRectangle(cornerRadius: 12))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }
}

/// A schematic for rules guidance, not a player-position sensor.
struct PhoneCourtDiagram: View {
    let homeName: String
    let awayName: String
    let homeNear: Bool
    let homeServing: Bool
    let servingRight: Bool
    var receiverName: String = ""

    private var servingNear: Bool { homeServing == homeNear }

    var body: some View {
        VStack(spacing: 10) {
            Text(homeNear ? awayName : homeName)
                .font(.caption.weight(.medium))
                .foregroundStyle(CourtPalette.secondary)
                .lineLimit(1)
            GeometryReader { proxy in
                let size = proxy.size
                let centerX = size.width / 2
                let centerY = size.height / 2
                let xFraction: CGFloat = servingRight ? 0.73 : 0.27
                let serveX = servingNear ? size.width * xFraction : size.width * (1 - xFraction)
                let serveY = servingNear ? size.height - 11 : 11
                let receiveX = size.width - serveX
                let receiveY = servingNear ? 21.0 : size.height - 21
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.10, green: 0.23, blue: 0.17))
                    Path { path in
                        path.addRect(CGRect(x: 10, y: 8, width: size.width - 20, height: size.height - 16))
                        path.move(to: CGPoint(x: 26, y: 8))
                        path.addLine(to: CGPoint(x: 26, y: size.height - 8))
                        path.move(to: CGPoint(x: size.width - 26, y: 8))
                        path.addLine(to: CGPoint(x: size.width - 26, y: size.height - 8))
                        path.move(to: CGPoint(x: 26, y: centerY - 30))
                        path.addLine(to: CGPoint(x: size.width - 26, y: centerY - 30))
                        path.move(to: CGPoint(x: 26, y: centerY + 30))
                        path.addLine(to: CGPoint(x: size.width - 26, y: centerY + 30))
                        path.move(to: CGPoint(x: centerX, y: centerY - 30))
                        path.addLine(to: CGPoint(x: centerX, y: centerY + 30))
                    }
                    .stroke(.white.opacity(0.43), lineWidth: 1)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: centerY))
                        path.addLine(to: CGPoint(x: size.width, y: centerY))
                    }
                    .stroke(.white.opacity(0.8), lineWidth: 2)
                    Path { path in
                        path.move(to: CGPoint(x: serveX, y: serveY))
                        path.addLine(to: CGPoint(x: receiveX, y: receiveY))
                    }
                    .stroke(CourtPalette.lime.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                    Circle()
                        .fill(CourtPalette.lime)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(CourtPalette.background, lineWidth: 3))
                        .position(x: serveX, y: serveY)
                    Circle()
                        .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                        .frame(width: 10, height: 10)
                        .position(x: receiveX, y: receiveY)
                }
            }
            .frame(height: 160)
            Text(homeNear ? homeName : awayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(CourtPalette.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("场地示意，\(homeName)在\(homeNear ? "近端" : "远端")，\(homeServing ? homeName : awayName)从\(servingRight ? "右区" : "左区")发球，\(receiverName)接发")
    }
}

extension View {
    func courtScreen() -> some View {
        self.background { CourtPageBackground() }
            .preferredColorScheme(.dark)
            .tint(CourtPalette.lime)
    }
}
