import Foundation
import Observation

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
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?
    private(set) var refreshError: String?

    /// Static so `init` can read it before the observed stored properties are set.
    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("schedule.json")
    }

    init() {
        let bundled = Self.loadBundled(FestivalData.self, named: "schedule")
        // A cached refresh is only preferred when it is actually newer than the bundle,
        // so shipping a corrected build always wins over a stale download.
        if let cached = Self.decode(FestivalData.self, from: try? Data(contentsOf: Self.cacheURL)),
           cached.generatedAt > bundled.generatedAt {
            data = cached
            lastRefreshed = cached.generatedAt
        } else {
            data = bundled
        }
        guide = Self.loadBundled(GuideData.self, named: "info")
        map = Self.loadBundled(MapData.self, named: "map")
        vendors = Self.loadBundled(VendorData.self, named: "vendors")
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
            guard let fresh = Self.decode(FestivalData.self, from: payload) else {
                throw RefreshError.malformed
            }

            // Ignore a remote copy that is older than what we already show.
            if fresh.generatedAt > data.generatedAt {
                data = fresh
                try? payload.write(to: Self.cacheURL, options: .atomic)
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

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? decoder().decode(type, from: data)
    }

    /// The bundled files are build inputs we control, so failure here is a packaging
    /// bug worth surfacing loudly rather than limping along with empty state.
    private static func loadBundled<T: Decodable>(_ type: T.Type, named name: String) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Missing bundled \(name).json — check the Resources build phase.")
        }
        do {
            return try decoder().decode(type, from: data)
        } catch {
            fatalError("Bundled \(name).json failed to decode: \(error)")
        }
    }
}

// MARK: - Derived schedule queries

extension ScheduleStore {
    var days: [FestivalDay] { data.days }

    /// The day to open on: today if the festival is running, otherwise the first day.
    func defaultDay(now: Date = Date()) -> FestivalDay? {
        currentDay(now: now) ?? data.days.first
    }

    /// The day whose programming is running right now, late-night sets included.
    func currentDay(now: Date = Date()) -> FestivalDay? {
        data.days.first { day in
            guard let first = day.sets.map(\.start).min(),
                  let last = day.sets.map(\.end).max() else { return false }
            return now >= first && now <= last
        }
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
