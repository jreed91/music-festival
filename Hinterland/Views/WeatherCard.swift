import SwiftUI

/// The forecast in one line, sitting above the schedule. Tapping it opens `WeatherView`.
///
/// It renders even with nothing cached, because a blank space is not discoverable and
/// the first fetch needs someone to be somewhere with a signal.
struct WeatherCard: View {
    @Environment(WeatherStore.self) private var weather

    private var current: CurrentConditions? { weather.snapshot?.current }

    /// The soonest hour in the next twelve with a real chance of rain — the one thing
    /// worth surfacing before someone decides what to carry.
    private var wetHour: HourConditions? {
        weather.snapshot?.upcomingHours(limit: 12).first { $0.precipitationChance >= 0.3 }
    }

    var body: some View {
        NavigationLink(value: WeatherRoute.forecast) {
            HStack(spacing: 12) {
                Image(systemName: current?.symbolName ?? "cloud.sun")
                    .symbolRenderingMode(current == nil ? .monochrome : .multicolor)
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 30)

                if let current {
                    Text(Format.temperature(current.temperature))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.condition)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                        if let wetHour {
                            Label("\(Format.percent(wetHour.precipitationChance)) rain by "
                                + Format.hour(wetHour.date),
                                  systemImage: "umbrella")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.rain)
                        } else if current.showsApparentTemperature {
                            Text("Feels like \(Format.temperature(current.apparentTemperature))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Forecast")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(weather.isRefreshing ? "Loading…" : "Tap to load — needs a signal once")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(current.map { "Weather, \(Format.temperature($0.temperature)), \($0.condition)" }
                            ?? "Weather forecast")
    }
}

/// A severe or extreme advisory, pulled out of the weather screen and onto the schedule.
/// At that point it isn't a forecast, it's an instruction, and it shouldn't need a tap
/// to find.
struct WeatherAlertBanner: View {
    let advisory: WeatherAdvisory

    var body: some View {
        NavigationLink(value: WeatherRoute.forecast) {
            HStack(spacing: 10) {
                Image(systemName: advisory.severity.symbol)
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(advisory.summary)
                        .font(.system(size: 14, weight: .bold))
                        .multilineTextAlignment(.leading)
                    Text("\(advisory.severity.label) · \(advisory.source)")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(advisory.severity.tint,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The same advisory on the weather screen itself, where there's room for the region it
/// covers and a link out to the full text.
struct WeatherAlertCard: View {
    let advisory: WeatherAdvisory

    var body: some View {
        Link(destination: advisory.detailsURL) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: advisory.severity.symbol)
                        .font(.system(size: 15, weight: .semibold))
                    Text(advisory.severity.label.uppercased())
                        .font(.system(size: 11, weight: .heavy))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.7)
                }
                .foregroundStyle(advisory.severity.tint)

                Text(advisory.summary)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text([advisory.region, advisory.source].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(advisory.severity.tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(advisory.severity.tint.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// What it'll be doing while a set is on. Shown next to set times, and simply absent
/// when the forecast doesn't reach that far — a guess is worse than nothing here.
struct SetForecastBadge: View {
    let hour: HourConditions

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: hour.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 11))
            Text(Format.temperature(hour.temperature))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            if hour.precipitationChance >= 0.2 {
                Text(Format.percent(hour.precipitationChance))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.rain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surfaceRaised, in: Capsule())
        .accessibilityLabel("At set time: \(Format.temperature(hour.temperature)), \(hour.condition)")
    }
}

/// Apple requires the Weather trademark and a link to its legal page wherever WeatherKit
/// data is shown. The marks are remote images, so the cached service name stands in
/// while they load and whenever there's no signal to load them at all.
struct WeatherAttributionView: View {
    let attribution: WeatherAttributionInfo?

    var body: some View {
        VStack(spacing: 5) {
            if let attribution {
                Link(destination: attribution.legalPageURL) {
                    VStack(spacing: 5) {
                        AsyncImage(url: attribution.combinedMarkDarkURL) { image in
                            image.resizable().scaledToFit().frame(height: 16)
                        } placeholder: {
                            textMark(attribution.serviceName)
                        }
                        Text(attribution.legalText)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                .buttonStyle(.plain)
            } else {
                textMark("Weather")
            }
        }
        .padding(.top, 4)
    }

    private func textMark(_ name: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "apple.logo")
            Text(name)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.secondaryText)
    }
}

extension AdvisorySeverity {
    var tint: Color {
        switch self {
        case .extreme: return Color(red: 1.0, green: 0.36, blue: 0.36)
        case .severe: return Theme.warning
        case .moderate: return Theme.accent
        case .minor, .unknown: return Color(red: 0.55, green: 0.75, blue: 0.98)
        }
    }
}
