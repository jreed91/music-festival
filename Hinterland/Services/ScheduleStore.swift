import Foundation
import Observation
import WidgetKit

/// Owns the festival schedule and guide.
///
/// Offline first: the bundled JSON always loads synchronously at launch, so the app is
/// fully usable in airplane mode with no cell service — which is the normal state of
/// affairs in a field in St. Charles. A newer copy, if one has been cached from a
/// previous refresh, wins over the bundle. Network refresh is strictly an upgrade path
/// and never blocks the UI.
@Observable
final class ScheduleStore {
    /// Set times shift during the weekend. Editing `Data/schedule.json` on the repo's
    /// default branch pushes an update to everyone without an App Store round trip.
    ///
    /// This points at the repository's default branch. If that branch is ever renamed,
    /// update the path here to match, or the fetch 404s and the app quietly keeps using
    /// its bundled copy.
    static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/jreed91/music-festival/main/Data/schedule.json"
    )!

    private(set) var data: FestivalData
    private(set) var guide: GuideData
    /// Georeferenced grounds map and its pins. Bundled only — it describes artwork that
    /// ships in the binary, so there is nothing to refresh.
    let map: MapData
    /// Food & drink stands by area. Bundled only; the lineup of vendors is settled well
    /// before gates and doesn't move during the weekend the way set times do.
    let vendors: VendorData
    /// Every Hinterland before this one. Bundled only — ten summers that already happened
    /// don't move over a weekend the way this one's set times do.
    let pastLineups: PastLineupData
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?
    private(set) var refreshError: String?

    init() {
        // Pre-widget builds cached outside the app group, where the extension can't see it.
        ScheduleFile.migrateLegacyCacheIfNeeded()

        let bundled = Self.loadBundled(FestivalData.self, named: "schedule")
        // A cached refresh is only preferred when it is actually newer than the bundle,
        // so shipping a corrected build always wins over a stale download.
        if let cached = ScheduleFile.cached(), cached.generatedAt > bundled.generatedAt {
            data = cached
            lastRefreshed = cached.generatedAt
        } else {
            data = bundled
        }
        guide = Self.loadBundled(GuideData.self, named: "info")
        map = Self.loadBundled(MapData.self, named: "map")
        vendors = Self.loadBundled(VendorData.self, named: "vendors")
        pastLineups = Self.loadBundled(PastLineupData.self, named: "past-lineups")
    }

    // MARK: - Refresh

    @MainActor
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }

        do {
            var request = URLRequest(url: Self.remoteURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 12

            let (payload, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw RefreshError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            guard let fresh = ScheduleFile.decode(payload) else {
                throw RefreshError.malformed
            }

            // Ignore a remote copy that is older than what we already show.
            if fresh.generatedAt > data.generatedAt {
                data = fresh
                try? payload.write(to: ScheduleFile.cacheURL, options: .atomic)
                // New set times are exactly the case where a stale widget misleads.
                WidgetCenter.shared.reloadAllTimelines()
            }
            lastRefreshed = Date()
        } catch {
            refreshError = (error as? RefreshError)?.description ?? error.localizedDescription
        }
    }

    enum RefreshError: Error, CustomStringConvertible {
        case badStatus(Int)
        case malformed

        var description: String {
            switch self {
            case .badStatus(let code): return "Server returned \(code)."
            case .malformed: return "That schedule file couldn't be read."
            }
        }
    }

    // MARK: - Loading

    /// The bundled files are build inputs we control, so failure here is a packaging
    /// bug worth surfacing loudly rather than limping along with empty state.
    private static func loadBundled<T: Decodable>(_ type: T.Type, named name: String) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Missing bundled \(name).json — check the Resources build phase.")
        }
        do {
            return try ScheduleFile.decoder().decode(type, from: data)
        } catch {
            fatalError("Bundled \(name).json failed to decode: \(error)")
        }
    }
}

// MARK: - Derived schedule queries

extension ScheduleStore {
    var days: [FestivalDay] { data.days }

    /// The day to open on: whatever is running right now, else today's date if the
    /// festival is on today, else the first day.
    ///
    /// The running day is checked first so that a 1am walk back to the car still opens
    /// on the night you're leaving rather than the one starting in a few hours.
    func defaultDay(now: Date = Date()) -> FestivalDay? {
        currentDay(now: now) ?? day(on: now) ?? data.days.first
    }

    /// The day whose programming is running right now, late-night sets included.
    func currentDay(now: Date = Date()) -> FestivalDay? {
        data.days.first { day in
            guard let first = day.sets.map(\.start).min(),
                  let last = day.sets.map(\.end).max() else { return false }
            return now >= first && now <= last
        }
    }

    /// The festival day falling on the same calendar date as `date`, judged in the
    /// festival's own time zone so a phone still set to Pacific opens on the right day.
    func day(on date: Date) -> FestivalDay? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = data.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: date)
        return data.days.first { $0.date == today }
    }

    func performances(on day: FestivalDay, stage: String? = nil) -> [Performance] {
        day.sets
            .filter { stage == nil || $0.stage == stage }
            .sorted { $0.start == $1.start ? $0.stage < $1.stage : $0.start < $1.start }
    }

    func liveNow(at date: Date = Date()) -> [Performance] {
        data.allPerformances.filter { $0.isLive(at: date) }.sorted { $0.start < $1.start }
    }

    func upNext(after date: Date = Date(), limit: Int = 3) -> [Performance] {
        data.allPerformances
            .filter { $0.start > date }
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map { $0 }
    }
}
