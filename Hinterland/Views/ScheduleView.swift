import Combine
import SwiftUI

/// The full schedule, one day at a time, with an optional stage filter.
struct ScheduleView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(WeatherStore.self) private var weather

    @State private var selectedDay: String?
    @State private var stageFilter: String?
    @State private var now = Date()

    /// Keeps the NOW badge and the Now-playing card honest without a per-second timer.
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var day: FestivalDay? {
        store.days.first { $0.date == selectedDay } ?? store.defaultDay()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    // A tornado warning outranks whatever is about to start on the Main
                    // Stage, so it goes above the card that says so.
                    if let alert = weather.snapshot?.urgentAlert {
                        WeatherAlertBanner(advisory: alert)
                    }

                    if let live = store.liveNow(at: now).first ?? store.upNext(after: now).first {
                        NowCard(performance: live, isLive: live.isLive(at: now))
                    }
                    // Under the Now card rather than over it: what's playing is why this
                    // screen exists, the weather is the context you read it in.
                    WeatherCard()
                        .padding(.bottom, 2)

                    if let day {
                        ForEach(store.performances(on: day, stage: stageFilter)) { performance in
                            NavigationLink(value: performance) {
                                PerformanceRow(performance: performance)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    freshness
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .navigationDestination(for: Performance.self) { performance in
                ArtistDetailView(artistID: performance.artistId)
            }
            .navigationDestination(for: WeatherRoute.self) { _ in
                WeatherView()
            }
            .refreshable {
                await store.refresh()
                await weather.refresh(force: true)
            }
            .onReceive(ticker) { now = $0 }
            .onAppear { selectedDay = selectedDay ?? store.defaultDay()?.date }
        }
    }

    /// Where the set times came from and when. The Info tab used to carry this alongside
    /// its own refresh button; pull-to-refresh on this screen does the same job, so all
    /// that's left to say is how stale the list is and whether the last check failed.
    private var freshness: some View {
        VStack(spacing: 4) {
            if let error = store.refreshError {
                Text(error).foregroundStyle(Theme.warning)
            }
            Text("Set times last updated "
               + store.data.generatedAt.formatted(date: .abbreviated, time: .shortened)
               + ". Pull down to check for updates.")
                .foregroundStyle(Theme.tertiaryText)
        }
        .font(.system(size: 11))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    private var header: some View {
        VStack(spacing: 10) {
            dayPicker
            stagePicker
        }
        .padding(.vertical, 10)
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
        }
    }

    private var dayPicker: some View {
        HStack(spacing: 8) {
            ForEach(store.days) { candidate in
                let isSelected = candidate.date == (day?.date ?? "")
                Button {
                    selectedDay = candidate.date
                } label: {
                    VStack(spacing: 2) {
                        Text(candidate.shortWeekday.uppercased())
                            .font(.system(size: 12, weight: .bold))
                        Text(Format.dayLabel(candidate))
                            .font(.system(size: 10, weight: .medium))
                            .opacity(0.75)
                        if let conditions = forecast(for: candidate) {
                            HStack(spacing: 3) {
                                // Multicolour would fight the amber fill on the selected
                                // day, so the selected one inherits the dark foreground.
                                Image(systemName: conditions.symbolName)
                                    .symbolRenderingMode(isSelected ? .monochrome : .multicolor)
                                    .font(.system(size: 9))
                                Text(Format.temperature(conditions.high))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .padding(.top, 1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(isSelected ? Theme.background : .white)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Theme.accent : Theme.surface)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var stagePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All stages", isSelected: stageFilter == nil, tint: .white) {
                    stageFilter = nil
                }
                ForEach(store.data.stageNames, id: \.self) { name in
                    let stage = Stage(name: name)
                    chip(title: stage.displayName,
                         isSelected: stageFilter == name,
                         tint: stage.color) {
                        stageFilter = stageFilter == name ? nil : name
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// The day's high and symbol under its label in the picker — nil until WeatherKit's
    /// ten-day horizon reaches that far, which for a festival still weeks out it hasn't.
    private func forecast(for day: FestivalDay) -> DayConditions? {
        weather.snapshot?.day(for: day, in: store.data.timeZone)
    }

    private func chip(title: String, isSelected: Bool, tint: Color,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.background : tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? tint : tint.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Whatever is happening right now, or the next thing if the stages are dark.
private struct NowCard: View {
    let performance: Performance
    let isLive: Bool

    @Environment(ScheduleStore.self) private var store

    var body: some View {
        NavigationLink(value: performance) {
            HStack(spacing: 14) {
                ArtistImage(artist: store.data.artist(id: performance.artistId), size: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(isLive ? "ON NOW" : "UP NEXT")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.accent)
                    Text(performance.artist)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        StageBadge(stage: Stage(name: performance.stage), compact: true)
                        Text(isLive
                             ? "until \(Format.time(performance.end))"
                             : Format.relative(performance.start))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.surface],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
