import SwiftUI
import UserNotifications

/// The sets you starred, grouped by day, with overlap warnings and reminder settings.
struct MyLineupView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(Favorites.self) private var favorites
    @Environment(NotificationManager.self) private var notifications

    @State private var showingSettings = false

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
                    EmptyStateView(
                        symbol: "star",
                        title: "No sets starred yet",
                        message: "Tap the star on any set in the Schedule and it shows up here, "
                               + "with a reminder before it starts.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background)
                } else {
                    list
                }
            }
            .navigationTitle("My Lineup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: notifications.isEnabled ? "bell.fill" : "bell.slash")
                    }
                    .tint(Theme.accent)
                }
            }
            .sheet(isPresented: $showingSettings) {
                ReminderSettingsView()
            }
            .navigationDestination(for: Performance.self) { performance in
                ArtistDetailView(artistID: performance.artistId)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !conflicts.isEmpty {
                    conflictBanner
                }

                ForEach(byDay, id: \.day.id) { group in
                    Text("\(group.day.weekday.uppercased()) · \(Format.dayLabel(group.day))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.top, 8)

                    ForEach(group.sets) { performance in
                        NavigationLink(value: performance) {
                            PerformanceRow(
                                performance: performance,
                                showsConflictWarning: favorites.isInConflict(performance,
                                                                            in: store.data))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
    }

    private var conflictBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(conflicts.count) overlapping \(conflicts.count == 1 ? "set" : "sets")",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.warning)

            ForEach(Array(conflicts.enumerated()), id: \.offset) { _, pair in
                Text("\(pair.0.artist) and \(pair.1.artist) overlap "
                     + "\(Format.time(max(pair.0.start, pair.1.start)))–"
                     + "\(Format.time(min(pair.0.end, pair.1.end))).")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.warning.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 12)
    }
}

/// Reminder on/off and how much warning you get.
struct ReminderSettingsView: View {
    @Environment(NotificationManager.self) private var notifications
    @Environment(ScheduleStore.self) private var store
    @Environment(Favorites.self) private var favorites
    @Environment(\.dismiss) private var dismiss

    private let leadOptions = [5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        // Bound separately rather than shadowing, so the closures below unambiguously
        // refer to the environment object.
        @Bindable var bindable = notifications

        NavigationStack {
            Form {
                Section {
                    Toggle("Remind me before my sets", isOn: $bindable.isEnabled)
                        .tint(Theme.accent)
                } footer: {
                    Text("Reminders are scheduled on your phone, so they still fire with no "
                       + "signal or in airplane mode.")
                }

                if notifications.isEnabled {
                    Section("How much warning") {
                        Picker("Lead time", selection: $bindable.leadMinutes) {
                            ForEach(leadOptions, id: \.self) { minutes in
                                Text("\(minutes) minutes before").tag(minutes)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                if notifications.authorization == .denied {
                    Section {
                        Label("Notifications are turned off for Hinterland in iOS Settings.",
                              systemImage: "exclamationmark.circle")
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Theme.accent)
                }
            }
        }
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

    private func applyReminders() {
        if notifications.isEnabled {
            notifications.reschedule(for: favorites.performances(in: store.data),
                                     festivalTimeZone: store.data.timeZone)
        } else {
            notifications.cancelAll()
        }
    }
}
