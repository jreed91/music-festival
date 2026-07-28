import CoreLocation
import Foundation
import Observation
import WeatherKit

/// Owns the festival forecast.
///
/// The same offline-first bargain the schedule makes: whatever was last fetched is
/// loaded from disk at launch and shown immediately, the network is an upgrade path,
/// and a failed fetch leaves the cached forecast on screen rather than an empty view.
/// Unlike the schedule there is nothing to bundle — a forecast shipped in the binary
/// would be a year old — so before the first successful fetch there is simply no
/// weather, and the UI says so.
///
/// The location is the venue from `map.json`, not the phone's. Everyone using this app
/// wants the weather over the amphitheater, including the people still driving to it,
/// and it means the forecast needs no location permission.
@Observable
final class WeatherStore {
    /// Floor on how often we'll hit WeatherKit, independent of what the forecast says
    /// about its own expiry. Foreground/background cycling shouldn't burn the free call
    /// allowance, and a forecast doesn't change usefully inside a quarter of an hour.
    private static let minimumInterval: TimeInterval = 15 * 60

    /// How far ahead to keep hourly detail. Two days covers the whole festival from any
    /// point inside it; WeatherKit hands back ten times that and it all gets cached.
    private static let hourlyHorizon: TimeInterval = 48 * 3600

    let venue: MapVenue

    private(set) var snapshot: WeatherSnapshot?
    private(set) var isRefreshing = false
    /// Nil once a fetch succeeds. Never blocks the cached forecast from rendering.
    private(set) var lastError: String?

    private var lastAttempt: Date?

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("weather.json")
    }

    init(venue: MapVenue) {
        self.venue = venue
        snapshot = Self.loadCache()
    }

    // MARK: - Refresh

    /// Best effort, always. `force` is for pull-to-refresh and the refresh button, which
    /// should do something visible even when the cached forecast hasn't expired yet.
    @MainActor
    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        guard force || shouldRefresh() else { return }

        isRefreshing = true
        lastAttempt = Date()
        defer { isRefreshing = false }

        do {
            let location = CLLocation(latitude: venue.latitude, longitude: venue.longitude)
            let service = WeatherService.shared
            let (current, hourly, daily, alerts) = try await service.weather(
                for: location, including: .current, .hourly, .daily, .alerts)

            // Attribution is a second round trip for marks and legal text that never
            // change, so it's fetched once and then carried forward. A failure there is
            // not worth losing a good forecast over: the text fallback covers it.
            //
            // Written out rather than folded into a `??`, whose right-hand side is a
            // non-async autoclosure and can't hold the await.
            var attribution = snapshot?.attribution
            if attribution == nil {
                attribution = (try? await service.attribution).map { WeatherAttributionInfo($0) }
            }

            snapshot = Self.makeSnapshot(
                current: current,
                hourly: hourly.forecast,
                daily: daily.forecast,
                alerts: alerts ?? [],
                attribution: attribution)
            lastError = nil
            persist()
        } catch {
            lastError = Self.message(for: error)
        }
    }

    private func shouldRefresh(now: Date = Date()) -> Bool {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.minimumInterval {
            return false
        }
        guard let snapshot else { return true }
        return snapshot.isExpired(at: now)
    }

    /// WeatherKit's errors are terse and mostly mean one of two things: no signal, or
    /// the entitlement isn't set up on this build. Neither is worth a stack trace on a
    /// phone in a field.
    private static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No signal — showing the last forecast that came through."
            case .timedOut:
                return "The forecast request timed out."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    // MARK: - Mapping

    private static func makeSnapshot(current: CurrentWeather,
                                     hourly: [HourWeather],
                                     daily: [DayWeather],
                                     alerts: [WeatherAlert],
                                     attribution: WeatherAttributionInfo?) -> WeatherSnapshot {
        let now = Date()
        // WeatherKit's hourly forecast opens at the start of today, so the first several
        // entries are already history. Keep the current hour onward.
        let window = hourly.filter {
            $0.date.addingTimeInterval(3600) > now && $0.date < now.addingTimeInterval(hourlyHorizon)
        }

        return WeatherSnapshot(
            fetchedAt: now,
            expiresAt: current.metadata.expirationDate,
            current: CurrentConditions(current),
            hourly: window.map { HourConditions($0) },
            daily: daily.map { DayConditions($0) },
            alerts: alerts.map { WeatherAdvisory($0) },
            attribution: attribution)
    }

    // MARK: - Cache

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }

    private func persist() {
        guard let snapshot else { return }
        let (encoder, _) = Self.coder()
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    /// A cache we can't read is a cache we don't have — the app just starts without a
    /// forecast and fetches one.
    private static func loadCache() -> WeatherSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let (_, decoder) = coder()
        return try? decoder.decode(WeatherSnapshot.self, from: data)
    }
}

// MARK: - WeatherKit → snapshot

private extension CurrentConditions {
    init(_ weather: CurrentWeather) {
        self.init(
            temperatureCelsius: weather.temperature.converted(to: .celsius).value,
            apparentTemperatureCelsius: weather.apparentTemperature.converted(to: .celsius).value,
            symbolName: weather.symbolName,
            condition: weather.condition.description,
            humidity: weather.humidity,
            windSpeedKPH: weather.wind.speed.converted(to: .kilometersPerHour).value,
            windGustKPH: weather.wind.gust?.converted(to: .kilometersPerHour).value,
            windDirection: weather.wind.compassDirection.abbreviation,
            uvIndex: weather.uvIndex.value,
            uvCategory: weather.uvIndex.category.description)
    }
}

private extension HourConditions {
    init(_ weather: HourWeather) {
        self.init(
            date: weather.date,
            temperatureCelsius: weather.temperature.converted(to: .celsius).value,
            symbolName: weather.symbolName,
            condition: weather.condition.description,
            precipitationChance: weather.precipitationChance)
    }
}

private extension DayConditions {
    init(_ weather: DayWeather) {
        self.init(
            date: weather.date,
            highCelsius: weather.highTemperature.converted(to: .celsius).value,
            lowCelsius: weather.lowTemperature.converted(to: .celsius).value,
            symbolName: weather.symbolName,
            condition: weather.condition.description,
            precipitationChance: weather.precipitationChance,
            sunset: weather.sun.sunset)
    }
}

private extension WeatherAdvisory {
    init(_ alert: WeatherAlert) {
        // WeatherKit doesn't hand out an identifier, and the details URL is per-event,
        // so it plus the summary is stable enough to keep SwiftUI's diffing honest.
        self.init(
            id: "\(alert.detailsURL.absoluteString)|\(alert.summary)",
            summary: alert.summary,
            severity: AdvisorySeverity(alert.severity),
            region: alert.region,
            source: alert.source,
            detailsURL: alert.detailsURL)
    }
}

private extension AdvisorySeverity {
    init(_ severity: WeatherSeverity) {
        switch severity {
        case .extreme: self = .extreme
        case .severe: self = .severe
        case .moderate: self = .moderate
        case .minor: self = .minor
        case .unknown: self = .unknown
        @unknown default: self = .unknown
        }
    }
}

private extension WeatherAttributionInfo {
    init(_ attribution: WeatherAttribution) {
        self.init(
            serviceName: attribution.serviceName,
            legalText: attribution.legalAttributionText,
            legalPageURL: attribution.legalPageURL,
            // The app is locked to dark mode, so the light mark would be invisible.
            combinedMarkDarkURL: attribution.combinedMarkDarkURL)
    }
}
