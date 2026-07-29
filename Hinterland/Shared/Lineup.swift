import Foundation

/// What the widget and the Live Activity should be showing at a given moment.
///
/// Both answer the same question — "what am I watching, and what's after it?" — so the
/// rule for picking those two sets lives here rather than twice.
struct LineupFocus: Equatable {
    /// Playing right now.
    var current: Performance?
    /// The next one to start, whether or not anything is playing.
    var next: Performance?
    /// True when these came from starred sets. False means nothing is starred (or the
    /// weekend has moved past everything that was) and this is the festival at large,
    /// which is worth labelling differently — "On now" rather than "Your next set".
    var isPersonal: Bool

    var isEmpty: Bool { current == nil && next == nil }

    /// The set to lead with.
    var headline: Performance? { current ?? next }
}

enum Lineup {
    /// Starred sets if there are any still to come, the whole schedule otherwise.
    static func focus(in data: FestivalData,
                      starred: Set<String>,
                      at now: Date = Date()) -> LineupFocus {
        let remaining = data.allPerformances.filter { $0.end > now }
        let personal = remaining.filter { starred.contains($0.id) }
        let pool = personal.isEmpty ? remaining : personal

        // Earliest start among whatever is live, matching the Now card on the schedule —
        // with two starred sets overlapping, the one that began first is the one you're
        // standing at.
        let current = pool.filter { $0.isLive(at: now) }.min { $0.start < $1.start }
        let next = pool.filter { $0.start > now }.min { $0.start < $1.start }

        return LineupFocus(current: current, next: next, isPersonal: !personal.isEmpty)
    }

    /// Instants where the focus changes — every remaining start and end. A widget
    /// timeline built on these redraws exactly when a set begins or finishes and not
    /// once in between, which is what keeps it correct through a night with no signal.
    static func transitions(in data: FestivalData,
                            starred: Set<String>,
                            after now: Date = Date(),
                            limit: Int = 24) -> [Date] {
        let remaining = data.allPerformances.filter { $0.end > now }
        let personal = remaining.filter { starred.contains($0.id) }
        let pool = personal.isEmpty ? remaining : personal

        let boundaries = pool.flatMap { [$0.start, $0.end] }.filter { $0 > now }
        return Array(Set(boundaries).sorted().prefix(limit))
    }
}
