import SwiftUI
import AppKit

// Sessions window: a grid of tiles with pixel mascots, one dark style for now (not themed).
// What each tile shows at a given time comes from SessionLook (Sources/Sessions.swift); this file only draws it.

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
    // 16 × 12 pixels: # body, E face, H cap, S shade.
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
    /// The Codex cloud wears a terminal prompt ">_" for a face.
    static let codex = [
        ".........HHH....",
        "........HHHHH...",
        ".......######...",
        "...###.#######..",
        "..###E#########.",
        ".#####E#########",
        ".######E########",
        ".#####E#########",
        ".####E###EEE####",
        "..#############.",
        "...SSSSSSSSSSS..",
        "................",
    ]
    /// Cap colours tell sessions apart, for example two sessions in one folder.
    static let hats: [UInt32] = [0x5AB0E8, 0x7BC86C, 0xE8E8E8, 0x8E7CE0, 0xF2C94C, 0xE86FA0]
    // Hints beside the head, in 2 pt pixels.
    static let check = ["....#", "...#.", "#.#..", ".#..."]
    static let zed = ["####", "..#.", ".#..", "####"]
    static let alert = ["..#..", "..#..", "..#..", ".....", "..#.."]
    static let question = ["###..", "..#..", ".#...", ".....", ".#..."]
    /// Tool icons, 5 × 5: pencil, prompt, eye, magnifier, globe, little mascot, list, plug, gear.
    static let tools: [ToolKind: [String]] = [
        .edit: ["...##", "..##.", ".##..", "##...", "#...."],
        .shell: ["#....", ".#...", "#....", "..###", "....."],
        .read: [".....", ".###.", "#.#.#", ".###.", "....."],
        .search: ["###..", "#.#..", "###..", "...#.", "....#"],
        .web: [".###.", "#.#.#", "#####", "#.#.#", ".###."],
        .agent: [".###.", "#.#.#", "#####", ".#.#.", "....."],
        .plan: ["#.###", ".....", "#.###", ".....", "#.###"],
        .mcp: [".#.#.", ".#.#.", "#####", ".###.", "..#.."],
        .other: [".#.#.", "#####", "##.##", "#####", ".#.#."],
    ]

    /// The mascot grid for one frame: legs, a waving or typing hand, closed or crossed eyes, the Codex cursor,
    /// and eyes that look up at the pointer.
    static func pose(_ provider: SessionProvider, look: SessionLook, lookUp: Bool) -> [[Character]] {
        var rows = (provider == .claude ? claude : codex).map(Array.init)
        // A 3 × 3 cross of face pixels centred on (x, y), for the crossed eyes of a failed turn.
        func cross(_ x: Int, _ y: Int) {
            for dy in -1...1 { for dx in -1...1 { rows[y + dy][x + dx] = dx != 0 && dy != 0 || dx == 0 && dy == 0 ? "E" : "#" } }
        }
        if provider == .claude {
            if look.legs == .leftUp { rows[11][3] = "."; rows[11][5] = "." }
            if look.legs == .rightUp { rows[11][10] = "."; rows[11][12] = "." }
            if look.armUp { rows[5][15] = "#"; rows[6][14] = "#"; rows[7][14] = "."; rows[7][15] = "." }
            // Typing: the outer pixels of row 7 are the hands; one rises a pixel.
            if look.typing == .left { rows[6][0] = "#"; rows[6][1] = "#"; rows[7][0] = "."; rows[7][1] = "." }
            if look.typing == .right { rows[6][14] = "#"; rows[6][15] = "#"; rows[7][14] = "."; rows[7][15] = "." }
            if look.crossed { cross(4, 5); cross(11, 5) } else if look.eyesClosed && !lookUp { rows[5][4] = "#"; rows[5][11] = "#" }
        } else if look.crossed {
            // ">x": the cursor becomes a cross.
            for x in 9...11 { rows[8][x] = "#" }
            cross(10, 7)
        } else if !look.cursor || look.cursorShift > 0 {
            for x in 9...11 { rows[8][x] = "#" }
            if look.cursor { for x in 9...11 { rows[8][x + look.cursorShift] = "E" } }
        }
        if lookUp && !look.crossed {
            let face = rows.indices.flatMap { y in rows[y].indices.filter { rows[y][$0] == "E" }.map { (x: $0, y: y) } }
            for spot in face { rows[spot.y][spot.x] = "#" }
            for spot in face where spot.y > 0 { rows[spot.y - 1][spot.x] = "E" }
        }
        return rows
    }
    /// The order in which pixels show while a tile appears: a fixed scatter per session, 0..<1.
    static func order(_ x: Int, _ y: Int, _ seed: Int) -> Double {
        var hash = UInt32(truncatingIfNeeded: seed &* 31 &+ x &* 7919 &+ y &* 104_729)
        hash ^= hash >> 13; hash = hash &* 0x5BD1_E995; hash ^= hash >> 15
        return Double(hash % 1000) / 1000
    }
}

private extension Color {
    init(rgb: UInt32) { self.init(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255) }
    static let sessionOrange = Color(rgb: 0xF0702E)
    static let sessionGreen = Color(rgb: 0x5BD16B)
    static let sessionRed = Color(rgb: 0xEF4F4A)
}

struct SessionMascotView: View {
    let provider: SessionProvider
    let hat: Int
    var look = SessionLook()
    /// The pointer is over the tile: the eyes open and look up a pixel.
    var lookUp = false
    /// Scatters the pixels of an appearing tile differently for each session.
    var seed = 0
    var body: some View {
        let rows = SessionMascot.pose(provider, look: look, lookUp: lookUp)
        Canvas { context, _ in
            let pixel: CGFloat = 4
            for (y, row) in rows.enumerated() {
                for (x, mark) in row.enumerated() where mark != "." {
                    if look.reveal < 1 && SessionMascot.order(x, y, seed) >= look.reveal { continue }
                    let rect = CGRect(x: CGFloat(x) * pixel, y: CGFloat(y + 1 - look.lift) * pixel, width: pixel, height: pixel)
                    context.fill(Path(rect), with: .color(color(mark, awake: Self.dither[y % 2][x % 2] < look.awake)))
                }
            }
        }
        .frame(width: 64, height: 52)
        .accessibilityHidden(true)
    }
    /// Falling asleep greys the body through a 2 × 2 dither, like a pixel screen, instead of blending into brown.
    private static let dither = [[0.125, 0.625], [0.875, 0.375]]
    private func color(_ mark: Character, awake: Bool) -> Color {
        switch mark {
        case "H": return Color(rgb: SessionMascot.hats[hat % SessionMascot.hats.count])
        case "E": return Color(rgb: 0x1C1A19)
        case "S": return Color(rgb: provider == .codex ? (awake ? 0xB8C6DA : 0x6B737A) : (awake ? 0xC9531C : 0x7E878D))
        default: return Color(rgb: provider == .claude ? (awake ? 0xF0702E : 0xA3ACB2) : (awake ? 0xEEF2F8 : 0x8E979E))
        }
    }
}

/// Beside the mascot's head: the running tool, "!" after a tool error, a check right after a turn, z's while asleep, "?" when it went silent.
/// Drawn in the mascot's coordinates, right of the head and below the corner light: a 5 × 5 icon covers x 65–75, y 15–25.
private struct SessionHintView: View {
    let hint: SessionLook.Hint
    var body: some View {
        Canvas { context, _ in
            func sprite(_ rows: [String], at x: CGFloat, _ y: CGFloat, _ color: Color) {
                for (dy, row) in rows.enumerated() {
                    for (dx, mark) in row.enumerated() where mark != "." {
                        context.fill(Path(CGRect(x: x + CGFloat(dx) * 2, y: y + CGFloat(dy) * 2, width: 2, height: 2)), with: .color(color))
                    }
                }
            }
            switch hint {
            case .none: break
            case .check: sprite(SessionMascot.check, at: 65, 15, .sessionGreen)
            case .tool(let kind): sprite(SessionMascot.tools[kind] ?? [], at: 65, 15, Color(rgb: 0xB4B9C0))
            case .alert: sprite(SessionMascot.alert, at: 65, 15, .sessionRed)
            case .question: sprite(SessionMascot.question, at: 65, 15, Color(rgb: 0x5D6269))
            case .sleep(let depth):
                // One z under an hour, two under six hours, three after that; they rise up and away from the corner light.
                for (x, y) in [(66.0, 22.0), (60.0, 12.0), (54.0, 2.0)].prefix(depth) { sprite(SessionMascot.zed, at: x, y, Color(rgb: 0x5D6269)) }
            }
        }
        .frame(width: 80, height: 32)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
    /// Moves the stripes sideways one step at a time, like hazard tape.
    var stripes = 0
    var body: some View {
        if waiting {
            // Diagonal stripes mark a session that waits for you.
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(rgb: 0x1F1510)))
                var x = -size.height - 12 + CGFloat(stripes)
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
    var look = SessionLook()
    var hovered = false
    var lookUp = false
    var flash = false
    var body: some View {
        VStack(spacing: 3) {
            SessionMascotView(provider: session.provider, hat: SessionStore.hat(for: session.id, count: SessionMascot.hats.count),
                              look: look, lookUp: lookUp, seed: SessionStore.hat(for: session.id, count: 997))
                // The shake moves the mascot as a whole, so pixels at its edge are not cut off; the hint stays put.
                .offset(x: CGFloat(look.shake) * 4)
                .overlay(alignment: .topLeading) { SessionHintView(hint: look.hint) }
                .padding(.bottom, 3)
            // A Claude app title takes two lines: sessions in one folder differ only by it.
            // Every name keeps room for two lines, so mascots in a row stay level.
            Text(session.title ?? session.name)
                .font(.system(size: 11, weight: look.bold ? .semibold : .regular, design: .monospaced))
                .foregroundColor(look.bold ? .white : Color(rgb: 0xC9CCD1))
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
        .background(SessionTileBackground(waiting: session.state == .waiting, stripes: look.stripes))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: 1))
        .overlay(session.state == .working ? SessionCorner().stroke(Color.sessionOrange, lineWidth: 2) : nil)
        .overlay(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 1.5).fill(light).frame(width: 7, height: 7).padding(6)
        }
    }
    private var border: Color {
        if flash { return Color(rgb: 0xE6E8EB) }
        if session.state == .waiting { return .sessionOrange }
        return hovered ? Color(rgb: 0x4A4E54) : Color(rgb: 0x2A2C30)
    }
    private var light: Color {
        switch look.light {
        case .waiting: return .sessionOrange
        case .waitingDim: return Color(rgb: 0x6A3417)
        case .unseen: return .sessionGreen
        case .failed: return .sessionRed
        case .off: return Color(rgb: 0x3A3D42)
        }
    }
}

/// A tile as a button: its frame lights up under the pointer, it sinks a pixel while pressed and flashes once on click.
private struct SessionTileButton: View {
    let session: Session
    let now: TimeInterval
    let look: SessionLook
    let motion: Bool
    let open: (Session) -> Void
    // State values without the @State macro: the Command Line Tools that build the app have no SwiftUI macro plugin.
    private let hovered = State(initialValue: false)
    private let flash = State(initialValue: false)
    var body: some View {
        Button {
            // The flash confirms the click while the Claude app or the terminal comes forward.
            flash.wrappedValue = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { flash.wrappedValue = false }
            open(session)
        } label: {
            SessionTileView(session: session, now: now, look: look, hovered: hovered.wrappedValue, lookUp: hovered.wrappedValue && motion, flash: flash.wrappedValue)
        }
        .buttonStyle(SessionPressStyle())
        .onHover { hovered.wrappedValue = $0 }
    }
}

private struct SessionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .brightness(configuration.isPressed ? -0.05 : 0)
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

/// One clock for all tiles: 0.08 s steps while a moment plays, then the step SessionLook.clock picked.
struct SessionClock: TimelineSchedule {
    var fastUntil: TimeInterval
    var step: TimeInterval
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next = startDate
        let fastUntil = fastUntil, step = step
        return AnyIterator {
            let current = next
            next = current.addingTimeInterval(current.timeIntervalSince1970 < fastUntil ? SessionLook.fastTick : step)
            return current
        }
    }
}

struct SessionGridView: View {
    var sessions: [Session]
    var moments: [String: SessionMoment] = [:]
    /// The tool call each tile shows, from SessionStore.running.
    var running: [String: SessionTool] = [:]
    var limit = 16
    /// False while other windows cover the whole window: nothing moves and the clock keeps its idle step.
    var visible = true
    var open: (Session) -> Void = { _ in }
    var markAllSeen: () -> Void = {}
    var hide: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let shown = Array(sessions.prefix(limit))
        let motion = !reduceMotion && visible
        let clock = SessionLook.clock(shown, moments: moments, running: running, now: Date().timeIntervalSince1970, motion: motion)
        TimelineView(SessionClock(fastUntil: clock.fastUntil, step: clock.step)) { context in
            let now = context.date.timeIntervalSince1970
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(SessionGridLayout.tile.width), spacing: SessionGridLayout.gap), count: SessionGridLayout.columns),
                      alignment: .leading, spacing: SessionGridLayout.gap) {
                ForEach(shown, id: \.key) { session in
                    // The folder stays in the tooltip and for VoiceOver when the tile shows a title.
                    let words = [session.provider == .claude ? "Claude" : "Codex", session.name] + (session.title.map { [$0] } ?? [])
                    SessionTileButton(session: session, now: now,
                                      look: SessionLook.of(session, moment: moments[session.key], tool: running[session.key], now: now, motion: motion),
                                      motion: motion, open: open)
                        .help(words.joined(separator: " · "))
                        .accessibilityLabel((words + [SessionStore.spokenStatus(session, now: now)]).joined(separator: ", "))
                }
                // Empty slots keep the grid the same size, like the screen of a device.
                ForEach(shown.count..<max(shown.count, limit), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).fill(Color(rgb: 0x141518))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(rgb: 0x1E2023), lineWidth: 1))
                        .frame(width: SessionGridLayout.tile.width, height: SessionGridLayout.tile.height)
                        .accessibilityHidden(true)
                }
            }
            // A tile that changes place slides there, so the eye can follow it.
            .animation(motion ? .easeInOut(duration: 0.25) : nil, value: shown.map(\.key))
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
            .contextMenu {
                Button("Mark All as Seen", action: markAllSeen).disabled(!sessions.contains { $0.unseen != nil })
                Button("Hide Sessions", action: hide)
            }
        }
    }
}
