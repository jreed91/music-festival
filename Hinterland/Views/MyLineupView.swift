import Combine
import SwiftUI
import UserNotifications

/// The sets you starred, day by day on the same hour timeline as the schedule, with
/// clash markers on sets that overlap and reminder settings.
struct MyLineupView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Favorites.self) private var favorites
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingSettings = false
    @State private var now = Date()

    /// Moves the now line and the on-air row along without a per-second timer.
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var starred: [Performance] { favorites.performances(in: store.data) }
    private var conflicts: [(Performance, Performance)] { favorites.conflicts(in: store.data) }

    /// Starred sets bucketed into the festival day they belong to, in order.
    private var byDay: [(day: FestivalDay, sets: [Performance])] {
        store.days.compactMap { day in
            let sets = day.sets.filter { favorites.contains($0) }.sorted { $0.start < $1.start }
            return sets.isEmpty ? nil : (day, sets)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if starred.isEmpty {
                    DeadAirScreen(
                        title: "No sets starred yet",
                        message: "Star a set on the Schedule and it shows up here, with a "
                               + "reminder before it starts.")
                } else {
                    list
                }
            }
            .navigationTitle("My Lineup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Ratings before alerts: after the weekend the scoreboard is the reason
                // to open this tab at all, and the reminders have long since fired.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: RatingsRoute.recap) {
                        Image(systemName: "star.leadinghalf.filled")
                    }
                    .tint(Theme.ink)
                    .accessibilityLabel("My Ratings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: notifications.isEnabled ? "bell.fill" : "bell.slash")
                    }
                    .tint(Theme.ink)
                    .accessibilityLabel("Alerts")
                }
            }
            .sheet(isPresented: $showingSettings) {
                AlertSettingsView()
            }
            .navigationDestination(for: Performance.self) { performance in
                ArtistDetailView(artistID: performance.artistId)
            }
            .navigationDestination(for: RatingsRoute.self) { _ in
                RatingsView()
            }
        }
    }

    private var list: some View {
        let clashing = Set(conflicts.flatMap { [$0.0.id, $0.1.id] })
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Lineup · \(starred.count) \(starred.count == 1 ? "set" : "sets")".uppercased())
                        .appFont(12, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkFaint)
                    Text("YOUR NIGHTS")
                        .marqueeFont(88)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                if !conflicts.isEmpty {
                    conflictBanner
                }

                ForEach(byDay, id: \.day.id) { group in
                    Text("\(group.day.weekday) · \(Format.dayLabel(group.day))".uppercased())
                        .appFont(15, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.top, 28)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Theme.ink).frame(height: 2)
                        }
                        .accessibilityLabel("\(group.day.weekday), \(Format.dayLabel(group.day))")
                        .accessibilityAddTraits(.isHeader)

                    HourTimeline(performances: group.sets, now: now, clashing: clashing)
                }

                Horizon()
                    .padding(.top, 48)
                    .padding(.horizontal, -22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
        .background(Theme.night)
        .onReceive(ticker) { date in
            withAnimation(reduceMotion ? nil : Motion.tick) { now = date }
        }
        .onAppear { now = Date() }
    }

    /// Every clash in one place, so none is only findable by scrolling to it.
    private var conflictBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(conflicts.count) \(conflicts.count == 1 ? "clash" : "clashes")".uppercased())
                .appFont(13, weight: .heavy)
                .tracking(2)
                .foregroundStyle(Theme.caution)

            ForEach(Array(conflicts.enumerated()), id: \.offset) { _, pair in
                Text("\(pair.0.artist) and \(pair.1.artist) overlap "
                     + "\(Format.time(max(pair.0.start, pair.1.start)))–"
                     + "\(Format.time(min(pair.0.end, pair.1.end))).")
                    .appFont(15)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.caution).frame(width: 3)
        }
        .padding(.top, 20)
    }
}

/// What the app is allowed to put in front of you: reminders before your sets, and the
/// Live Activity that sits on the Lock Screen while one is on.
struct AlertSettingsView: View {
    @Environment(NotificationManager.self) private var notifications
    @Environment(LiveActivityController.self) private var liveActivity
    @Environment(ScheduleStore.self) private var store
    @Environment(Favorites.self) private var favorites
    @Environment(\.dismiss) private var dismiss

    private let leadOptions = [5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        // Bound separately rather than shadowing, so the closures below unambiguously
        // refer to the environment object.
        @Bindable var bindable = notifications
        @Bindable var activity = liveActivity

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("MY LINEUP")
                        .appFont(12, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("ALERTS")
                        .marqueeFont(88)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)

                    SectionHeading(title: "Reminders")
                    Toggle("Remind me before my sets", isOn: $bindable.isEnabled)
                        .toggleStyle(GlowToggleStyle())
                        .padding(.top, 12)
                    note("Reminders are scheduled on your phone, so they still fire with no "
                       + "signal or in airplane mode.")

                    if notifications.isEnabled {
                        SectionHeading(title: "How much warning")
                        leadPresets(selection: $bindable.leadMinutes)
                            .padding(.top, 14)
                    }

                    if notifications.authorization == .denied {
                        problem("Notifications are turned off for Hinterland in iOS Settings.")
                    }

                    SectionHeading(title: "On the Lock Screen")
                    Toggle("Live Activity", isOn: $activity.isEnabled)
                        .toggleStyle(GlowToggleStyle())
                        .padding(.top, 12)

                    if !liveActivity.isPermittedBySystem {
                        problem("Live Activities are turned off for Hinterland in iOS Settings.")
                    } else if let reason = liveActivity.failureReason {
                        // Otherwise a card that never appears looks like a bug in the
                        // schedule rather than something iOS declined.
                        problem(reason)
                    }

                    note("Puts the starred set you're watching on the Lock Screen and in the "
                       + "Dynamic Island, from 90 minutes before it starts until it ends. It "
                       + "counts down on its own, so it keeps working with no signal.")

                    // Only ever true on a build whose App ID is missing the app group, which
                    // is a signing problem rather than anything the user did — but it's worth
                    // saying, because the symptom is a widget that sits there empty.
                    if !AppGroup.isAvailable {
                        problem("The Home Screen widget can't read your lineup on this build "
                              + "— its app group isn't set up.",
                                symbol: "square.grid.2x2")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Theme.nightSheet)
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.nightSheet, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.ink)
        .presentationBackground(Theme.nightSheet)
        .task { await notifications.refreshAuthorization() }
        .onChange(of: notifications.isEnabled) { _, enabled in
            Task {
                // Ask the first time the toggle goes on; fall back if the user says no.
                if enabled, notifications.authorization != .authorized {
                    let granted = await notifications.requestAuthorization()
                    if !granted { notifications.isEnabled = false }
                }
                applyReminders()
            }
        }
        .onChange(of: notifications.leadMinutes) { _, _ in applyReminders() }
    }

    /// The lead times as preset buttons, the same hardware as the day picker: the one
    /// you picked is lit.
    private func leadPresets(selection: Binding<Int>) -> some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(leadOptions, id: \.self) { minutes in
                let isSelected = selection.wrappedValue == minutes
                Button {
                    selection.wrappedValue = minutes
                } label: {
                    Text("\(minutes) MIN")
                        .appFont(15, weight: .bold)
                        .tracking(1.8)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Theme.sodium : Theme.inkMuted)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 72, minHeight: 44)
                        .background(Theme.glass, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isSelected ? Theme.sodium : Theme.hairline, lineWidth: 1))
                        .shadow(color: isSelected ? Theme.sodium.opacity(0.6) : .clear, radius: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(minutes) minutes before")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .appFont(15)
            .foregroundStyle(Theme.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }

    /// Something iOS or the build is refusing, in `signal`: it's the reason a switch
    /// above it does nothing.
    private func problem(_ text: String, symbol: String = "exclamationmark.circle") -> some View {
        Label(text, systemImage: symbol)
            .appFont(15, weight: .semibold)
            .foregroundStyle(Theme.signal)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
    }

    private func applyReminders() {
        if notifications.isEnabled {
            notifications.reschedule(for: favorites.performances(in: store.data),
                                     festivalTimeZone: store.data.timeZone)
        } else {
            notifications.cancelAll()
        }
    }
}
