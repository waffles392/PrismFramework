/// a physical keyboard key represented by its SDL scancode
///
/// keys are identified by scancode (physical position), not by
/// the character they produce, so layouts and modifiers do not
/// change key identity. named keys cover the commonly used
/// portion of the keyboard; scancodes not named here are
/// retained as 'unknown', so the wrapper never loses input
public enum Key: Hashable, Sendable {
    case unknown(Int32)
    case escape, enter, tab, backspace, space
    case grave
    case left, right, up, down
    case leftShift, rightShift, leftControl, rightControl, leftAlt, rightAlt
    case leftGUI, rightGUI
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case digit0, digit1, digit2, digit3, digit4
    case digit5, digit6, digit7, digit8, digit9
    case F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12
    case capsLock, scrollLock, numLock
    case printScreen
    case insert, home, pageUp, delete, end, pageDown
    case application
    case numpad0, numpad1, numpad2, numpad3, numpad4
    case numpad5, numpad6, numpad7, numpad8, numpad9
    case numpadEnter, numpadDecimal

    public init(rawValue: Int32) {
        switch rawValue {
        case 4: self = .a
        case 5: self = .b
        case 6: self = .c
        case 7: self = .d
        case 8: self = .e
        case 9: self = .f
        case 10: self = .g
        case 11: self = .h
        case 12: self = .i
        case 13: self = .j
        case 14: self = .k
        case 15: self = .l
        case 16: self = .m
        case 17: self = .n
        case 18: self = .o
        case 19: self = .p
        case 20: self = .q
        case 21: self = .r
        case 22: self = .s
        case 23: self = .t
        case 24: self = .u
        case 25: self = .v
        case 26: self = .w
        case 27: self = .x
        case 28: self = .y
        case 29: self = .z
        case 30: self = .digit1
        case 31: self = .digit2
        case 32: self = .digit3
        case 33: self = .digit4
        case 34: self = .digit5
        case 35: self = .digit6
        case 36: self = .digit7
        case 37: self = .digit8
        case 38: self = .digit9
        case 39: self = .digit0
        case 40: self = .enter
        case 41: self = .escape
        case 42: self = .backspace
        case 43: self = .tab
        case 44: self = .space
        case 53: self = .grave
        case 57: self = .capsLock
        case 58: self = .F1
        case 59: self = .F2
        case 60: self = .F3
        case 61: self = .F4
        case 62: self = .F5
        case 63: self = .F6
        case 64: self = .F7
        case 65: self = .F8
        case 66: self = .F9
        case 67: self = .F10
        case 68: self = .F11
        case 69: self = .F12
        case 70: self = .printScreen
        case 71: self = .scrollLock
        case 73: self = .insert
        case 74: self = .home
        case 75: self = .pageUp
        case 76: self = .delete
        case 77: self = .end
        case 78: self = .pageDown
        case 79: self = .right
        case 80: self = .left
        case 81: self = .down
        case 82: self = .up
        case 83: self = .numLock
        case 88: self = .numpadEnter
        case 89: self = .numpad1
        case 90: self = .numpad2
        case 91: self = .numpad3
        case 92: self = .numpad4
        case 93: self = .numpad5
        case 94: self = .numpad6
        case 95: self = .numpad7
        case 96: self = .numpad8
        case 97: self = .numpad9
        case 98: self = .numpad0
        case 101: self = .application
        case 220: self = .numpadDecimal
        case 224: self = .leftControl
        case 225: self = .leftShift
        case 226: self = .leftAlt
        case 227: self = .leftGUI
        case 228: self = .rightControl
        case 229: self = .rightShift
        case 230: self = .rightAlt
        case 231: self = .rightGUI
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: Int32 {
        switch self {
        case .unknown(let value): value
        case .a: 4
        case .b: 5
        case .c: 6
        case .d: 7
        case .e: 8
        case .f: 9
        case .g: 10
        case .h: 11
        case .i: 12
        case .j: 13
        case .k: 14
        case .l: 15
        case .m: 16
        case .n: 17
        case .o: 18
        case .p: 19
        case .q: 20
        case .r: 21
        case .s: 22
        case .t: 23
        case .u: 24
        case .v: 25
        case .w: 26
        case .x: 27
        case .y: 28
        case .z: 29
        case .digit1: 30
        case .digit2: 31
        case .digit3: 32
        case .digit4: 33
        case .digit5: 34
        case .digit6: 35
        case .digit7: 36
        case .digit8: 37
        case .digit9: 38
        case .digit0: 39
        case .enter: 40
        case .escape: 41
        case .backspace: 42
        case .tab: 43
        case .space: 44
        case .grave: 53
        case .capsLock: 57
        case .F1: 58
        case .F2: 59
        case .F3: 60
        case .F4: 61
        case .F5: 62
        case .F6: 63
        case .F7: 64
        case .F8: 65
        case .F9: 66
        case .F10: 67
        case .F11: 68
        case .F12: 69
        case .printScreen: 70
        case .scrollLock: 71
        case .insert: 73
        case .home: 74
        case .pageUp: 75
        case .delete: 76
        case .end: 77
        case .pageDown: 78
        case .right: 79
        case .left: 80
        case .down: 81
        case .up: 82
        case .numLock: 83
        case .numpadEnter: 88
        case .numpad1: 89
        case .numpad2: 90
        case .numpad3: 91
        case .numpad4: 92
        case .numpad5: 93
        case .numpad6: 94
        case .numpad7: 95
        case .numpad8: 96
        case .numpad9: 97
        case .numpad0: 98
        case .application: 101
        case .numpadDecimal: 220
        case .leftControl: 224
        case .leftShift: 225
        case .leftAlt: 226
        case .leftGUI: 227
        case .rightControl: 228
        case .rightShift: 229
        case .rightAlt: 230
        case .rightGUI: 231
        }
    }

    public static func letter(_ letter: Character) -> Key? {
        switch letter.lowercased() {
        case "a": .a
        case "b": .b
        case "c": .c
        case "d": .d
        case "e": .e
        case "f": .f
        case "g": .g
        case "h": .h
        case "i": .i
        case "j": .j
        case "k": .k
        case "l": .l
        case "m": .m
        case "n": .n
        case "o": .o
        case "p": .p
        case "q": .q
        case "r": .r
        case "s": .s
        case "t": .t
        case "u": .u
        case "v": .v
        case "w": .w
        case "x": .x
        case "y": .y
        case "z": .z
        default: nil
        }
    }

    public static func digit(_ digit: Int) -> Key? {
        switch digit {
        case 0: .digit0
        case 1: .digit1
        case 2: .digit2
        case 3: .digit3
        case 4: .digit4
        case 5: .digit5
        case 6: .digit6
        case 7: .digit7
        case 8: .digit8
        case 9: .digit9
        default: nil
        }
    }

    public static func function(_ number: Int) -> Key? {
        switch number {
        case 1: .F1
        case 2: .F2
        case 3: .F3
        case 4: .F4
        case 5: .F5
        case 6: .F6
        case 7: .F7
        case 8: .F8
        case 9: .F9
        case 10: .F10
        case 11: .F11
        case 12: .F12
        default: nil
        }
    }
}
