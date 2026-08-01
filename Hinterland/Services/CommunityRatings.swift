import CloudKit
import Foundation
import Observation

/// What everyone else made of one set: the stars added up, and how many people gave them.
struct CrowdRating: Codable, Equatable {
    let total: Int
    let count: Int

    var average: Double { count == 0 ? 0 : Double(total) / Double(count) }
}

/// The whole crowd table as it was at `fetchedAt`, which is what gets cached to disk so
/// the averages are still on screen in a field with no signal.
struct CrowdRatings: Codable, Equatable {
    var fetchedAt: Date
    var byPerformanceID: [String: CrowdRating]
    /// True when the sweep stopped at the record cap rather than at the end of the
    /// records, so the UI can decline to call a partial count the whole crowd.
    var isPartial: Bool
}

/// Everyone's ratings, pooled through the CloudKit public database.
///
/// The bargain the rest of the app makes applies here too, and harder: `Ratings` on the
/// phone is the source of truth for what *you* thought, it is written and read with no
/// network at all, and this class is strictly an upgrade path on top of it. A rating made
/// in the valley goes into an outbox that survives relaunches and drains whenever signal
/// comes back — most likely in the car on the way home.
///
/// CloudKit rather than a server of our own: no hosting, no keys in the binary, no
/// accounts to build, and the public database's default role already enforces the rule
/// that matters — anyone may read, but you may only write records you created. One record
/// per person per set, named for both, so re-rating a set overwrites your own row instead
/// of stuffing the ballot.
///
/// Only the score is shared. Notes never leave the phone.
@Observable
final class CommunityRatings {
    static let recordType = "SetRating"
    private static let performanceKey = "performanceID"
    private static let starsKey = "stars"
    private static let yearKey = "festivalYear"

    /// Sentinel in the outbox for "take my rating back down", which is a delete rather
    /// than a score. Stars are 1–5, so zero can't collide with one.
    private static let withdrawn = 0

    private static let sharingKey = "sharesRatings"
    private static let outboxKey = "pendingSharedRatings"

    /// Same floor as the forecast: coming back to the app repeatedly shouldn't turn into
    /// repeated sweeps of the database, and an average over hundreds of people doesn't
    /// move inside a quarter of an hour.
    private static let minimumInterval: TimeInterval = 15 * 60

    /// The public database has no server-side aggregation, so the averages are counted
    /// here from the raw rows. That is fine at this festival's scale and cheap per row
    /// (two small fields), but it is the part that doesn't grow forever: past this cap
    /// the sweep stops and says it's partial, and the fix at that point is to aggregate
    /// somewhere else and publish the totals the way `schedule.json` is published.
    private static let pageSize = 400
    private static let recordCap = 20_000

    /// Off means: stop uploading, and take back what's already up there. Reading the
    /// crowd average carries on either way — it costs nothing and gives nothing away.
    var isSharing: Bool {
        didSet {
            guard isSharing != oldValue else { return }
            UserDefaults.standard.set(isSharing, forKey: Self.sharingKey)
        }
    }

    private(set) var crowd: CrowdRatings?
    private(set) var isRefreshing = false
    private(set) var isPushing = false
    /// Nil once something succeeds. Never blocks the cached averages from rendering.
    private(set) var lastError: String?
    /// Whether this phone can write at all. Reads don't need an account; writes do.
    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine

    /// Ratings made locally that CloudKit hasn't taken yet, keyed by performance —
    /// persisted, because the whole point is surviving a weekend with no signal.
    private(set) var outbox: [String: Int]

    private let festivalYear: Int
    private let container: CKContainer
    private var lastAttempt: Date?

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("crowd-ratings.json")
    }

    init(festivalYear: Int, container: CKContainer = .default()) {
        self.festivalYear = festivalYear
        self.container = container
        let defaults = UserDefaults.standard
        // Default on: the feature is the crowd average, and an app that quietly opts you
        // out of the thing it's for is just broken. The toggle is one tap away and the
        // screen it's on says what's shared.
        isSharing = defaults.object(forKey: Self.sharingKey) as? Bool ?? true
        outbox = defaults.dictionary(forKey: Self.outboxKey) as? [String: Int] ?? [:]
        crowd = Self.loadCache()
    }

    // MARK: - Reading

    func rating(for performance: Performance) -> CrowdRating? {
        guard let entry = crowd?.byPerformanceID[performance.id], entry.count > 0 else { return nil }
        return entry
    }

    var fetchedAt: Date? { crowd?.fetchedAt }
    var hasPendingUploads: Bool { !outbox.isEmpty }

    /// The one thing worth saying out loud: writes need an iCloud account and this phone
    /// doesn't have one, so these ratings are staying put.
    var needsAccount: Bool {
        isSharing && !outbox.isEmpty && accountStatus == .noAccount
    }

    // MARK: - Refresh

    /// Best effort, always — a failed sweep leaves the cached averages on screen.
    @MainActor
    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < Self.minimumInterval {
            return
        }

        isRefreshing = true
        lastAttempt = Date()
        defer { isRefreshing = false }

        let query = CKQuery(recordType: Self.recordType,
                            predicate: NSPredicate(format: "%K == %@", Self.yearKey,
                                                   NSNumber(value: festivalYear)))
        let keys = [Self.performanceKey, Self.starsKey]
        var totals: [String: (total: Int, count: Int)] = [:]
        var cursor: CKQueryOperation.Cursor?
        var seen = 0

        do {
            repeat {
                let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
                           queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    page = try await container.publicCloudDatabase.records(
                        continuingMatchFrom: cursor, desiredKeys: keys,
                        resultsLimit: Self.pageSize)
                } else {
                    page = try await container.publicCloudDatabase.records(
                        matching: query, desiredKeys: keys, resultsLimit: Self.pageSize)
                }

                for (_, result) in page.matchResults {
                    guard let record = try? result.get(),
                          let performanceID = record[Self.performanceKey] as? String,
                          let stars = (record[Self.starsKey] as? NSNumber)?.intValue
                    else { continue }
                    var entry = totals[performanceID] ?? (total: 0, count: 0)
                    // Clamped rather than trusted: these rows come from other people's
                    // copies of the app, and one bad row shouldn't skew a set's average.
                    entry.total += min(max(stars, SetRating.scale.lowerBound),
                                       SetRating.scale.upperBound)
                    entry.count += 1
                    totals[performanceID] = entry
                }

                seen += page.matchResults.count
                cursor = page.queryCursor
            } while cursor != nil && seen < Self.recordCap

            crowd = CrowdRatings(
                fetchedAt: Date(),
                byPerformanceID: totals.mapValues { CrowdRating(total: $0.total, count: $0.count) },
                isPartial: cursor != nil)
            lastError = nil
            persistCache()
        } catch {
            lastError = Self.message(for: error)
        }
    }

    // MARK: - Writing

    /// Turns a change in the local ratings into work for the outbox.
    ///
    /// Driven from the change in `Ratings` rather than called at each tap site, so there
    /// is one place that decides what goes up and it can't be forgotten at a fourth
    /// button somewhere.
    func noteLocalChange(from old: [String: SetRating], to new: [String: SetRating]) {
        guard isSharing else { return }
        var changes: [String: Int] = [:]
        for (id, rating) in new where old[id]?.stars != rating.stars {
            changes[id] = rating.stars
        }
        for id in old.keys where new[id] == nil {
            changes[id] = Self.withdrawn
        }
        guard !changes.isEmpty else { return }
        outbox.merge(changes) { _, latest in latest }
        persistOutbox()
    }

    /// Turning sharing on offers up everything you've already rated; turning it off takes
    /// all of it back down rather than merely stopping, which is the only reading of that
    /// switch that isn't a lie.
    func applySharingChange(localRatings: [String: SetRating]) {
        for (id, rating) in localRatings {
            outbox[id] = isSharing ? rating.stars : Self.withdrawn
        }
        persistOutbox()
    }

    /// Drains the outbox. Runs on launch, on foreground and after any rating changes;
    /// does nothing at all when there's nothing waiting.
    @MainActor
    func push() async {
        guard !outbox.isEmpty, !isPushing else { return }
        isPushing = true
        defer { isPushing = false }

        accountStatus = (try? await container.accountStatus()) ?? .couldNotDetermine
        guard accountStatus == .available else {
            // Not an error worth showing: without an account there is nothing to do but
            // hold on to the ratings, which is exactly what the outbox is for.
            return
        }

        guard let userID = try? await container.userRecordID() else {
            lastError = "Couldn't reach iCloud — your ratings are saved and will upload later."
            return
        }

        // One record per person per set, so a re-rating overwrites your row rather than
        // adding a second one. Kept alongside the batch because the record name is the
        // only thing the results come back keyed by.
        var performanceIDsByRecordName: [String: String] = [:]
        var saves: [CKRecord] = []
        var deletes: [CKRecord.ID] = []

        for (performanceID, stars) in outbox {
            let recordID = CKRecord.ID(recordName: "\(performanceID)_\(userID.recordName)")
            performanceIDsByRecordName[recordID.recordName] = performanceID
            if stars == Self.withdrawn {
                deletes.append(recordID)
            } else {
                let record = CKRecord(recordType: Self.recordType, recordID: recordID)
                record[Self.performanceKey] = performanceID as NSString
                record[Self.starsKey] = stars as NSNumber
                record[Self.yearKey] = festivalYear as NSNumber
                saves.append(record)
            }
        }

        do {
            // `.allKeys` because the record is rebuilt from local state every time and is
            // meant to win — there is no merge to do with a row only you can write.
            // Not atomic: the public database's default zone doesn't do atomic batches,
            // and one rejected row shouldn't strand the rest.
            let results = try await container.publicCloudDatabase.modifyRecords(
                saving: saves, deleting: deletes, savePolicy: .allKeys, atomically: false)

            for (recordID, result) in results.saveResults {
                guard case .success = result,
                      let performanceID = performanceIDsByRecordName[recordID.recordName]
                else { continue }
                outbox.removeValue(forKey: performanceID)
            }

            for (recordID, result) in results.deleteResults {
                guard let performanceID = performanceIDsByRecordName[recordID.recordName] else {
                    continue
                }
                switch result {
                case .success:
                    outbox.removeValue(forKey: performanceID)
                case .failure(let error):
                    // Already gone is the outcome we wanted, not a failure to retry.
                    if (error as? CKError)?.code == .unknownItem {
                        outbox.removeValue(forKey: performanceID)
                    }
                }
            }

            persistOutbox()
            lastError = outbox.isEmpty ? nil : Self.holdingMessage(count: outbox.count)
        } catch {
            lastError = Self.message(for: error)
        }
    }

    @MainActor
    func refreshAccountStatus() async {
        accountStatus = (try? await container.accountStatus()) ?? .couldNotDetermine
    }

    // MARK: - Messages

    private static func holdingMessage(count: Int) -> String {
        "\(count) \(count == 1 ? "rating is" : "ratings are") waiting to upload."
    }

    /// CloudKit's errors mostly mean one of three things down here: no signal, no iCloud
    /// account, or a build whose container isn't set up. None of them is worth more than
    /// a line, and none of them costs you the rating — it's already on the phone.
    private static func message(for error: Error) -> String {
        guard let ckError = error as? CKError else { return error.localizedDescription }
        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            return "No signal — showing the last crowd ratings that came through."
        case .notAuthenticated:
            return "Sign in to iCloud to add your ratings to the average."
        case .quotaExceeded:
            return "iCloud is out of space for this, so ratings aren't uploading."
        case .badContainer, .missingEntitlement:
            return "This build isn't set up for shared ratings, so only yours are shown."
        default:
            return ckError.localizedDescription
        }
    }

    // MARK: - Persistence

    private func persistOutbox() {
        UserDefaults.standard.set(outbox, forKey: Self.outboxKey)
    }

    private func persistCache() {
        guard let crowd, let payload = try? Self.coder().0.encode(crowd) else { return }
        try? payload.write(to: Self.cacheURL, options: .atomic)
    }

    /// A cache we can't read is a cache we don't have — the app starts with no averages
    /// and fetches some.
    private static func loadCache() -> CrowdRatings? {
        guard let payload = try? Data(contentsOf: cacheURL) else { return nil }
        return try? coder().1.decode(CrowdRatings.self, from: payload)
    }

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }
}
