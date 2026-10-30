import SwiftUI

/// The forecast in one line, sitting above the schedule. Tapping it opens `WeatherView`.
///
/// It renders even with nothing cached, because a blank space is not discoverable and
/// the first fetch needs someone to be somewhere with a signal.
struct WeatherCard: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(\.dynamicTypeSize) private var typeSize

    private var current: CurrentConditions? { weather.snapshot?.current }

    /// Symbol, temperature and conditions fit on one line at ordinary sizes and nowhere
    /// near it at accessibility ones, where the row used to run off the card and print
    /// "Feels like" over the temperature. Stack them instead of overflowing.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    /// The soonest hour in the next twelve with a real chance of rain — the one thing
    /// worth surfacing before someone decides what to carry.
    private var wetHour: HourConditions? {
        weather.snapshot?.upcomingHours(limit: 12).first { $0.precipitationChance >= 0.3 }
    }

    var body: some View {
        NavigationLink(value: WeatherRoute.forecast) {
            layout {
                if let current {
                    // A big word in the design system's sense: the one number anyone
                    // reads off this card.
                    Text(Format.temperature(current.temperature))
                        .marqueeFont(56)
                        .foregroundStyle(Theme.ink)
                        .fixedSize()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            // One colour, not the system's multicolour suns and clouds:
                            // the screen's only glow is what's on air.
                            Image(systemName: current.symbolName)
                                .symbolRenderingMode(.hierarchical)
                                .appFont(15, weight: .semibold)
                                .accessibilityHidden(true)
                            Text(current.condition.uppercased())
                                .appFont(15, weight: .bold)
                                .tracking(1.2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Theme.inkMuted)
                        if let wetHour {
                            Label("\(Format.percent(wetHour.precipitationChance)) rain by "
                                + Format.hour(wetHour.date),
                                  systemImage: "umbrella")
                                .appFont(13, weight: .bold)
                                .foregroundStyle(Theme.rain)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if current.showsApparentTemperature {
                            Text("Feels like \(Format.temperature(current.apparentTemperature))")
                                .appFont(13)
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FORECAST")
                            .appFont(13, weight: .bold)
                            .tracking(2.4)
                            .foregroundStyle(Theme.inkFaint)
                        Text(weather.isRefreshing ? "Tuning in…" : "Tap to load. It needs a signal once.")
                            .appFont(15)
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .appFont(12, weight: .semibold)
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityHidden(true)
            }
            // Stacked, nothing is left pushing the card open, so it would shrink to its
            // widest line and stop matching the cards above and below it.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.nightRaised)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenSummary)
    }

    /// Everything the card shows, including the rain warning the label used to drop —
    /// the one line on it that changes what someone carries out to the field.
    private var spokenSummary: String {
        guard let current else { return "Weather forecast" }
        var parts = ["Weather", Format.temperature(current.temperature), current.condition]
        if let wetHour {
            parts.append("\(Format.percent(wetHour.precipitationChance)) chance of rain by "
                       + Format.hour(wetHour.date))
        } else if current.showsApparentTemperature {
            parts.append("feels like \(Format.temperature(current.apparentTemperature))")
        }
        return parts.joined(separator: ", ")
    }
}

/// A severe or extreme advisory, pulled out of the weather screen and onto the schedule.
/// At that point it isn't a forecast, it's an instruction, and it shouldn't need a tap
/// to find.
struct WeatherAlertBanner: View {
    let advisory: WeatherAdvisory

    var body: some View {
        NavigationLink(value: WeatherRoute.forecast) {
            HStack(spacing: 12) {
                Image(systemName: advisory.severity.symbol)
                    .appFont(20, weight: .bold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(advisory.severity.label) · \(advisory.source)".uppercased())
                        .appFont(12, weight: .heavy)
                        .tracking(1.6)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(advisory.summary)
                        .appFont(17, weight: .bold)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .appFont(12, weight: .bold)
                    .accessibilityHidden(true)
            }
            // An alert is `signal`, the same red as the now line: the one thing allowed to
            // shout over the on-air glow.
            .foregroundStyle(Theme.night)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(advisory.severity.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The same advisory on the weather screen itself, where there's room for the region it
/// covers and a link out to the full text.
struct WeatherAlertCard: View {
    let advisory: WeatherAdvisory

    var body: some View {
        Link(destination: advisory.detailsURL) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: advisory.severity.symbol)
                        .appFont(15, weight: .semibold)
                        .accessibilityHidden(true)
                    Text(advisory.severity.label.uppercased())
                        .appFont(13, weight: .heavy)
                        .tracking(2)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .appFont(12, weight: .semibold)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(advisory.severity.tint)

                Text(advisory.summary)
                    .appFont(17, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text([advisory.region, advisory.source].compactMap { $0 }.joined(separator: " · "))
                    .appFont(13)
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.nightRaised)
            .overlay(Rectangle().strokeBorder(advisory.severity.tint, lineWidth: 1.5))
            .contentShape(Rectangle())
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
                .symbolRenderingMode(.hierarchical)
                .appFont(12, weight: .semibold)
                .foregroundStyle(Theme.inkMuted)
            Text(Format.temperature(hour.temperature))
                .appFont(12, weight: .bold)
                .foregroundStyle(Theme.ink)
            if hour.precipitationChance >= 0.2 {
                Text(Format.percent(hour.precipitationChance))
                    .appFont(12, weight: .bold)
                    .foregroundStyle(Theme.rain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(for: hour))
    }

    /// The rain chance is said whenever it's drawn, which the label used to leave out.
    static func spokenLabel(for hour: HourConditions) -> String {
        var label = "At set time: \(Format.temperature(hour.temperature)), \(hour.condition)"
        if hour.precipitationChance >= 0.2 {
            label += ", \(Format.percent(hour.precipitationChance)) chance of rain"
        }
        return label
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
                            .appFont(12)
                            .foregroundStyle(Theme.inkFaint)
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
        .appFont(12, weight: .medium)
        .foregroundStyle(Theme.inkMuted)
    }
}

extension AdvisorySeverity {
    /// Severe and worse are alerts, so `signal`. Below that an advisory is something to
    /// know rather than act on, and stays in the text colours: never `sodium`, which
    /// would read as on air, and never `rain`, which is only the chance of it.
    var tint: Color {
        switch self {
        case .extreme, .severe: return Theme.signal
        case .moderate: return Theme.ink
        case .minor, .unknown: return Theme.inkMuted
        }
    }
}
