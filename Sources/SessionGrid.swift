import SwiftUI
import AppKit

// Sessions window: a grid of tiles with pixel mascots, one dark style for now (not themed).

enum SessionGridLayout {
    static let columns = 4
    static let limits = [4, 8, 16]
    // Wide enough for "done · 11m ago" in 10 pt monospaced type.
    static let tile = CGSize(width: 100, height: 104)
    static let gap: CGFloat = 8
    static let padding: CGFloat = 12
    /// The window keeps one size per setting (4, 8 or 16 tiles), like the screen of a device.
    static func size(limit: Int) -> CGSize {
        let rows = max(1, (limit + columns - 1) / columns)
        return CGSize(width: padding * 2 + CGFloat(columns) * tile.width + CGFloat(columns - 1) * gap,
                      height: padding * 2 + CGFloat(rows) * tile.height + CGFloat(rows - 1) * gap)
    }
}

enum SessionMascot {
    // 16 × 12 pixels: # body, E eyes and mouth, H cap, S shade.
    static let claude = [
        "................",
        "................",
        ".....HHHHHH.....",
        "....HHHHHHHHHHH.",
        "..############..",
        "..##E######E##..",
        "..##E######E##..",
        "################",
        "..############..",
        "..############..",
        "...#.#....#.#...",
        "...#.#....#.#...",
    ]
    static let codex = [
        ".........HHH....",
        "........HHHHH...",
        ".......######...",
        "...###.#######..",
        "..#############.",
        ".###############",
        ".####E#####E####",
        ".####E#####E####",
        ".#####E###E#####",
        "..#####EEE#####.",
        "...SSSSSSSSSSS..",
        "................",
    ]
    /// Cap colours tell sessions apart, for example two sessions in one folder.
    static let hats: [UInt32] = [0x5AB0E8, 0x7BC86C, 0xE8E8E8, 0x8E7CE0, 0xF2C94C, 0xE86FA0]
}

private extension Color {
    init(rgb: UInt32) { self.init(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255) }
    static let sessionOrange = Color(rgb: 0xF0702E)
}

struct SessionMascotView: View {
    let provider: SessionProvider
    let active: Bool
    let hat: Int
    /// Working mascots bob one pixel; idle ones rest on the lower position.
    let raised: Bool
    var body: some View {
        Canvas { context, _ in
            let pixel: CGFloat = 4
            let grid = provider == .claude ? SessionMascot.claude : SessionMascot.codex
            for (y, row) in grid.enumerated() {
                for (x, mark) in row.enumerated() where mark != "." {
                    let rect = CGRect(x: CGFloat(x) * pixel, y: CGFloat(y + (raised ? 0 : 1)) * pixel, width: pixel, height: pixel)
                    context.fill(Path(rect), with: .color(color(mark)))
                }
            }
        }
        .frame(width: 64, height: 52)
        .accessibilityHidden(true)
    }
    private func color(_ mark: Character) -> Color {
        switch mark {
        case "H": return Color(rgb: SessionMascot.hats[hat % SessionMascot.hats.count])
        case "E": return Color(rgb: 0x1C1A19)
        case "S": return Color(rgb: provider == .codex ? (active ? 0xB8C6DA : 0x6B737A) : (active ? 0xC9531C : 0x7E878D))
        default: return Color(rgb: provider == .claude ? (active ? 0xF0702E : 0xA3ACB2) : (active ? 0xEEF2F8 : 0x8E979E))
        }
    }
}

/// Orange corner on working tiles, like the frame of a device screen.
private struct SessionCorner: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.6, y: 1))
        path.addLine(to: CGPoint(x: rect.width - 1, y: 1))
        path.addLine(to: CGPoint(x: rect.width - 1, y: rect.height * 0.55))
        return path
    }
}

private struct SessionTileBackground: View {
    let waiting: Bool
    var body: some View {
        if waiting {
            // Diagonal stripes mark a session that waits for you.
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(rgb: 0x1F1510)))
                var x = -size.height
                while x < size.width {
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: x, y: size.height)); stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(stripe, with: .color(Color(rgb: 0x33200F)), lineWidth: 6)
                    x += 12
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4).fill(Color(rgb: 0x18191C))
        }
    }
}

struct SessionTileView: View {
    let session: Session
    let now: TimeInterval
    let raised: Bool
    var body: some View {
        let active = session.state != .idle
        VStack(spacing: 3) {
            SessionMascotView(provider: session.provider, active: active,
                              hat: SessionStore.hat(for: session.id, count: SessionMascot.hats.count),
                              raised: session.state == .working && raised)
                .overlay(alignment: .topTrailing) {
                    // Beside the mascot's head, so it moves with the mascot.
                    if session.state == .idle {
                        Text("z z").font(.system(size: 9, design: .monospaced)).foregroundColor(Color(rgb: 0x5D6269))
                            .fixedSize().offset(x: 13, y: 13)
                    }
                }
                .padding(.bottom, 3)
            // A Claude app title takes two lines: sessions in one folder differ only by it.
            // Every name keeps room for two lines, so mascots in a row stay level.
            Text(session.title ?? session.name)
                .font(.system(size: 11, weight: active ? .semibold : .regular, design: .monospaced))
                .foregroundColor(active ? .white : Color(rgb: 0xC9CCD1))
                .lineLimit(session.title == nil ? 1 : 2).truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(height: 28)
            Text(SessionStore.status(session, now: now))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(session.state == .waiting ? .sessionOrange : Color(rgb: 0x7D828A))
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .frame(width: SessionGridLayout.tile.width, height: SessionGridLayout.tile.height)
        .background(SessionTileBackground(waiting: session.state == .waiting))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(session.state == .waiting ? Color.sessionOrange : Color(rgb: 0x2A2C30), lineWidth: 1))
        .overlay(session.state == .working ? SessionCorner().stroke(Color.sessionOrange, lineWidth: 2) : nil)
        .overlay(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 1.5).fill(session.state == .waiting ? Color.sessionOrange : Color(rgb: 0x3A3D42))
                .frame(width: 7, height: 7).padding(6)
        }
    }
}

/// Lets the borderless window be dragged by its background; tiles stay clickable.
private struct SessionWindowDrag: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The first click on a tile opens the session even when Limitwick is not the active app.
final class SessionsHostingView: NSHostingView<SessionGridView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct SessionGridView: View {
    var sessions: [Session]
    var limit = 16
    var open: (Session) -> Void = { _ in }
    var hide: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let shown = Array(sessions.prefix(limit))
        let animate = !reduceMotion && shown.contains { $0.state == .working }
        // One clock drives the bobbing and the "3m ago" texts; it slows down when nothing moves.
        TimelineView(.periodic(from: Date(), by: animate ? 0.32 : 20)) { context in
            let now = context.date.timeIntervalSince1970
            let raised = animate && Int(now / 0.32) % 2 == 0
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(SessionGridLayout.tile.width), spacing: SessionGridLayout.gap), count: SessionGridLayout.columns),
                      alignment: .leading, spacing: SessionGridLayout.gap) {
                ForEach(shown, id: \.key) { session in
                    // The folder stays in the tooltip and for VoiceOver when the tile shows a title.
                    let words = [session.provider == .claude ? "Claude" : "Codex", session.name] + (session.title.map { [$0] } ?? [])
                    Button { open(session) } label: { SessionTileView(session: session, now: now, raised: raised) }
                        .buttonStyle(.plain)
                        .help(words.joined(separator: " · "))
                        .accessibilityLabel((words + [SessionStore.status(session, now: now)]).joined(separator: ", "))
                }
                // Empty slots keep the grid the same size, like the screen of a device.
                ForEach(shown.count..<max(shown.count, limit), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).fill(Color(rgb: 0x141518))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(rgb: 0x1E2023), lineWidth: 1))
                        .frame(width: SessionGridLayout.tile.width, height: SessionGridLayout.tile.height)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if shown.isEmpty {
                    Text("Sessions from the last 24 hours appear here. They need the activity hooks from Settings.")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(Color(rgb: 0x7D828A))
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }
            }
            .padding(SessionGridLayout.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(SessionWindowDrag())
            .background(Color(rgb: 0x0F1012))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contextMenu { Button("Hide Sessions", action: hide) }
        }
    }
}
