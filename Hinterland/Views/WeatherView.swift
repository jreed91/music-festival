import SwiftUI

/// Pushed from the schedule. Kept out of `Performance`'s destination so the schedule's
/// navigation stack can carry both.
enum WeatherRoute: Hashable {
    case forecast
}

/// The forecast over the amphitheater: any active advisories, what it's doing now, the
/// next day of hours, and a high/low for each day of the festival.
///
/// Everything here comes from the cached snapshot, so the screen still opens with no
/// signal — it just shows how old what it's showing is.
struct WeatherView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(WeatherStore.self) private var weather

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let snapshot = weather.snapshot {
                    ForEach(snapshot.alertsBySeverity) { advisory in
                        WeatherAlertCard(advisory: advisory)
                    }
                    if let current = snapshot.current {
                        currentCard(current)
                    }
                    hourlyStrip(snapshot)
                    festivalDays(snapshot)
                } else {
                    noForecast
                }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .navigationTitle("Weather")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await weather.refresh(force: true) }
        .task { await weather.refresh() }
    }

    // MARK: - Now

    private func currentCard(_ current: CurrentConditions) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.temperature(current.temperature))
                        .appFont(56, weight: .semibold, design: .rounded)
                        .foregroundStyle(.white)
                    Text(current.condition)
                        .appFont(15, weight: .medium)
                        .foregroundStyle(Theme.secondaryText)
                    if current.showsApparentTemperature {
                        Text("Feels like \(Format.temperature(current.apparentTemperature))")
                            .appFont(13)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: current.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .appFont(46)
                    .padding(.top, 6)
            }

            Divider().overlay(Theme.hairline)

            // Two columns rather than a row of four: "12 mph NNW" doesn't survive a
            // quarter of a phone's width at a legible size.
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 12) {
                WeatherStat(symbol: "wind", label: "Wind",
                            value: "\(Format.windSpeed(current.windSpeed)) \(current.windDirection)")
                if let gust = current.windGust {
                    WeatherStat(symbol: "wind.circle", label: "Gusts",
                                value: Format.windSpeed(gust))
                }
                WeatherStat(symbol: "humidity", label: "Humidity",
                            value: Format.percent(current.humidity))
                WeatherStat(symbol: "sun.max.trianglebadge.exclamationmark", label: "UV index",
                            value: "\(current.uvIndex) · \(current.uvCategory)")
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Theme.accent.opacity(0.18), Theme.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    // MARK: - Hourly

    @ViewBuilder
    private func hourlyStrip(_ snapshot: WeatherSnapshot) -> some View {
        let hours = snapshot.upcomingHours()
        if !hours.isEmpty {
            WeatherSection(title: "Next 24 hours", symbol: "clock") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(hours) { hour in
                            VStack(spacing: 6) {
                                Text(Format.hour(hour.date))
                                    .appFont(11, weight: .semibold)
                                    .foregroundStyle(Theme.secondaryText)
                                Image(systemName: hour.symbolName)
                                    .symbolRenderingMode(.multicolor)
                                    .appFont(18)
                                    .frame(height: 22)
                                Text(Format.temperature(hour.temperature))
                                    .appFont(14, weight: .semibold, design: .rounded)
                                    .foregroundStyle(.white)
                                // Only worth the ink once rain is actually plausible, but
                                // the row still reserves its height so the strip doesn't
                                // jog up and down between hours.
                                Text(hour.precipitationChance >= 0.1
                                     ? Format.percent(hour.precipitationChance) : "")
                                    .appFont(10, weight: .semibold)
                                    .foregroundStyle(Theme.rain)
                                    .frame(height: 12)
                            }
                            .frame(minWidth: 40)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - The weekend

    private func festivalDays(_ snapshot: WeatherSnapshot) -> some View {
        WeatherSection(title: "The weekend", symbol: "calendar") {
            VStack(spacing: 0) {
                ForEach(store.days) { day in
                    dayRow(day, conditions: snapshot.day(for: day, in: store.data.timeZone))
                    if day.id != store.days.last?.id {
                        Divider().overlay(Theme.hairline).padding(.leading, 14)
                    }
                }
            }
        }
    }

    private func dayRow(_ day: FestivalDay, conditions: DayConditions?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.weekday)
                    .appFont(15, weight: .semibold)
                    .foregroundStyle(.white)
                Text(Format.dayLabel(day))
                    .appFont(11)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .frame(width: 78, alignment: .leading)

            if let conditions {
                Image(systemName: conditions.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .appFont(20)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conditions.condition)
                        .appFont(12)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if conditions.precipitationChance >= 0.1 {
                            Label(Format.percent(conditions.precipitationChance),
                                  systemImage: "umbrella")
                                .appFont(10, weight: .semibold)
                                .foregroundStyle(Theme.rain)
                        }
                        if let sunset = conditions.sunset {
                            Label(Format.time(sunset), systemImage: "sunset")
                                .appFont(10, weight: .semibold)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }

                Spacer(minLength: 0)

                Text(Format.temperature(conditions.high))
                    .appFont(17, weight: .semibold, design: .rounded)
                    .foregroundStyle(.white)
                Text(Format.temperature(conditions.low))
                    .appFont(17, weight: .regular, design: .rounded)
                    .foregroundStyle(Theme.tertiaryText)
            } else {
                // WeatherKit reaches about ten days out. Before that the honest answer
                // is that nobody knows yet.
                Text("Too far out to forecast")
                    .appFont(12)
                    .foregroundStyle(Theme.tertiaryText)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
    }

    // MARK: - Empty state and footer

    private var noForecast: some View {
        EmptyStateView(
            symbol: weather.isRefreshing ? "arrow.clockwise" : "cloud.slash",
            title: weather.isRefreshing ? "Fetching the forecast" : "No forecast yet",
            message: weather.isRefreshing
                ? "One moment."
                : "The forecast needs a signal the first time. Once it's loaded it stays "
                  + "on your phone and opens offline like everything else here.")
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                Task { await weather.refresh(force: true) }
            } label: {
                HStack(spacing: 6) {
                    if weather.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh")
                }
                .appFont(13, weight: .semibold)
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(weather.isRefreshing)

            if let error = weather.lastError {
                Text(error)
                    .appFont(11)
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
            }

            if let snapshot = weather.snapshot {
                Text("Updated \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))"
                   + " · \(store.map.venue.name)")
                    .appFont(11)
                    .foregroundStyle(Theme.tertiaryText)
                    .multilineTextAlignment(.center)
            }

            WeatherAttributionView(attribution: weather.snapshot?.attribution)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

// MARK: - Pieces

/// A titled card. The weather screen is a stack of these and they all want the same
/// surface, corner radius and header treatment.
private struct WeatherSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .appFont(12, weight: .bold)
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 2)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeatherStat: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .appFont(13)
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .appFont(10, weight: .semibold)
                    .foregroundStyle(Theme.tertiaryText)
                Text(value)
                    .appFont(13, weight: .medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}
