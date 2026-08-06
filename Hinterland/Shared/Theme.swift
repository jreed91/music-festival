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
    /// Everyone else's ratings. Off the accent on purpose — amber stars are yours, and
    /// the two numbers sit next to each other often enough to need telling apart.
    static let crowd = Color(red: 0.78, green: 0.72, blue: 0.98)
}

// MARK: - Type

extension View {
    /// A system font at `size` that scales with the reader's text-size setting.
    ///
    /// `Font.system(size:)` is fixed: it ignores Dynamic Type completely, which for an app
    /// read at arm's length in a field, in the sun, by a crowd of every age is the wrong
    /// default. This keeps each hand-tuned size exactly as it is at the default setting and
    /// scales from there.
    func appFont(_ size: CGFloat,
                 weight: Font.Weight = .regular,
                 design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

private struct ScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: Self.anchor(for: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: weight, design: design))
    }

    /// The built-in style whose default size sits nearest, so each size grows at the rate
    /// iOS grows type of that size — a 10pt badge climbs steeply, a 32pt title barely
    /// moves. Anchoring everything to one style instead would either leave the small text
    /// unreadable or blow the large text off the screen.
    private static func anchor(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2      // 11
        case ..<12.5: return .caption       // 12
        case ..<13.5: return .footnote      // 13
        case ..<15.5: return .subheadline   // 15
        case ..<16.5: return .callout       // 16
        case ..<18.5: return .body          // 17
        case ..<21:   return .title3        // 20
        case ..<25:   return .title2        // 22
        case ..<31:   return .title         // 28
        default:      return .largeTitle    // 34
        }
    }
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

    /// "Jul 30 – Aug 2", from the `yyyy-MM-dd` strings the festival gives its own dates in.
    /// Nil if either one doesn't parse, so a caller can fall back rather than print a range
    /// with a hole in it.
    static func dateRange(_ start: String, _ end: String) -> String? {
        let parser = DateFormatter()
        parser.timeZone = timeZone
        parser.dateFormat = "yyyy-MM-dd"
        guard let from = parser.date(from: start), let to = parser.date(from: end) else {
            return nil
        }
        let printer = DateFormatter()
        printer.timeZone = timeZone
        printer.dateFormat = "MMM d"
        return "\(printer.string(from: from)) – \(printer.string(from: to))"
    }

    /// An average rating to one decimal — "4.3" — in the reader's own number format.
    static func rating(_ average: Double) -> String {
        average.formatted(.number.precision(.fractionLength(1)))
    }

    /// "in 25 min" / "started 10 min ago", used on the Now card.
    static func relative(_ date: Date, from now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
