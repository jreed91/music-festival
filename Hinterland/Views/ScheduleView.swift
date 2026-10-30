import Combine
import SwiftUI

/// The full schedule, one day at a time, with an optional stage filter.
///
/// Deliberately not the owner of a `NavigationStack`: this is the root of the first tab
/// while the festival is on, and a screen pushed from the recap once it's over.
/// `FestivalHomeView` owns the stack and decides which of those this is.
struct ScheduleView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(WeatherStore.self) private var weather

    @State private var selectedDay: String?
    @State private var stageFilter: String?
    @State private var now = Date()

    /// Keeps the NOW badge and the Now-playing card honest without a per-second timer.
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// `selectedDay` only ever holds a tap. Until there is one, the day tracks the clock,
    /// so the screen is already on today when it opens and rolls over with the date if it
    /// is left running.
    private var day: FestivalDay? {
        store.days.first { $0.date == selectedDay } ?? store.defaultDay(now: now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                title

                // A tornado warning outranks whatever is about to start on the Main
                // Stage, so it goes above the block that says so.
                if let alert = weather.snapshot?.urgentAlert {
                    WeatherAlertBanner(advisory: alert)
                }

                if let live = store.liveNow(at: now).first ?? store.upNext(after: now).first {
                    NowCard(performance: live, isLive: live.isLive(at: now), now: now)
                }
                // Under the Now block rather than over it: what's playing is why this
                // screen exists, the weather is the context you read it in.
                WeatherCard()

                if let day {
                    HourTimeline(performances: store.performances(on: day, stage: stageFilter),
                                 now: now)
                }

                freshness

                Horizon()
                    .padding(.top, 32)
                    .padding(.horizontal, -22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
        .background(Theme.night)
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        // The lineup is what this tab is, so the ten before it belong behind it
        // rather than in a fifth tab — which is also where the festival's own site
        // files them, under Lineup.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: PastLineupRoute.index) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .tint(Theme.ink)
                .accessibilityLabel("Past lineups")
            }
        }
        .refreshable {
            await store.refresh()
            await weather.refresh(force: true)
        }
        .onReceive(ticker) { now = $0 }
        // The ticker doesn't run while the app is backgrounded, so catch up on the
        // way back in rather than showing yesterday for up to half a minute.
        .onAppear { now = Date() }
    }

    /// Where the set times came from and when. The Info tab used to carry this alongside
    /// its own refresh button; pull-to-refresh on this screen does the same job, so all
    /// that's left to say is how stale the list is and whether the last check failed.
    private var freshness: some View {
        VStack(spacing: 4) {
            if let error = store.refreshError {
                Text(error).foregroundStyle(Theme.signal)
            }
            Text("Set times last updated "
               + store.data.generatedAt.formatted(date: .abbreviated, time: .shortened)
               + ". Pull down to check for updates.")
                .foregroundStyle(Theme.inkFaint)
        }
        .appFont(13)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    /// The day's name, huge, under where you are.
    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(store.data.festival.name) · \(store.data.festival.city)".uppercased())
                .appFont(12, weight: .bold)
                .tracking(2.4)
                .foregroundStyle(Theme.inkFaint)
            Text((day?.weekday ?? "Schedule").uppercased())
                .marqueeFont(96)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            DayPresets(days: store.days,
                       selected: day?.date,
                       forecast: forecast(for:),
                       spokenLabel: spokenDay) { selectedDay = $0.date }
            stagePicker
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Theme.night)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    /// Wrapped rather than scrolled sideways, so no stage is ever off the edge.
    private var stagePicker: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            FilterChip(title: "All stages", isOn: stageFilter == nil) {
                stageFilter = nil
            }
            ForEach(store.data.stageNames, id: \.self) { name in
                let stage = Stage(name: name)
                FilterChip(title: stage.displayName, isOn: stageFilter == name,
                           onColor: stage.color) {
                    stageFilter = stageFilter == name ? nil : name
                }
            }
        }
    }

    private func spokenDay(_ day: FestivalDay) -> String {
        var label = "\(day.weekday), \(Format.dayLabel(day))"
        if let conditions = forecast(for: day) {
            label += ", high of \(Format.temperature(conditions.high)), \(conditions.condition)"
        }
        return label
    }

    /// The day's high and symbol under its label in the picker — nil until WeatherKit's
    /// ten-day horizon reaches that far, which for a festival still weeks out it hasn't.
    private func forecast(for day: FestivalDay) -> DayConditions? {
        weather.snapshot?.day(for: day, in: store.data.timeZone)
    }

}

/// Whatever is happening right now, or the next thing if the stages are dark: the
/// NowPlaying block of the design system. The on-air name is the one glowing thing on
/// the screen.
private struct NowCard: View {
    let performance: Performance
    let isLive: Bool
    let now: Date

    var body: some View {
        let stage = Stage(name: performance.stage)
        NavigationLink(value: performance) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(isLive ? "Now playing" : "Up next") · \(stage.displayName)".uppercased())
                    .appFont(13, weight: .bold)
                    .tracking(2.4)
                    .foregroundStyle(isLive ? Theme.sodium : Theme.inkFaint)
                Text(performance.artist.uppercased())
                    .marqueeFont(isLive ? 120 : 88)
                    .foregroundStyle(isLive ? Theme.sodium : Theme.ink)
                    .onAirGlow(isLive)
                    .fixedSize(horizontal: false, vertical: true)
                Text(readout.uppercased())
                    .appFont(20, weight: .medium)
                    .tracking(0.8)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
        .accessibilityInputLabels([performance.artist])
    }

    /// "9:30 — 11:00 PM · 48 MIN LEFT", or when the next set starts.
    private var readout: String {
        let times = "\(Format.time(performance.start)) — \(Format.time(performance.end))"
        if isLive {
            let left = max(0, Int(performance.end.timeIntervalSince(now) / 60))
            return "\(times) · \(left) min left"
        }
        return "\(times) · \(Format.relative(performance.start, from: now))"
    }

    private var spokenSummary: String {
        let stage = Stage(name: performance.stage).displayName
        return isLive
            ? "Now playing: \(performance.artist), \(stage), until \(Format.time(performance.end))"
            : "Up next: \(performance.artist), \(stage), \(Format.relative(performance.start, from: now))"
    }
}
