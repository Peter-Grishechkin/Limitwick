import Foundation
import CoreGraphics

// Accessories on the Sessions mascots: they must not hide what a tile says (eyes, the Codex ">_", hands, crossed eyes)
// and must stay inside the 16 × 12 grid in every pose.

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: UInt = #line) {
    if !condition() { fatalError("FAILED (line \(line)): \(message)") }
}

@main struct SessionMascotTests {
    static func main() {
        let plain = SessionOutfit()
        // The cap is today's hat, pixel for pixel.
        check(SessionMascot.pose(.claude, look: SessionLook(), lookUp: false, outfit: plain).map { String($0) } == [
            "................", "................", ".....HHHHHH.....", "....HHHHHHHHHHH.",
            "..############..", "..##E######E##..", "..##E######E##..", "################",
            "..############..", "..############..", "...#.#....#.#...", "...#.#....#.#...",
        ], "Claude in a cap looks as before")
        check(SessionMascot.pose(.codex, look: SessionLook(), lookUp: false, outfit: plain).map { String($0) } == [
            ".........HHH....", "........HHHHH...", ".......######...", "...###.#######..",
            "..###E#########.", ".#####E#########", ".######E########", ".#####E#########",
            ".####E###EEE####", "..#############.", "...SSSSSSSSSSS..", "................",
        ], "Codex in a cap looks as before")

        let marks = Set(".#ESHhKkWBLgGR")
        let eyewearMarks = Set("LgGR")
        let poses: [(String, SessionLook)] = [
            ("rest", SessionLook()),
            ("working", SessionLook(lift: 1, bold: true)),
            ("left legs up", SessionLook(lift: 1, legs: .leftUp)),
            ("typing left", SessionLook(lift: 1, typing: .left)),
            ("typing right", SessionLook(lift: 1, typing: .right)),
            ("waving", SessionLook(lift: 1, armUp: true)),
            ("asleep", SessionLook(eyesClosed: true, awake: 0)),
            ("blink", SessionLook(lift: 1, cursor: false)),
            ("cursor 1", SessionLook(lift: 1, cursorShift: 1)),
            ("cursor 2", SessionLook(lift: 1, cursorShift: 2)),
            ("crossed", SessionLook(eyesClosed: true, awake: 0, crossed: true)),
            ("jump", SessionLook(lift: 2)),
            ("jump top", SessionLook(lift: 3)),
        ]
        // The z's of a long sleep in the frame's points (SessionHintView draws them 4 × 4 of 2 pt).
        let zeds = SessionMascot.zeds.map { CGRect(x: $0.x, y: $0.y, width: 8, height: 8) }

        // Claude and Codex start on one line: Claude's head (row 4) and the Codex bump (row 2), and their caps.
        for lift in 0...1 {
            check(SessionMascot.y(row: 4, lift: lift, provider: .claude) == SessionMascot.y(row: 2, lift: lift, provider: .codex), "heads on one line")
            let capTop = { (provider: SessionProvider) in
                SessionMascot.pose(provider, look: SessionLook(lift: lift), lookUp: false).firstIndex { $0.contains("H") }
                    .map { SessionMascot.y(row: $0, lift: lift, provider: provider) }
            }
            check(capTop(.claude) == capTop(.codex), "caps on one line")
        }

        for provider in [SessionProvider.claude, .codex] {
            for headwear in SessionOutfit.Headwear.allCases {
                for eyewear in SessionOutfit.Eyewear.allCases {
                    let outfit = SessionOutfit(headwear: headwear, eyewear: eyewear)
                    for (name, look) in poses {
                        for lookUp in [false, true] where !(lookUp && look.crossed) {
                            let rows = SessionMascot.pose(provider, look: look, lookUp: lookUp, outfit: outfit)
                            let what = "\(provider) \(headwear) \(eyewear) \(name)\(lookUp ? " looking up" : "")"
                            check(rows.count == 12 && rows.allSatisfy { $0.count == 16 }, "\(what): 16 × 12 grid")
                            check(rows.joined().allSatisfy(marks.contains), "\(what): every mark has a colour")
                            // Inside the frame in every pose; standing or resting, 2 pixels of air above the tallest hat.
                            for (y, row) in rows.enumerated() where row.contains(where: { $0 != "." }) {
                                let top = SessionMascot.y(row: y, lift: look.lift, provider: provider)
                                check(top >= 0 && top + 4 <= SessionMascot.frame.height, "\(what): row \(y) inside the frame")
                                if look.lift <= 1 { check(top >= 8, "\(what): row \(y) keeps off the top edge") }
                            }
                            let up = lookUp ? 1 : 0
                            if look.crossed {
                                // A failed turn knocks the eyewear off and keeps the crosses.
                                check(!rows.joined().contains(where: eyewearMarks.contains), "\(what): no eyewear on crossed eyes")
                                if provider == .claude {
                                    for (x, y) in [(3, 4), (5, 4), (4, 5), (3, 6), (5, 6), (10, 4), (12, 4), (11, 5), (10, 6), (12, 6)] {
                                        check(rows[y][x] == "E", "\(what): crossed eye at \(x),\(y)")
                                    }
                                } else {
                                    for (x, y) in [(9, 6), (11, 6), (10, 7), (9, 8), (11, 8)] { check(rows[y][x] == "E", "\(what): >x at \(x),\(y)") }
                                }
                                continue
                            }
                            if provider == .codex {
                                // ">" stays readable: dark on the cloud or lit in the shades.
                                for (x, y) in [(5, 4), (6, 5), (7, 6), (6, 7), (5, 8)] {
                                    check("EG".contains(rows[y - up][x]), "\(what): > at \(x),\(y - up)")
                                }
                                // "_" and its run to the right are never covered.
                                for x in 9...13 {
                                    let cursorHere = look.cursor && (9 + look.cursorShift...11 + look.cursorShift).contains(x)
                                    check(rows[8 - up][x] == (cursorHere ? "E" : "#"), "\(what): _ path at \(x),\(8 - up)")
                                }
                            } else {
                                // Hands and the waving arm keep their pixels.
                                if look.typing == .left { check(rows[6][0] == "#" && rows[6][1] == "#", "\(what): left hand") }
                                if look.typing == .right { check(rows[6][14] == "#" && rows[6][15] == "#", "\(what): right hand") }
                                if look.armUp { check(rows[5][15] == "#" && rows[6][14] == "#", "\(what): waving arm") }
                                // Without shades the open eyes show; the monocle keeps the eye inside its rim.
                                if eyewear != .sunglasses && !look.eyesClosed {
                                    check(rows[6 - up][4] == "E" && rows[6 - up][11] == "E", "\(what): eyes")
                                }
                                // Shades: the eyes peek over them under the pointer.
                                if eyewear == .sunglasses && lookUp { check(rows[4][4] == "E" && rows[4][11] == "E", "\(what): eyes over the shades") }
                            }
                            // Accessories stay off the z's of a long sleep.
                            if name == "asleep" && !lookUp {
                                for (y, row) in rows.enumerated() {
                                    for (x, mark) in row.enumerated() where !"#ES.".contains(mark) {
                                        let pixel = CGRect(x: CGFloat(x) * 4, y: SessionMascot.y(row: y, lift: 0, provider: provider), width: 4, height: 4)
                                        check(!zeds.contains { $0.insetBy(dx: 0.5, dy: 0.5).intersects(pixel) }, "\(what): \(mark) at \(x),\(y) under a z")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        print("Session mascot tests passed")
    }
}
