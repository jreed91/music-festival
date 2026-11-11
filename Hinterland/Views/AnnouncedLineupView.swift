import Combine
import SwiftUI

/// Next year's bill as announced: each day's names in billing order, no times, no stages.
///
/// The first tab's root once this year's festival is over and next year's bill is out
/// (see `FestivalHomeView`): the app has moved on to the next summer, with a countdown to
/// it, and this year's recap is a card away. Set like `PastYearView` because it is the
/// same kind of thing, a poster, read from the other end. No artist taps through: these
/// artists have no pages in this build, and a set can't be starred until it has a time.
/// When next year's schedule arrives the Schedule tab takes over and
/// `ScheduleStore.upcomingLineup` stops offering this screen.
struct AnnouncedLineupView: View {
    let lineup: AnnouncedLineup

    @Environment(ScheduleStore.self) private var store

    /// Read on appear and on the hour. The countdown is in days, so nothing finer matters.
    @State private var now = Date()
    private let ticker = Timer.publish(every: 3600, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.data.festival.name) · the lineup".uppercased())
                        .appFont(12, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkFaint)
                    Text(String(lineup.year))
                        .marqueeFont(96)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let range = Format.dateRange(lineup.startDate, lineup.endDate) {
                        Text(range.uppercased())
                            .appFont(15, weight: .bold)
                            .tracking(1.6)
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let countdown {
                        Text(countdown.uppercased())
                            .appFont(13, weight: .bold)
                            .tracking(2.4)
                            .foregroundStyle(Theme.sodium)
                            .contentTransition(.numericText())
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }

                lastYear
                    .padding(.top, 16)

                ForEach(lineup.days) { day in
                    dayBlock(day)
                }

                footer
                    .padding(.top, 24)

                Horizon()
                    .padding(.top, 48)
                    .padding(.horizontal, -22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
        .background(Theme.night)
        .navigationTitle(String(lineup.year))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: RecapRoute.schedule) {
                    Image(systemName: "calendar")
                }
                .tint(Theme.ink)
                .accessibilityLabel("\(String(store.data.festival.year)) schedule")
            }
        }
        .onReceive(ticker) { now = $0 }
        .onAppear { now = Date() }
    }

    // MARK: Countdown

    /// "262 days to go", "Tomorrow", "This weekend", or nil once the weekend has passed
    /// and the schedule should have long since taken over.
    private var countdown: String? {
        guard let days = AnnouncedLineupFormat.daysUntil(lineup.startDate, from: now) else {
            return nil
        }
        switch days {
        case ..<(-2): return nil
        case ...0: return "This weekend"
        case 1: return "Tomorrow"
        default: return "\(days) days to go"
        }
    }

    // MARK: Last year

    /// The way back to this year's weekend: the recap that had the tab until next year's
    /// bill took it, with your ratings, the crowd's best sets and the share card.
    private var lastYear: some View {
        NavigationLink(value: RecapRoute.recap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THAT'S A WRAP")
                        .appFont(13, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkFaint)
                    Text("Your \(String(store.data.festival.year))".uppercased())
                        .listNameFont()
                        .foregroundStyle(Theme.ink)
                    Text("Your recap, your ratings and the crowd's best sets")
                        .appFont(15)
                        .foregroundStyle(Theme.inkMuted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .appFont(12, weight: .semibold)
                    .foregroundStyle(Theme.inkFaint)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(Theme.nightRaised)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One day: its name and date over the 2pt rule, the headliner in Six Caps, everyone
    /// else in `list-name`, the way the poster stacks them.
    private func dayBlock(_ day: AnnouncedDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: day.weekday, detail: AnnouncedLineupFormat.monthDay(day.date))
                .padding(.top, 12)
            ForEach(Array(day.artists.enumerated()), id: \.element.id) { index, artist in
                artistRow(artist, isHeadliner: index == 0)
                    .padding(.vertical, index == 0 ? 10 : 8)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
            }
        }
    }

    private func artistRow(_ artist: AnnouncedArtist, isHeadliner: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if artist.isSpecial {
                Text("A special performance by".uppercased())
                    .appFont(12, weight: .bold)
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Headliners in Six Caps, like the top of a poster; everyone under them in the
            // list's heavy Barlow, which is the size a name can still be read at.
            Group {
                if isHeadliner {
                    Text(artist.name.uppercased())
                        .marqueeFont(56)
                        .foregroundStyle(Theme.ink)
                } else {
                    Text(artist.name.uppercased())
                        .listNameFont()
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set times and stages aren't out yet. When the festival publishes them they "
               + "arrive in the Schedule tab, where you can star sets and get reminders.")
                .readingFont(15)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: store.data.festival.website + "/lineup") {
                Link(destination: url) {
                    Label("Lineup on hinterlandiowa.com", systemImage: "arrow.up.right")
                }
                .buttonStyle(GlowButtonStyle(.quiet))
            }
        }
    }
}

/// A day heading's date. The file's dates are bare `yyyy-MM-dd` days, read and written in
/// UTC so the day never shifts with the phone's time zone.
enum AnnouncedLineupFormat {
    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        return formatter
    }()

    /// Whole days from today to `day`, both read as dates in the festival's time zone, so
    /// the count ticks over at midnight in Iowa rather than wherever the phone is.
    static func daysUntil(_ day: String, from now: Date) -> Int? {
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = Format.timeZone
        local.dateFormat = "yyyy-MM-dd"
        guard let target = parser.date(from: day),
              let today = parser.date(from: local.string(from: now)) else { return nil }
        // Both are UTC midnights, so count in UTC too: a calendar in Central would see
        // the spring clock change as a day an hour short and count one fewer.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.dateComponents([.day], from: today, to: target).day
    }

    /// "July 30", or the raw string if it doesn't parse.
    static func monthDay(_ day: String) -> String {
        guard let date = parser.date(from: day) else { return day }
        return monthDayFormatter.string(from: date)
    }
}
