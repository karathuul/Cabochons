internal import Foundation
internal import SwiftUI

// MARK: - Jewel

/// A single tap. One jewel = one occurrence of the activity.
struct Jewel: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date
    /// Optional. Synthesised decoding uses `decodeIfPresent` for Optionals, so
    /// files written before notes existed load without migration.
    var note: String? = nil

    /// Whitespace-only notes don't count — otherwise an opened-and-abandoned
    /// editor would flag the jewel forever.
    var hasNote: Bool {
        !(note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Cadence

/// How often an activity comes due. The app's unit of time is the *period*,
/// not the day — "3 times every 2 weeks" and "once a month" are as valid as
/// "4 times a day".
struct Cadence: Codable, Hashable {
    enum Unit: String, Codable, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }

        func label(count: Int) -> String {
            let stem: String
            switch self {
            case .day:   stem = "day"
            case .week:  stem = "week"
            case .month: stem = "month"
            }
            return count == 1 ? stem : stem + "s"
        }
    }

    var count: Int
    var unit: Unit

    init(count: Int, unit: Unit) {
        self.count = max(1, count)
        self.unit = unit
    }

    static let daily = Cadence(count: 1, unit: .day)
    static let weekly = Cadence(count: 1, unit: .week)
    static let monthly = Cadence(count: 1, unit: .month)

    static let presets: [Cadence] = [
        .daily,
        Cadence(count: 3, unit: .day),
        .weekly,
        Cadence(count: 2, unit: .week),
        .monthly,
        Cadence(count: 3, unit: .month)
    ]

    var isDaily: Bool { count == 1 && unit == .day }

    /// "day", "3 days", "2 weeks"
    var phrase: String {
        count == 1 ? unit.label(count: 1) : "\(count) \(unit.label(count: count))"
    }

    /// Length in days. Nil for month-based cadences, which vary.
    var lengthInDays: Int? {
        switch unit {
        case .day:   return count
        case .week:  return count * 7
        case .month: return nil
        }
    }
}

// MARK: - Activity

struct Activity: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var color: MateriaColor
    /// Sockets per period.
    var target: Int
    var isOpenEnded: Bool { target == 0 }
    var cadence: Cadence = .daily
    var jewels: [Jewel] = []
    var createdAt: Date = .now
    /// Hidden activities keep every jewel they ever earned but stop asking for
    /// anything: no sockets, no button, no place in the day's capacity.
    var isHidden: Bool = false

    /// Newest first.
    var sortedJewels: [Jewel] {
        jewels.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: Codable, with migration

    private enum CodingKeys: String, CodingKey {
        case id, name, color, target, cadence, jewels, createdAt, isHidden
        case dailyTarget   // pre-cadence name
    }

    init(
        id: UUID = UUID(),
        name: String,
        color: MateriaColor,
        target: Int,
        cadence: Cadence = .daily,
        jewels: [Jewel] = [],
        createdAt: Date = .now,
        isHidden: Bool = false
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.target = target
        self.cadence = cadence
        self.jewels = jewels
        self.createdAt = createdAt
        self.isHidden = isHidden
    }

    /// Files written before cadences stored `dailyTarget` and had no `cadence`.
    /// Fall back to both rather than throwing, or the whole log reads as empty.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        color = try container.decode(MateriaColor.self, forKey: .color)
        target = try container.decodeIfPresent(Int.self, forKey: .target)
            ?? container.decodeIfPresent(Int.self, forKey: .dailyTarget)
            ?? 1
        cadence = try container.decodeIfPresent(Cadence.self, forKey: .cadence) ?? .daily
        jewels = try container.decodeIfPresent([Jewel].self, forKey: .jewels) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    /// Written by hand because `CodingKeys` carries `dailyTarget`, a key with
    /// no matching property. Swift synthesises `encode(to:)` by pairing each
    /// stored property with its key, so a case that pairs with nothing makes
    /// synthesis fail — and only on the encode side, since `init(from:)` is
    /// custom.
    ///
    /// `dailyTarget` is read-only: it's accepted on the way in from old files
    /// and never written back out.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(target, forKey: .target)
        try container.encode(cadence, forKey: .cadence)
        try container.encode(jewels, forKey: .jewels)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isHidden, forKey: .isHidden)
    }
}

// MARK: - Tag

/// A category laid across activities — "exercise", "social", "creative". A
/// tag has its own target and cadence, and its progress is the sum of every
/// member's jewels within the tag's current period.
///
/// Membership lives here, not on the activity, so configuring a rail is one
/// edit in one place and `Activity`'s schema doesn't move. An activity can
/// belong to any number of tags: acro can be social *and* exercise.
///
/// Tags stack with activity targets rather than replacing them. "Run 3× a
/// week" and "exercise 5× a week" are both live; one run advances both.
///
/// Lives in this file, next to `Activity`, because `LogFile` carries tags and
/// the widget decodes `LogFile` — so wherever `Activity` compiles, this must.
struct Tag: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Jewels per period. Never 0 — a tag with nothing to ask for is just a
    /// label, and the app doesn't do labels.
    var target: Int
    var cadence: Cadence = .weekly
    /// Ordered, so a tag's legend reads the same every day. Kept in sync by
    /// `LogStore.delete(_:)`, which prunes a deleted activity from every tag.
    var activityIDs: [UUID] = []
    /// Period anchor, same rule as `Activity.createdAt`.
    var createdAt: Date = .now

    func contains(_ id: Activity.ID) -> Bool {
        activityIDs.contains(id)
    }

    init(
        id: UUID = UUID(),
        name: String,
        target: Int,
        cadence: Cadence = .weekly,
        activityIDs: [UUID] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.target = max(1, target)
        self.cadence = cadence
        self.activityIDs = activityIDs
        self.createdAt = createdAt
    }

    // MARK: Codable, with migration

    private enum CodingKeys: String, CodingKey {
        case id, name, target, cadence, activityIDs, createdAt
    }

    /// Every key but `name` falls back, so a tag written by a future version
    /// with fields this one doesn't know still loads. `encode(to:)` is
    /// synthesised: every case here pairs with a property.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        target = try max(1, container.decodeIfPresent(Int.self, forKey: .target) ?? 1)
        cadence = try container.decodeIfPresent(Cadence.self, forKey: .cadence) ?? .weekly
        activityIDs = try container.decodeIfPresent([UUID].self, forKey: .activityIDs) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
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
        MateriaPreset(name: "Earth", color: .magic),
        MateriaPreset(name: "Water", color: .support),
        MateriaPreset(name: "Fire", color: .summon),
        MateriaPreset(name: "Gold", color: .command),
        MateriaPreset(name: "Magic", color: .independent)
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
    
    func weekday(for date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }
    
    func hour(for date: Date) -> Int {
        calendar.component(.hour, from: date)
    }

    // MARK: Periods

    /// Which period a date falls in, counted from the activity's creation.
    ///
    /// Day- and week-based cadences are anchored to the creation day, because
    /// "every 3 days" has no natural calendar alignment. Month-based ones are
    /// calendar-aligned instead — asking "did I do it in August" is how people
    /// actually think about a monthly commitment, and it sidesteps months
    /// having different lengths.
    func periodIndex(for date: Date, cadence: Cadence, anchor: Date) -> Int {
        switch cadence.unit {
        case .day, .week:
            let span = cadence.lengthInDays ?? 1
            return Self.floorDiv(daysBetween(day(for: anchor), day(for: date)), span)
        case .month:
            let from = monthStart(for: anchor)
            let to = monthStart(for: date)
            let months = calendar.dateComponents([.month], from: from, to: to).month ?? 0
            return Self.floorDiv(months, cadence.count)
        }
    }

    func periodStart(index: Int, cadence: Cadence, anchor: Date) -> Date {
        switch cadence.unit {
        case .day, .week:
            let span = cadence.lengthInDays ?? 1
            return offsetting(day(for: anchor), by: index * span)
        case .month:
            let from = monthStart(for: anchor)
            return calendar.date(byAdding: .month, value: index * cadence.count, to: from) ?? from
        }
    }

    /// Exclusive.
    func periodEnd(index: Int, cadence: Cadence, anchor: Date) -> Date {
        periodStart(index: index + 1, cadence: cadence, anchor: anchor)
    }

    func currentPeriodIndex(cadence: Cadence, anchor: Date) -> Int {
        periodIndex(for: .now, cadence: cadence, anchor: anchor)
    }

    private func monthStart(for date: Date) -> Date {
        let shifted = day(for: date)
        let components = calendar.dateComponents([.year, .month], from: shifted)
        return calendar.date(from: components) ?? shifted
    }

    /// Swift's `/` truncates toward zero, which puts dates before the anchor in
    /// the wrong period. Periods must tile the line evenly in both directions.
    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let quotient = a / b
        let remainder = a % b
        return (remainder != 0 && ((remainder < 0) != (b < 0))) ? quotient - 1 : quotient
    }

    /// "Today", "Aug 12 – 18", "August", "Aug – Oct 2026"
    func periodLabel(index: Int, cadence: Cadence, anchor: Date) -> String {
        let start = periodStart(index: index, cadence: cadence, anchor: anchor)
        let end = offsetting(periodEnd(index: index, cadence: cadence, anchor: anchor), by: -1)

        if cadence.isDaily { return label(for: start) }

        if cadence.unit == .month {
            if cadence.count == 1 {
                return start.formatted(.dateTime.month(.wide).year())
            }
            return start.formatted(.dateTime.month(.abbreviated))
                + " – " + end.formatted(.dateTime.month(.abbreviated).year())
        }

        return start.formatted(.dateTime.month(.abbreviated).day())
            + " – " + end.formatted(.dateTime.month(.abbreviated).day())
    }
}
