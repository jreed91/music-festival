import SwiftUI

/// Hinterland After Dark: driving home on a county road at midnight, one sodium
/// streetlight at the crossroads. Every screen is pitch black with exactly one thing
/// glowing, and `sodium` means only two things — on air right now, or yours.
///
/// The names and values come from the After Dark design system, which is where the
/// rules for using them live. The older names further down (`background`, `accent`…)
/// map onto the new ones so screens that haven't been restyled still land in the
/// right place.
///
/// Lives in `Shared` because the widget and the Live Activity draw the same festival in
/// the same colours, and a second copy of these numbers would drift the first time one
/// of them was nudged. The view helpers that used to sit here are in `Views/Components`.
enum Theme {
    /// The ground of every screen, widget and Live Activity.
    static let night = Color(hex: 0x050607)
    /// Grouped surfaces on `night`: list sections, cards, map callouts.
    static let nightRaised = Color(hex: 0x0E0F11)
    /// Sheets and menus. The highest surface; never stack a third.
    static let nightSheet = Color(hex: 0x17181B)
    /// Warm black behind things that should look lit from within: day presets, buttons.
    static let glass = Color(hex: 0x120B05)
    static let hairline = Color(hex: 0xEDE6D8).opacity(0.12)

    /// Primary text: headlight cream.
    static let ink = Color(hex: 0xEDE6D8)
    /// Second lines and body copy.
    static let inkMuted = Color(hex: 0xA8A093)
    /// Captions, past sets, hour numerals that aren't now. 12pt and up only.
    static let inkFaint = Color(hex: 0x8A8478)
    /// Marks rather than text: inactive tab icons, unlit fireflies, past hour numerals.
    static let unlit = Color(hex: 0x6B655B)

    /// The one glow: on air right now, or yours.
    static let sodium = Color(hex: 0xFF9A3C)
    /// Text and icons on a solid `sodium` fill.
    static let onSodium = Color(hex: 0x140B03)
    /// The halo behind on-air type.
    static let sodiumGlow = Color(red: 1, green: 140 / 255, blue: 40 / 255).opacity(0.5)
    /// The now line, alerts (a set time changed, medical), the map's radio tower.
    static let signal = Color(hex: 0xFF3B2F)
    /// Living things: Miniland Stage, dietary tags, the fireflies.
    static let firefly = Color(hex: 0xD8F26A)
    /// Campfire Stage, which runs past midnight.
    static let moon = Color(hex: 0xB9C8FF)
    /// Rain chance, kept apart from every stage colour.
    static let rain = Color(hex: 0x6FB3F0)
    /// The bar and tag that flag two starred sets that overlap.
    static let caution = Color(hex: 0xF5C400)
    static let onCaution = Color(hex: 0x141414)

    // MARK: Older names

    static let background = night
    static let surface = nightRaised
    static let surfaceRaised = nightSheet
    static let accent = sodium
    static let secondaryText = inkMuted
    static let tertiaryText = inkFaint
    static let warning = signal
    /// Dietary tags on the food vendors.
    static let dietary = firefly
    /// Everyone else's ratings. Never `sodium` — that colour is your rating — and never
    /// fireflies, so the two numbers can't be mistaken for each other.
    static let crowd = inkMuted
}

extension Color {
    /// `0xFF9A3C`, as the design system writes it.
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Type

/// The two bundled families. Six Caps is for names and big words only; Barlow Condensed
/// is everything else. Both are registered through `UIAppFonts` in each target.
enum AppFontFace {
    static let marquee = "SixCaps"

    /// Barlow Condensed ships in four weights; anything lighter than medium reads as
    /// medium, anything heavier than bold as extra bold.
    static func text(_ weight: Font.Weight) -> String {
        switch weight {
        case .semibold: return "BarlowCondensed-SemiBold"
        case .bold: return "BarlowCondensed-Bold"
        case .heavy, .black: return "BarlowCondensed-ExtraBold"
        default: return "BarlowCondensed-Medium"
        }
    }
}

extension View {
    /// Barlow Condensed at `size`, scaling with the reader's text-size setting.
    ///
    /// A fixed size ignores Dynamic Type completely, which for an app read at arm's
    /// length in a field, in the sun, by a crowd of every age is the wrong default. This
    /// keeps each hand-tuned size exactly as it is at the default setting and scales from
    /// there. `design` is accepted for the callers written before the custom face, and
    /// ignored: Barlow has no rounded cut.
    func appFont(_ size: CGFloat,
                 weight: Font.Weight = .regular,
                 design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight))
    }

    /// Six Caps at `size`, for artist names, day names, hour numerals and screen titles.
    ///
    /// Grows with Dynamic Type but stops at 1.3x: these sizes are already enormous, and
    /// past that a name breaks mid-word. Callers let it wrap rather than truncate.
    func marqueeFont(_ size: CGFloat) -> some View {
        modifier(MarqueeFont(size: size))
    }

    /// The halo behind on-air type: `glow-lg` in the design system.
    func onAirGlow(_ isOn: Bool = true) -> some View {
        shadow(color: isOn ? Theme.sodiumGlow : .clear, radius: 15)
    }
}

private struct ScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        // Barlow Condensed sets smaller than SF at the same point size, so every size is
        // nudged up to read about as large as it did before the switch.
        let adjusted = (size * 1.08).rounded()
        _scaledSize = ScaledMetric(wrappedValue: adjusted, relativeTo: Self.anchor(for: size))
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.custom(AppFontFace.text(weight), fixedSize: scaledSize))
    }

    /// The built-in style whose default size sits nearest, so each size grows at the rate
    /// iOS grows type of that size — a 10pt badge climbs steeply, a 32pt title barely
    /// moves. Anchoring everything to one style instead would either leave the small text
    /// unreadable or blow the large text off the screen.
    static func anchor(for size: CGFloat) -> Font.TextStyle {
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

private struct MarqueeFont: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    let size: CGFloat

    func body(content: Content) -> some View {
        content.font(.custom(AppFontFace.marquee, fixedSize: size * min(scale, 1.3)))
    }
}

extension Stage {
    var color: Color {
        switch self {
        case .main: return Theme.sodium
        case .miniland: return Theme.firefly
        case .campfire: return Theme.moon
        case .other: return Theme.inkMuted
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

    /// "9:30" — a start time in a set row's time column, where the hour numeral beside
    /// it already says whether it's afternoon or night.
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }

    /// "9" and "PM" — the timeline's hour numeral and the half of the day under it.
    static func hourNumeral(_ date: Date) -> (number: String, period: String) {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h"
        let number = formatter.string(from: date)
        formatter.dateFormat = "a"
        return (number, formatter.string(from: date).uppercased())
    }

    /// "75 MIN", the way the design system reads a set's length.
    static func minutes(_ interval: TimeInterval) -> String {
        "\(Int((interval / 60).rounded())) MIN"
    }

    static func range(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    /// `range` for VoiceOver. It reads the dash as a pause, so "8:00pm – 9:15pm" comes out
    /// as two unrelated times rather than a set that runs from one to the other.
    static func spokenRange(_ start: Date, _ end: Date) -> String {
        "\(time(start)) to \(time(end))"
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
