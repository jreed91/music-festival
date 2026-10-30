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
            VStack(alignment: .leading, spacing: 14) {
                header

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
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Theme.night)
        .navigationTitle("Weather")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await weather.refresh(force: true) }
        .task { await weather.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("OVER \(store.map.venue.name)".uppercased())
                .appFont(12, weight: .bold)
                .tracking(2.4)
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            Text("THE SKY")
                .marqueeFont(88)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Now

    private func currentCard(_ current: CurrentConditions) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Format.temperature(current.temperature))
                        .marqueeFont(96)
                        .foregroundStyle(Theme.ink)
                        .fixedSize()
                    Text(current.condition.uppercased())
                        .appFont(20, weight: .medium)
                        .tracking(0.8)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if current.showsApparentTemperature {
                        Text("Feels like \(Format.temperature(current.apparentTemperature))")
                            .appFont(15)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Image(systemName: current.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .appFont(40, weight: .semibold)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.top, 10)
                    .accessibilityHidden(true)
            }

            Rectangle().fill(Theme.hairline).frame(height: 1)

            // Two columns rather than a row of four: "12 mph NNW" doesn't survive a
            // quarter of a phone's width at a legible size.
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                GridItem(.flexible(), alignment: .topLeading)],
                      alignment: .leading, spacing: 14) {
                WeatherStat(symbol: "wind", label: "Wind",
                            value: "\(Format.windSpeed(current.windSpeed)) \(current.windDirection)")
                if let gust = current.windGust {
                    WeatherStat(symbol: "wind.circle", label: "Gusts",
                                value: Format.windSpeed(gust))
                }
                WeatherStat(symbol: "humidity", label: "Humidity",
                            value: Format.percent(current.humidity))
                WeatherStat(symbol: "sun.max", label: "UV index",
                            value: "\(current.uvIndex) · \(current.uvCategory)")
            }
        }
        .padding(16)
        .background(Theme.nightRaised)
    }

    // MARK: - Hourly

    @ViewBuilder
    private func hourlyStrip(_ snapshot: WeatherSnapshot) -> some View {
        let hours = snapshot.upcomingHours()
        if !hours.isEmpty {
            WeatherSection(title: "Next 24 hours") {
                // Sideways on purpose: a day of hours is a strip you drag, and the next
                // one peeking in at the edge says there's more.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(hours) { hour in
                            VStack(spacing: 6) {
                                Text(Format.hour(hour.date).uppercased())
                                    .appFont(11, weight: .bold)
                                    .tracking(1.2)
                                    .foregroundStyle(Theme.inkFaint)
                                    .fixedSize()
                                Image(systemName: hour.symbolName)
                                    .symbolRenderingMode(.hierarchical)
                                    .appFont(18, weight: .semibold)
                                    .foregroundStyle(Theme.inkMuted)
                                    .frame(height: 24)
                                Text(Format.temperature(hour.temperature))
                                    .appFont(17, weight: .bold)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize()
                                // Only worth the ink once rain is actually plausible, but
                                // the row still reserves its height so the strip doesn't
                                // jog up and down between hours.
                                Text(hour.precipitationChance >= 0.1
                                     ? Format.percent(hour.precipitationChance) : " ")
                                    .appFont(12, weight: .bold)
                                    .foregroundStyle(Theme.rain)
                                    .fixedSize()
                            }
                            .frame(minWidth: 40)
                            // One stop per hour, read as a sentence, rather than the
                            // hour, the temperature and the rain chance as separate stops.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(spokenHour(hour))
                        }
                    }
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private func spokenHour(_ hour: HourConditions) -> String {
        var label = "\(Format.hour(hour.date)), \(Format.temperature(hour.temperature)), "
            + hour.condition
        if hour.precipitationChance >= 0.1 {
            label += ", \(Format.percent(hour.precipitationChance)) chance of rain"
        }
        return label
    }

    // MARK: - The weekend

    private func festivalDays(_ snapshot: WeatherSnapshot) -> some View {
        WeatherSection(title: "The weekend") {
            VStack(spacing: 0) {
                ForEach(store.days) { day in
                    dayRow(day, conditions: snapshot.day(for: day, in: store.data.timeZone))
                        .overlay(alignment: .bottom) {
                            if day.id != store.days.last?.id {
                                Rectangle().fill(Theme.hairline).frame(height: 1)
                            }
                        }
                }
            }
        }
    }

    /// The day's name and its high and low on one line, everything else wrapping under
    /// it, so nothing has to squeeze into a fixed column at large text sizes.
    private func dayRow(_ day: FestivalDay, conditions: DayConditions?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.weekday.uppercased())
                        .marqueeFont(40)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Format.dayLabel(day).uppercased())
                        .appFont(11, weight: .bold)
                        .tracking(1.4)
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer(minLength: 8)
                if let conditions {
                    Text(Format.temperature(conditions.high))
                        .appFont(20, weight: .bold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .fixedSize()
                    Text(Format.temperature(conditions.low))
                        .appFont(20, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize()
                }
            }

            if let conditions {
                FlowLayout(spacing: 12, lineSpacing: 4) {
                    Label(conditions.condition, systemImage: conditions.symbolName)
                        .symbolRenderingMode(.hierarchical)
                        .appFont(15)
                        .foregroundStyle(Theme.inkMuted)
                    if conditions.precipitationChance >= 0.1 {
                        Label(Format.percent(conditions.precipitationChance),
                              systemImage: "umbrella")
                            .appFont(13, weight: .bold)
                            .foregroundStyle(Theme.rain)
                    }
                    if let sunset = conditions.sunset {
                        Label(Format.time(sunset), systemImage: "sunset")
                            .appFont(13, weight: .bold)
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
            } else {
                // WeatherKit reaches about ten days out. Before that the honest answer
                // is that nobody knows yet.
                Text("Too far out to forecast.")
                    .appFont(15)
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.vertical, 12)
        // High and low sit side by side as two bare numbers; spoken, they need saying
        // which is which.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenDay(day, conditions: conditions))
    }

    private func spokenDay(_ day: FestivalDay, conditions: DayConditions?) -> String {
        var parts = [day.weekday, Format.dayLabel(day)]
        if let conditions {
            parts.append(conditions.condition)
            parts.append("high \(Format.temperature(conditions.high))")
            parts.append("low \(Format.temperature(conditions.low))")
            if conditions.precipitationChance >= 0.1 {
                parts.append("\(Format.percent(conditions.precipitationChance)) chance of rain")
            }
            if let sunset = conditions.sunset {
                parts.append("sunset \(Format.time(sunset))")
            }
        } else {
            parts.append("Too far out to forecast")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Empty state and footer

    private var noForecast: some View {
        EmptyStateView(
            title: weather.isRefreshing ? "Fetching the forecast" : "No forecast yet",
            message: weather.isRefreshing
                ? "One moment."
                : "The forecast needs a signal the first time. Once it's loaded it stays "
                  + "on your phone and opens offline like everything else here.",
            headline: weather.isRefreshing ? "Stand by" : "Dead air")
            .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                Task { await weather.refresh(force: true) }
            } label: {
                HStack(spacing: 8) {
                    if weather.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.ink)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh")
                }
            }
            .buttonStyle(GlowButtonStyle(.quiet))
            .disabled(weather.isRefreshing)

            if let error = weather.lastError {
                Text(error)
                    .appFont(13)
                    .foregroundStyle(Theme.signal)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let snapshot = weather.snapshot {
                Text("Updated \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))"
                   + " · \(store.map.venue.name)")
                    .appFont(13)
                    .foregroundStyle(Theme.inkFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WeatherAttributionView(attribution: weather.snapshot?.attribution)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }
}

// MARK: - Pieces

/// A section of the forecast: a callsign over the 2pt rule, then its rows straight on
/// `night`, the way every other screen groups things.
private struct WeatherSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: title)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeatherStat: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .appFont(13, weight: .semibold)
                .foregroundStyle(Theme.inkFaint)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .appFont(11, weight: .bold)
                    .tracking(1.4)
                    .foregroundStyle(Theme.inkFaint)
                Text(value)
                    .appFont(17, weight: .semibold)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
