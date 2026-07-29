import SwiftUI

/// A deliberately dark palette — the app is mostly read at dusk, in a field, at low
/// brightness. Warm accents echo the festival's sunset/campfire identity.
///
/// Lives in `Shared` because the widget and the Live Activity draw the same festival in
/// the same colours, and a second copy of these numbers would drift the first time one
/// of them was nudged. The view helpers that used to sit here are in `Views/Components`.
enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.13)
    static let surfaceRaised = Color(red: 0.14, green: 0.14, blue: 0.18)
    static let accent = Color(red: 0.96, green: 0.60, blue: 0.26)      // sunset amber
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)
    static let hairline = Color.white.opacity(0.10)
    static let warning = Color(red: 0.98, green: 0.45, blue: 0.42)
    /// Rain chances, kept cool so they read as a separate signal from the amber accent.
    static let rain = Color(red: 0.48, green: 0.76, blue: 0.98)
    /// Dietary tags on the food vendors, kept off the accent so a wall of them doesn't
    /// read as a wall of buttons.
    static let dietary = Color(red: 0.52, green: 0.84, blue: 0.62)
}

extension Stage {
    var color: Color {
        switch self {
        case .main: return Theme.accent
        case .miniland: return Color(red: 0.42, green: 0.82, blue: 0.70)
        case .campfire: return Color(red: 0.72, green: 0.55, blue: 0.96)
        case .other: return Color.white.opacity(0.55)
        }
    }
}

// MARK: - Shared formatting

enum Format {
    /// Set times always read in the festival's own time zone, not the device's, so a
    /// phone that hasn't caught up to Central still shows the right times.
    static let timeZone: TimeZone = TimeZone(identifier: "America/Chicago") ?? .current

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date).replacingOccurrences(of: " AM", with: "am")
            .replacingOccurrences(of: " PM", with: "pm")
    }

    static func range(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    static func dayLabel(_ day: FestivalDay) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day.date) else { return day.weekday }
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// "in 25 min" / "started 10 min ago", used on the Now card.
    static func relative(_ date: Date, from now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
