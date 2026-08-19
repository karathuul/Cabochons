import Foundation
internal import SwiftUI

// MARK: - Jewel

/// A single tap. One jewel = one occurrence of the activity.
struct Jewel: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date
}

// MARK: - Activity

struct Activity: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var color: MateriaColor
    /// How many sockets the day has. Filling all of them masters the day.
    var dailyTarget: Int
    var jewels: [Jewel] = []
    var createdAt: Date = .now

    /// Newest first.
    var sortedJewels: [Jewel] {
        jewels.sorted { $0.timestamp > $1.timestamp }
    }
}

// MARK: - Palette

/// A jewel colour, stored as hue/saturation/brightness rather than RGB so a
/// single picked colour can generate the whole sphere — a bright rim and a
/// shadowed underside that stay recognisably the same hue.
///
/// Values are normalised on init so every gem reads against the socket. See
/// `normalised(_:)` for what that means and why it isn't a simple clamp.
struct MateriaColor: Codable, Hashable {
    /// All 0...1.
    let hue: Double
    let saturation: Double
    let brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        let wrapped = hue - floor(hue)
        let (h, s, b) = Self.normalised((
            wrapped,
            min(1, max(0, saturation)),
            min(1, max(0, brightness))
        ))
        self.hue = h
        self.saturation = s
        self.brightness = b
    }

    /// From a colour the user picked in a `ColorPicker`.
    init(red: Double, green: Double, blue: Double) {
        let (h, s, b) = Self.rgbToHSB(red, green, blue)
        self.init(hue: h, saturation: s, brightness: b)
    }

    // MARK: The three faces of the orb

    /// Bright centre.
    var core: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    /// Thin bright rim where the glass catches light.
    var rim: Color {
        Color(
            hue: hue,
            saturation: min(1, saturation * 0.48),
            brightness: min(1, brightness * 0.15 + 0.85)
        )
    }

    /// Shadowed lower edge, gives the sphere its volume.
    var deep: Color {
        Color(
            hue: hue,
            saturation: min(1, saturation * 1.25),
            brightness: brightness * 0.34
        )
    }

    // MARK: Readability

    /// Minimum contrast between a jewel and the empty socket behind it.
    private static let minContrast = 3.5

    /// Keeps a gem visible against gunmetal without hijacking the user's choice.
    ///
    /// Brightness is raised first, because that preserves the hue *and* the
    /// saturation someone actually asked for. Desaturating is the fallback,
    /// used only for hues that can't reach the threshold at any brightness —
    /// blues and violets are dim at full saturation no matter how bright you
    /// push them.
    ///
    /// Deliberately does NOT raise saturation: at saturation zero the hue is
    /// meaningless, so clamping it upward turns a white pick into a pink one.
    /// Greys and whites are left alone; they're legible already.
    private static func normalised(_ hsb: (Double, Double, Double)) -> (Double, Double, Double) {
        var (h, s, b) = hsb

        while b < 1, contrast(h, s, b) < minContrast {
            b = min(1, b + 0.01)
        }
        while s > 0, contrast(h, s, b) < minContrast {
            s = max(0, s - 0.01)
        }
        return (h, s, b)
    }

    private static func contrast(_ h: Double, _ s: Double, _ b: Double) -> Double {
        let jewel = luminance(of: hsbToRGB(h, s, b))
        let socket = 0.00570   // Chrome.socketVoid, precomputed
        let (hi, lo) = jewel > socket ? (jewel, socket) : (socket, jewel)
        return (hi + 0.05) / (lo + 0.05)
    }

    private static func luminance(of rgb: (Double, Double, Double)) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
    }

    /// True when the readability pass moved the pick enough to notice, so the
    /// editor can say so rather than silently changing it.
    static func wasAdjusted(red: Double, green: Double, blue: Double) -> Bool {
        let raw = rgbToHSB(red, green, blue)
        let made = MateriaColor(red: red, green: green, blue: blue)
        return abs(raw.1 - made.saturation) > 0.02 || abs(raw.2 - made.brightness) > 0.02
    }

    // MARK: Colour space

    static func hsbToRGB(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        guard s > 0 else { return (v, v, v) }
        let sector = (h - floor(h)) * 6
        let index = floor(sector)
        let f = sector - index
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))

        switch Int(index) % 6 {
        case 0:  return (v, t, p)
        case 1:  return (q, v, p)
        case 2:  return (p, v, t)
        case 3:  return (p, q, v)
        case 4:  return (t, p, v)
        default: return (v, p, q)
        }
    }

    static func rgbToHSB(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let high = max(r, g, b)
        let low = min(r, g, b)
        let delta = high - low

        var hue = 0.0
        if delta > 0 {
            if high == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if high == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }

        return (hue, high <= 0 ? 0 : delta / high, high)
    }

    /// For CSV export and for naming a colour that isn't a preset.
    var hex: String {
        let (r, g, b) = Self.hsbToRGB(hue, saturation, brightness)
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }

    // MARK: Presets

    static let magic       = MateriaColor(hue: 0.3970, saturation: 0.7366, brightness: 0.8784)
    static let summon      = MateriaColor(hue: 0.0113, saturation: 0.6941, brightness: 1.0)
    static let support     = MateriaColor(hue: 0.5691, saturation: 0.6902, brightness: 1.0)
    static let command     = MateriaColor(hue: 0.1252, saturation: 0.7098, brightness: 1.0)
    static let independent = MateriaColor(hue: 0.7669, saturation: 0.5804, brightness: 1.0)

    static let presets: [MateriaPreset] = [
        MateriaPreset(name: "Magic", color: .magic),
        MateriaPreset(name: "Summon", color: .summon),
        MateriaPreset(name: "Support", color: .support),
        MateriaPreset(name: "Command", color: .command),
        MateriaPreset(name: "Independent", color: .independent)
    ]

    /// Preset name if this matches one, otherwise the hex value.
    var displayName: String {
        for preset in Self.presets where preset.color.matches(self) {
            return preset.name
        }
        return hex
    }

    func matches(_ other: MateriaColor) -> Bool {
        abs(hue - other.hue) < 0.005
            && abs(saturation - other.saturation) < 0.005
            && abs(brightness - other.brightness) < 0.005
    }

    // MARK: Codable, with migration

    private enum CodingKeys: String, CodingKey {
        case hue, saturation, brightness
    }

    /// Files written before custom colours stored the preset name as a bare
    /// string ("magic", "summon"). Decode those rather than throwing, or the
    /// whole log reads as empty and looks like data loss.
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let legacy = try? single.decode(String.self) {
            self = Self.legacy(named: legacy)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hue: try container.decode(Double.self, forKey: .hue),
            saturation: try container.decode(Double.self, forKey: .saturation),
            brightness: try container.decode(Double.self, forKey: .brightness)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hue, forKey: .hue)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(brightness, forKey: .brightness)
    }

    private static func legacy(named name: String) -> MateriaColor {
        switch name {
        case "summon":      return .summon
        case "support":     return .support
        case "command":     return .command
        case "independent": return .independent
        default:            return .magic
        }
    }
}

struct MateriaPreset: Identifiable {
    let name: String
    let color: MateriaColor
    var id: String { name }
}

// MARK: - Chrome

/// The equipment-panel greys. Kept in one place so the whole app stays
/// on the same piece of metal.
enum Chrome {
    static let panel      = Color(hex: 0x161B24)
    static let panelHi    = Color(hex: 0x1F2732)
    static let socketVoid = Color(hex: 0x0A0D12)
    static let steel      = Color(hex: 0x5A6472)
    static let steelHi    = Color(hex: 0x8C96A6)
    static let gold       = Color(hex: 0xE8C46A)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Day boundaries

/// Decides which calendar day a timestamp belongs to.
///
/// `dayStartHour` shifts the boundary forward, so a session logged at 1am with
/// a 4am start still counts toward the previous day. Without this, night owls
/// snap streaks on technicalities.
struct DayCalculator {
    var dayStartHour: Int = 0
    var calendar: Calendar = .current

    func day(for date: Date) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: -dayStartHour, to: date) ?? date
        let start = calendar.startOfDay(for: shifted)
        return calendar.date(byAdding: .hour, value: dayStartHour, to: start) ?? start
    }

    var today: Date { day(for: .now) }

    func offsetting(_ day: Date, by days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: day) ?? day
    }

    func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    func label(for day: Date) -> String {
        let diff = daysBetween(day, today)
        switch diff {
        case 0:  return "Today"
        case 1:  return "Yesterday"
        default: return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }
}
