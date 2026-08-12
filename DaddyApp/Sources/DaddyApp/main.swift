import SwiftUI
import DaddyCore

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        _ = scanner.scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Theme Namespace

enum DaddyTheme {
    // Accent & Brand
    static var accentBlue: Color { Color(hex: "#33ccff") }

    // State Colors
    static var workingGreen: Color { Color(hex: "#1aff99") }
    static var hexGreen: Color { Color(hex: "#5affaa") }
    static var amber: Color { Color(hex: "#ffc74d") }
    static var purple: Color { Color(hex: "#cc99ff") }
    static var errorRed: Color { Color(hex: "#ff7878") }
    static var errorRedLight: Color { Color(hex: "#ffb3b3") }

    // UI Colors
    static var tealLabel: Color { Color(hex: "#4de5cc") }
    static var terminalGreen: Color { Color(hex: "#00ff80") }
    static var terminalGreenDim: Color { Color(hex: "#8cffc8") }
    static var readyCheckCyan: Color { Color(hex: "#9fe6ff") }

    // Text Hierarchy
    static var textPrimary: Color { Color.white.opacity(0.9) }
    static var textSecondary: Color { Color.white.opacity(0.6) }
    static var textTertiary: Color { Color.white.opacity(0.35) }
    static var textMuted: Color { Color.white.opacity(0.3) }
    static var textVeryDim: Color { Color.white.opacity(0.15) }
}

// MARK: - Background Sky

struct BackgroundSky: View {
    @State private var orb1Offset = CGSize.zero
    @State private var orb2Offset = CGSize.zero
    @State private var orb3Offset = CGSize.zero
    @State private var orb1Scale: CGFloat = 1.0
    @State private var orb2Scale: CGFloat = 1.05
    @State private var orb3Scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(hex: "#0a1030"), location: 0.0),
                    .init(color: Color(hex: "#1a1046"), location: 0.45),
                    .init(color: Color(hex: "#07333f"), location: 1.0),
                ]),
                startPoint: .init(x: 0, y: 0),
                endPoint: .init(x: 1, y: 1)
            )

            // Orb 1: Blue top-left
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.31, green: 0.47, blue: 1.0).opacity(0.55),
                        Color(red: 0.31, green: 0.47, blue: 1.0).opacity(0.0)
                    ]),
                    center: .center,
                    startRadius: 100,
                    endRadius: 300
                ))
                .frame(width: 500, height: 500)
                .blur(radius: 40)
                .offset(orb1Offset)
                .scaleEffect(orb1Scale)

            // Orb 2: Teal bottom-right
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.0, green: 0.86, blue: 0.78).opacity(0.4),
                        Color(red: 0.0, green: 0.86, blue: 0.78).opacity(0.0)
                    ]),
                    center: .center,
                    startRadius: 80,
                    endRadius: 350
                ))
                .frame(width: 600, height: 600)
                .blur(radius: 50)
                .offset(orb2Offset)
                .scaleEffect(orb2Scale)

            // Orb 3: Purple mid-canvas (optional, subtle)
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.71, green: 0.31, blue: 1.0).opacity(0.38),
                        Color(red: 0.71, green: 0.31, blue: 1.0).opacity(0.0)
                    ]),
                    center: .center,
                    startRadius: 90,
                    endRadius: 320
                ))
                .frame(width: 550, height: 550)
                .blur(radius: 45)
                .offset(orb3Offset)
                .scaleEffect(orb3Scale)
        }
        .ignoresSafeArea()
        .onAppear {
            startOrbAnimation()
        }
    }

    private func startOrbAnimation() {
        withAnimation(.easeInOut(duration: 34).repeatForever(autoreverses: true)) {
            orb1Offset = CGSize(width: -30, height: 25)
            orb1Scale = 1.08
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 46).repeatForever(autoreverses: true)) {
                orb2Offset = CGSize(width: 35, height: -30)
                orb2Scale = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 52).repeatForever(autoreverses: true)) {
                orb3Offset = CGSize(width: -20, height: -20)
                orb3Scale = 1.05
            }
        }
    }
}

// MARK: - Glass Panel Modifier

struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.18), location: 0),
                                .init(color: Color.white.opacity(0), location: 1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomLeading
                        )
                    )
                    .frame(height: 1)
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Color.black.opacity(0.35), radius: 35, x: 0, y: 12)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 20, tint: Color = Color.white.opacity(0.07)) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

// MARK: - Glass Strip (header variant, no rounding/shadow)

struct GlassStripModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(alignment: .bottom) {
                Divider()
                    .background(Color.white.opacity(0.14))
            }
    }
}

extension View {
    func glassStrip() -> some View {
        modifier(GlassStripModifier())
    }
}

// MARK: - Glass Capsule/Pill

struct GlassCapsuleModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .fill(tint)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

extension View {
    func glassCapsule(tint: Color = Color.white.opacity(0.07)) -> some View {
        modifier(GlassCapsuleModifier(tint: tint))
    }
}

// MARK: - Breathing Dot

struct BreathingDot: View {
    let color: Color
    let glowRadius: CGFloat

    @State private var isBreathing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(0.8), radius: isBreathing ? glowRadius : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}

// MARK: - State Badge Colors Helper

struct StateColors {
    static func badge(for state: AgentState) -> (bg: Color, border: Color, text: Color, dot: Color?) {
        switch state {
        case .working:
            return (bg: DaddyTheme.workingGreen.opacity(0.14), border: DaddyTheme.workingGreen.opacity(0.35), text: DaddyTheme.workingGreen, dot: DaddyTheme.workingGreen)
        case .rateLimited:
            return (bg: DaddyTheme.amber.opacity(0.12), border: DaddyTheme.amber.opacity(0.3), text: DaddyTheme.amber, dot: nil)
        case .ready:
            return (bg: Color.white.opacity(0.07), border: Color.white.opacity(0.18), text: Color.white.opacity(0.8), dot: nil)
        case .error:
            return (bg: DaddyTheme.errorRed.opacity(0.15), border: DaddyTheme.errorRed.opacity(0.35), text: DaddyTheme.errorRed, dot: nil)
        case .launching:
            return (bg: DaddyTheme.accentBlue.opacity(0.15), border: DaddyTheme.accentBlue.opacity(0.35), text: DaddyTheme.accentBlue, dot: nil)
        case .exited:
            return (bg: Color.white.opacity(0.05), border: Color.white.opacity(0.1), text: Color.white.opacity(0.5), dot: nil)
        }
    }
}

@main
struct DaddyApp: App {
    @State private var sessionManager = SessionManager()
    @State private var sessions: [Session] = []
    @State private var selectedSessionID: String?

    var body: some Scene {
        WindowGroup {
            ZStack {
                // BACKGROUND: Dark sky with drifting orbs
                BackgroundSky()

                VStack(spacing: 0) {
                    // HEADER BAR - Glass strip
                    HStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Text("◆")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DaddyTheme.accentBlue)

                            Text("DADDY")
                                .font(.system(size: 15, weight: .bold, design: .default))
                                .tracking(0.5)
                                .foregroundColor(DaddyTheme.accentBlue)

                            Text("AI Command Center")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(DaddyTheme.textTertiary)
                        }
                        .padding(.leading, 78)

                        Spacer()

                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                BreathingDot(color: DaddyTheme.hexGreen, glowRadius: 8)

                                Text("HEX Ready")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DaddyTheme.hexGreen)

                                Text("double-click ⌥")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(DaddyTheme.hexGreen.opacity(0.7))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassCapsule(tint: DaddyTheme.hexGreen.opacity(0.1))

                            HStack(spacing: 6) {
                                Text("●")
                                    .font(.system(size: 9))
                                    .foregroundColor(DaddyTheme.accentBlue)

                                Text("\(sessions.count)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(DaddyTheme.textPrimary)

                                Text("sessions")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(DaddyTheme.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassCapsule(tint: Color.white.opacity(0.07))
                        }
                        .padding(.trailing, 22)
                    }
                    .padding(.vertical, 22)
                    .glassStrip()

                    // MAIN CONTENT
                    HStack(spacing: 16) {
                        ProjectsSidebar()
                            .frame(width: 264)

                        AgentDashboard(
                            sessions: sessions,
                            selectedSessionID: selectedSessionID,
                            onSelectSession: { selectedSessionID = $0 }
                        )

                        TerminalPane(
                            sessions: sessions,
                            selectedSessionID: selectedSessionID
                        )
                        .frame(width: 496)
                    }
                    .padding(16)
                }
            }
            .frame(minWidth: 1400, minHeight: 900)
            .onAppear { refreshSessions() }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                refreshSessions()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }

    private func refreshSessions() {
        sessions = sessionManager.getActiveSessions()
    }
}

// MARK: - Projects Sidebar
struct ProjectsSidebar: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("ACTIVE PROJECTS")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .tracking(0.6)
                        .foregroundColor(DaddyTheme.tealLabel)

                    Spacer()

                    Text("~/Documents")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(DaddyTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)

                Divider()
                    .background(DaddyTheme.textVeryDim)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ProjectRow(name: "daddysHome", isActive: true, sessionCount: 2)
                    ProjectRow(name: "hex-bridge", isActive: false, sessionCount: 1)
                    ProjectRow(name: "daddycore-spm", isActive: false, sessionCount: nil)
                    ProjectRow(name: "notes-sync", isActive: false, sessionCount: nil)
                    ProjectRow(name: "portfolio-site", isActive: false, sessionCount: nil)
                    ProjectRow(name: "tax-2026", isActive: false, sessionCount: nil)
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 0) {
                Divider()
                    .background(DaddyTheme.textVeryDim)

                VStack(alignment: .leading, spacing: 6) {
                    Text("FOCUS")
                        .font(.system(size: 9, weight: .medium, design: .default))
                        .tracking(0.6)
                        .foregroundColor(DaddyTheme.textTertiary)

                    Text("daddysHome › work")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DaddyTheme.textMuted)
                }
                .padding(12)
            }
        }
        .glassPanel(cornerRadius: 20)
    }
}

struct ProjectRow: View {
    let name: String
    let isActive: Bool
    let sessionCount: Int?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isActive ? DaddyTheme.workingGreen : DaddyTheme.textVeryDim)
                .frame(width: 6, height: 6)

            Text(name)
                .font(.system(size: 12.5, weight: isActive ? .medium : .regular))
                .foregroundColor(isActive ? DaddyTheme.workingGreen : DaddyTheme.textSecondary)

            Spacer()

            if let count = sessionCount {
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(isActive ? DaddyTheme.workingGreen : DaddyTheme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isActive ? DaddyTheme.workingGreen.opacity(0.15) : Color.white.opacity(0.06))
                    .cornerRadius(6)
            }
        }
        .padding(9)
        .padding(.horizontal, 2)
        .background(
            isActive
                ? DaddyTheme.workingGreen.opacity(0.08)
                : Color.clear
        )
        .border(
            isActive
                ? DaddyTheme.workingGreen.opacity(0.25)
                : Color.clear,
            width: 1
        )
        .cornerRadius(12)
    }
}

// MARK: - Agent Dashboard
struct AgentDashboard: View {
    let sessions: [Session]
    let selectedSessionID: String?
    let onSelectSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ACTIVE AGENTS")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .tracking(0.6)
                    .foregroundColor(DaddyTheme.workingGreen)

                Spacer()

                Text("refresh 1s")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(DaddyTheme.textSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .border(DaddyTheme.textVeryDim, width: 0.5)

            ScrollView {
                VStack(spacing: 12) {
                    if sessions.isEmpty {
                        VStack(spacing: 8) {
                            Text("No active sessions")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(DaddyTheme.textSecondary)

                            Text("Speak to Daddy or launch an agent")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(DaddyTheme.textSecondary.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    } else {
                        ForEach(sessions, id: \.id) { session in
                            AgentCardView(
                                session: session,
                                isSelected: selectedSessionID == session.id,
                                onTap: { onSelectSession(session.id) }
                            )
                        }
                    }
                }
                .padding(16)
            }
        }
        .glassPanel(cornerRadius: 20)
    }
}

struct AgentCardView: View {
    let session: Session
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Text("▸")
                    .font(.system(size: 10))
                    .foregroundColor(DaddyTheme.workingGreen)

                Text(session.agent.rawValue.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .default))
                    .tracking(1.0)
                    .foregroundColor(DaddyTheme.workingGreen)

                Spacer()

                StatusBadge(state: session.state)
            }

            VStack(alignment: .leading, spacing: 7) {
                MetricRow(label: "project", value: session.projectID, color: .default)
                MetricRow(label: "model", value: session.model?.rawValue ?? "default", color: .green)
                MetricRow(label: "work", value: session.workUnitID, color: .purple)
            }

            HStack {
                Spacer()
                Text("last output · \(formatTimeAgo(session.lastOutputAt))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(DaddyTheme.textTertiary)
            }
        }
        .padding(15)
        .background(
            isSelected
                ? DaddyTheme.accentBlue.opacity(0.12)
                : Color.white.opacity(0.04)
        )
        .border(
            isSelected
                ? DaddyTheme.accentBlue.opacity(0.5)
                : Color.white.opacity(0.10),
            width: isSelected ? 2 : 1
        )
        .cornerRadius(16)
        .shadow(color: isSelected ? DaddyTheme.accentBlue.opacity(0.3) : .clear, radius: 12, x: 0, y: 4)
        .onTapGesture { onTap() }
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "now" }
        else if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        else { return "\(Int(elapsed / 3600))h" }
    }
}

struct StatusBadge: View {
    let state: AgentState

    var body: some View {
        let colors = StateColors.badge(for: state)

        HStack(spacing: 8) {
            if let dotColor = colors.dot {
                BreathingDot(color: dotColor, glowRadius: 8)
            } else {
                stateGlyph()
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(colors.text)
            }

            Text(stateName)
                .font(.system(size: 9, weight: .semibold, design: .default))
                .tracking(0.7)
                .foregroundColor(colors.text)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(colors.bg)
        .border(colors.border, width: 1)
        .cornerRadius(999)
    }

    @ViewBuilder
    func stateGlyph() -> some View {
        switch state {
        case .ready:
            Text("✓")
                .foregroundColor(DaddyTheme.readyCheckCyan)
        case .rateLimited:
            Text("⏸")
        case .error:
            Text("✗")
        default:
            EmptyView()
        }
    }

    var stateName: String {
        switch state {
        case .working: return "WORKING"
        case .rateLimited: return "RATE-LIMITED"
        case .ready: return "READY"
        case .error: return "ERROR"
        case .launching: return "LAUNCHING"
        case .exited: return "EXITED"
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    let color: ColorScheme

    enum ColorScheme {
        case `default`, green, purple

        var color: Color {
            switch self {
            case .default: return DaddyTheme.textSecondary
            case .green: return DaddyTheme.workingGreen
            case .purple: return DaddyTheme.purple
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(DaddyTheme.textTertiary)
                .frame(width: 52, alignment: .leading)

            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(color.color)
        }
    }
}

// MARK: - Terminal Pane
struct TerminalPane: View {
    let sessions: [Session]
    let selectedSessionID: String?

    var selectedSession: Session? {
        sessions.first { $0.id == selectedSessionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LIVE OUTPUT")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .tracking(0.6)
                    .foregroundColor(DaddyTheme.tealLabel)

                Spacer()

                if let session = selectedSession {
                    Text("\(session.agent.rawValue) · \(session.projectID)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(DaddyTheme.terminalGreenDim.opacity(0.6))
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
            .border(DaddyTheme.workingGreen.opacity(0.14), width: 0.5)

            if let session = selectedSession {
                VStack(alignment: .leading, spacing: 5) {
                    Text("$ \(session.agent.rawValue.lowercased()) --permission-mode acceptEdits --model \(session.model?.rawValue ?? "default")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DaddyTheme.terminalGreen)

                    Text("─────────────────────────────────")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DaddyTheme.terminalGreen.opacity(0.5))

                    Text("> working on \(session.workUnitID)…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DaddyTheme.terminalGreen)

                    Text("· Reading sources…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DaddyTheme.terminalGreenDim.opacity(0.7))

                    Spacer()

                    HStack(spacing: 6) {
                        Text(">")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(DaddyTheme.terminalGreen.opacity(0.6))

                        Text("█")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(DaddyTheme.terminalGreen)
                            .opacity(0.9)
                    }
                }
                .padding(17)
            } else {
                VStack {
                    Text("Select an agent to view output")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(DaddyTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 10) {
                Text("›")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(DaddyTheme.terminalGreen.opacity(0.6))

                Text("type to send into session…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(DaddyTheme.textSecondary)

                Spacer()

                Text("esc interrupt")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DaddyTheme.errorRedLight)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(DaddyTheme.errorRed.opacity(0.15))
                    .border(DaddyTheme.errorRed.opacity(0.35), width: 1)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .border(DaddyTheme.workingGreen.opacity(0.14), width: 0.5)
        }
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(DaddyTheme.workingGreen.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.35), radius: 35, x: 0, y: 12)
    }
}
