import Foundation

/// A flattened, archivable copy of everything the app shows from WeatherKit.
///
/// WeatherKit's own forecast types can't be written to disk, and this app assumes there
/// is no network — a valley in St. Charles with 15,000 phones in it has no usable data.
/// So the forecast is copied into plain values the moment it arrives and cached. What is
/// on screen is always this snapshot, whether it landed a minute ago or three hours ago,
/// and the UI says which.
///
/// Everything is stored metric. Display converts, so a cache written on one device
/// still reads correctly in whichever units the phone's locale prefers.
struct WeatherSnapshot: Codable, Equatable {
    /// When this was pulled from WeatherKit, shown to the user so a stale forecast is
    /// obviously stale rather than quietly wrong.
    let fetchedAt: Date
    /// WeatherKit's own expiry for the observation. Drives when we bother asking again.
    let expiresAt: Date
    var current: CurrentConditions?
    var hourly: [HourConditions]
    var daily: [DayConditions]
    var alerts: [WeatherAdvisory]
    /// Apple requires the Weather trademark and a link to its legal page anywhere this
    /// data appears, so the attribution is cached alongside it and survives going offline.
    var attribution: WeatherAttributionInfo?

    func isExpired(at date: Date = Date()) -> Bool { date >= expiresAt }
}

// MARK: - Conditions

struct CurrentConditions: Codable, Equatable {
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double
    let symbolName: String
    let condition: String
    /// 0–1.
    let humidity: Double
    let windSpeedKPH: Double
    let windGustKPH: Double?
    /// Compass abbreviation — "NNW".
    let windDirection: String
    let uvIndex: Int
    let uvCategory: String

    var temperature: Measurement<UnitTemperature> {
        Measurement(value: temperatureCelsius, unit: .celsius)
    }

    var apparentTemperature: Measurement<UnitTemperature> {
        Measurement(value: apparentTemperatureCelsius, unit: .celsius)
    }

    var windSpeed: Measurement<UnitSpeed> {
        Measurement(value: windSpeedKPH, unit: .kilometersPerHour)
    }

    var windGust: Measurement<UnitSpeed>? {
        windGustKPH.map { Measurement(value: $0, unit: .kilometersPerHour) }
    }

    /// Worth calling out on a card: "feels like" only earns its space when it disagrees
    /// with the thermometer, which in an Iowa August it usually does.
    var showsApparentTemperature: Bool {
        abs(apparentTemperatureCelsius - temperatureCelsius) >= 1
    }
}

struct HourConditions: Codable, Equatable, Identifiable {
    let date: Date
    let temperatureCelsius: Double
    let symbolName: String
    let condition: String
    /// 0–1.
    let precipitationChance: Double

    var id: Date { date }

    var temperature: Measurement<UnitTemperature> {
        Measurement(value: temperatureCelsius, unit: .celsius)
    }
}

struct DayConditions: Codable, Equatable, Identifiable {
    /// Start of the forecast day, in the forecast location's time zone.
    let date: Date
    let highCelsius: Double
    let lowCelsius: Double
    let symbolName: String
    let condition: String
    /// 0–1.
    let precipitationChance: Double
    /// When the field finally cools off. Nil at latitudes and dates where the sun
    /// doesn't set, which St. Charles is not, but the API is honest about it.
    let sunset: Date?

    var id: Date { date }

    var high: Measurement<UnitTemperature> {
        Measurement(value: highCelsius, unit: .celsius)
    }

    var low: Measurement<UnitTemperature> {
        Measurement(value: lowCelsius, unit: .celsius)
    }
}

// MARK: - Alerts

/// A National Weather Service advisory as WeatherKit hands it over. Iowa in high summer
/// means severe thunderstorm and tornado warnings, which for an outdoor festival is the
/// single most important thing this whole screen can tell anyone.
struct WeatherAdvisory: Codable, Equatable, Identifiable {
    let id: String
    let summary: String
    let severity: AdvisorySeverity
    let region: String?
    let source: String
    let detailsURL: URL
}

/// Mirrors `WeatherSeverity` without dragging WeatherKit into the archived model.
enum AdvisorySeverity: String, Codable, Comparable {
    case unknown
    case minor
    case moderate
    case severe
    case extreme

    /// Ordering for "show the worst one first", with `unknown` treated as the least
    /// urgent rather than as a gap in the scale.
    private var rank: Int {
        switch self {
        case .unknown: return 0
        case .minor: return 1
        case .moderate: return 2
        case .severe: return 3
        case .extreme: return 4
        }
    }

    static func < (lhs: AdvisorySeverity, rhs: AdvisorySeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Severe and worse get pulled out of the weather screen and onto the schedule,
    /// because at that point it is not a forecast, it is an instruction.
    var isUrgent: Bool { self >= .severe }

    var label: String {
        switch self {
        case .unknown: return "Advisory"
        case .minor: return "Minor"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        case .extreme: return "Extreme"
        }
    }

    var symbol: String {
        switch self {
        case .extreme, .severe: return "exclamationmark.triangle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .minor, .unknown: return "info.circle.fill"
        }
    }
}

// MARK: - Attribution

/// Apple's required attribution, cached so it still renders with no signal. The marks
/// are remote images; `legalText` is the offline fallback.
struct WeatherAttributionInfo: Codable, Equatable {
    let serviceName: String
    let legalText: String
    let legalPageURL: URL
    let combinedMarkDarkURL: URL
}

// MARK: - Lookups

extension WeatherSnapshot {
    /// Alerts worst-first — a tornado warning should never sit under a heat advisory.
    var alertsBySeverity: [WeatherAdvisory] {
        alerts.sorted { $0.severity > $1.severity }
    }

    var urgentAlert: WeatherAdvisory? {
        alertsBySeverity.first { $0.severity.isUrgent }
    }

    /// The hour a moment falls inside. Used to answer "what will it be doing during this
    /// set", so it returns nothing rather than guessing when the forecast doesn't reach.
    func hour(containing date: Date) -> HourConditions? {
        hourly.last { $0.date <= date && date < $0.date.addingTimeInterval(3600) }
    }

    /// The next `limit` hours, starting with the one we are in.
    func upcomingHours(from date: Date = Date(), limit: Int = 24) -> [HourConditions] {
        hourly
            .filter { $0.date.addingTimeInterval(3600) > date }
            .prefix(limit)
            .map { $0 }
    }

    /// The forecast for a `FestivalDay`, matched on the calendar date in the festival's
    /// own time zone. WeatherKit reaches about ten days out, so this is nil for days
    /// still beyond the horizon.
    func day(for festivalDay: FestivalDay, in timeZone: TimeZone) -> DayConditions? {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return daily.first { formatter.string(from: $0.date) == festivalDay.date }
    }
}

// MARK: - Formatting

extension Format {
    /// Locale-aware: °F in the US, °C most other places. `.narrow` drops the unit, which
    /// is what compact spots like the day picker want.
    static func temperature(
        _ value: Measurement<UnitTemperature>,
        width: Measurement<UnitTemperature>.FormatStyle.UnitWidth = .narrow
    ) -> String {
        value.formatted(
            .measurement(width: width,
                         usage: .weather,
                         numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// Converted by hand rather than through `usage:`, because the measurement styles
    /// don't have a wind usage and left alone they'd report km/h to an Iowa crowd.
    static func windSpeed(_ value: Measurement<UnitSpeed>) -> String {
        let imperial = Locale.current.measurementSystem == .us
        let converted = value.converted(to: imperial ? .milesPerHour : .kilometersPerHour)
        return "\(Int(converted.value.rounded())) \(imperial ? "mph" : "km/h")"
    }

    /// 0–1 to "40%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// "3pm" — the hourly strip has no room for minutes that are always :00.
    static func hour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
            .replacingOccurrences(of: " AM", with: "am")
            .replacingOccurrences(of: " PM", with: "pm")
    }
}
