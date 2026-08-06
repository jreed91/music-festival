import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Whether the festival is still to come, on, or over.
///
/// Read off the schedule rather than written down anywhere: the last set's end is already
/// in `schedule.json`, and a flag someone has to remember to flip is a flag that is wrong
/// on the Monday morning when it matters. It also means next year's schedule turns the
/// app back over on its own, with no build.
enum FestivalPhase {
    case upcoming
    case running
    case over
}

extension FestivalData {
    /// The moment the last band stops playing. Nil only for a schedule with no sets in it.
    ///
    /// The end of the *last set*, not the end of the last date: Hinterland's closing
    /// Campfire set starts at half past midnight, and a festival that declared itself over
    /// while a band was still on stage would be wrong for the best hour of the weekend.
    var lastSetEnd: Date? { allPerformances.map(\.end).max() }

    var firstSetStart: Date? { allPerformances.map(\.start).min() }

    func phase(at now: Date = Date()) -> FestivalPhase {
        guard let first = firstSetStart, let last = lastSetEnd else { return .upcoming }
        if now >= last { return .over }
        return now >= first ? .running : .upcoming
    }

    func isOver(at now: Date = Date()) -> Bool { phase(at: now) == .over }
}

// MARK: - The weekend you had

/// Everything the post-festival home screen counts, worked out once from the schedule, the
/// stars and the ratings.
///
/// A struct rather than a pile of computed properties on the view: the counting rules are
/// the interesting part — what "a set you saw" means, which day was busiest — and they
/// belong somewhere they can be reasoned about without a `View` around them.
struct Recap {
    /// A set you rated, with what you gave it.
    struct RatedSet: Identifiable {
        let performance: Performance
        let rating: SetRating

        var id: String { performance.id }
    }

    /// How many of your sets a stage got.
    struct StageTally: Identifiable {
        let stage: Stage
        let name: String
        let count: Int

        var id: String { name }
    }

    let festival: Festival
    /// Rated first, best first — the order the recap and the share card read in.
    let rated: [RatedSet]
    /// Your average across everything you rated, or nil if you rated nothing.
    let average: Double?
    /// Sets you were at: everything you rated, plus everything you starred that has since
    /// finished. Stars are a plan and plans get abandoned, so this is the generous count —
    /// which is the right one for a souvenir and the wrong one for anything else.
    let attended: [Performance]
    /// Starred, over, and never rated. The one number on this screen that is a to-do.
    let unrated: [Performance]
    /// Time on your feet in front of a stage, from the set lengths of everything attended.
    /// Overlapping sets are counted once each, because you were at both, briefly.
    let watched: TimeInterval
    /// The day you saw the most, and how many. Nil when nothing was attended.
    let busiestDay: (day: FestivalDay, count: Int)?
    /// Stages you were at, most-seen first.
    let stages: [StageTally]

    var attendedCount: Int { attended.count }
    var ratedCount: Int { rated.count }
    /// Rounded to the nearest half hour: a souvenir number, and "18.25 hours" is not one.
    var watchedHours: Double { (watched / 3600 * 2).rounded() / 2 }
    /// Nothing rated and nothing starred — the screen leads with the festival instead.
    var isEmpty: Bool { attended.isEmpty }

    /// Your best sets, longest-standing tie broken by who played first.
    func best(limit: Int) -> [RatedSet] { Array(rated.prefix(limit)) }

    init(data: FestivalData,
         ratings: Ratings,
         favorites: Favorites,
         now: Date = Date()) {
        // Everything is worked out into locals first and assigned at the end. Half of this
        // reads the results of the other half, and a stored property can't be read back
        // out of a closure until the whole value is initialised.
        let ranked = ratings.ranked(in: data).map { RatedSet(performance: $0.performance,
                                                             rating: $0.rating) }
        let starred = favorites.performances(in: data)

        // A set counts once however it got here, so this is a union and not a sum: the
        // sets you starred *and* rated are most of them, and counting those twice would
        // put the hours out by roughly the whole weekend.
        let ratedIDs = Set(ranked.map(\.performance.id))
        let finishedStars = starred.filter { $0.end <= now && !ratedIDs.contains($0.id) }
        let seen = (ranked.map(\.performance) + finishedStars).sorted { $0.start < $1.start }

        let byDay = data.days
            .map { day in (day: day, count: seen.filter { day.sets.contains($0) }.count) }
            .filter { $0.count > 0 }

        var counts: [String: Int] = [:]
        for performance in seen { counts[performance.stage, default: 0] += 1 }

        festival = data.festival
        rated = ranked
        average = ratings.average(in: data)
        unrated = ratings.unrated(among: starred, at: now)
        attended = seen
        watched = seen.reduce(0) { $0 + $1.duration }
        // `max(by:)` keeps the first of equal elements and the days are in order, so a tie
        // goes to the earlier day — the one that started the weekend.
        busiestDay = byDay.max { $0.count < $1.count }
        stages = counts
            .map { StageTally(stage: Stage(name: $0.key), name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}

// MARK: - Sharing

/// What the share sheet hands off: a rendered card for anywhere that takes a picture, and
/// the plain-text recap for anywhere that doesn't.
///
/// Both representations, rather than a choice made up front — Messages takes the image,
/// a notes app takes the text, and neither should get the wrong one. The PNG is rendered
/// before the sheet opens; if that somehow failed, the text representation is still there
/// and the share still works.
struct RecapShare: Transferable {
    let text: String
    let image: Data?

    struct ImageUnavailable: Error {}

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { share in
            guard let image = share.image else { throw ImageUnavailable() }
            return image
        }
        .suggestedFileName("hinterland-recap.png")

        ProxyRepresentation(exporting: \.text)
    }
}

extension Recap {
    /// The text half of the share. Ratings only — the notes are yours, and a share sheet
    /// is the last place they should turn up by default.
    var shareText: String {
        var lines = ["My \(festival.name) \(String(festival.year))"]
        if let average {
            lines.append("\(ratedCount) \(ratedCount == 1 ? "set" : "sets") rated · "
                       + "\(Format.rating(average)) average")
        }
        lines += rated.map { entry in
            let stars = String(repeating: "★", count: entry.rating.stars)
                + String(repeating: "☆", count: SetRating.scale.upperBound - entry.rating.stars)
            return "\(stars)  \(entry.performance.artist)"
        }
        return lines.joined(separator: "\n")
    }
}
