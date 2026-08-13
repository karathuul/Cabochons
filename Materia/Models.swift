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

/// The five materia types. Color is the only saturated element in the whole
/// interface — everything else is gunmetal — so it carries all the identity.
enum MateriaColor: String, Codable, CaseIterable, Identifiable {
    case magic, summon, support, command, independent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .magic:       return "Magic"
        case .summon:      return "Summon"
        case .support:     return "Support"
        case .command:     return "Command"
        case .independent: return "Independent"
        }
    }

    /// Bright center of the orb.
    var core: Color {
        switch self {
        case .magic:       return Color(hex: 0x3BE07A)
        case .summon:      return Color(hex: 0xFF5A4E)
        case .support:     return Color(hex: 0x4FB6FF)
        case .command:     return Color(hex: 0xFFD24A)
        case .independent: return Color(hex: 0xC46BFF)
        }
    }

    /// Shadowed lower edge, gives the sphere its volume.
    var deep: Color {
        switch self {
        case .magic:       return Color(hex: 0x064F2A)
        case .summon:      return Color(hex: 0x5C0C10)
        case .support:     return Color(hex: 0x082F58)
        case .command:     return Color(hex: 0x5A4004)
        case .independent: return Color(hex: 0x350758)
        }
    }

    /// Thin bright rim where the glass catches light.
    var rim: Color {
        switch self {
        case .magic:       return Color(hex: 0x8CFFC0)
        case .summon:      return Color(hex: 0xFFB0A8)
        case .support:     return Color(hex: 0xA8DBFF)
        case .command:     return Color(hex: 0xFFE9A8)
        case .independent: return Color(hex: 0xE3B8FF)
        }
    }
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
