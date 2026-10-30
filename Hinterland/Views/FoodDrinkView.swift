import SwiftUI

/// Every food and drink stand on site, grouped by where it's parked and filterable by
/// what you can eat. Bundled like the rest of the guide, so it answers "who has something
/// gluten-free" from a spot in the field with no signal.
struct FoodDrinkView: View {
    @Environment(ScheduleStore.self) private var store
    @State private var query = ""
    @State private var tags: Set<DietaryTag> = []

    private var areas: [VendorArea] { store.vendors.matchingAreas(query: query, tags: tags) }
    private var matchCount: Int { areas.reduce(0) { $0 + $1.vendors.count } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.vendors.vendorCount) stands · \(store.vendors.areas.count) areas".uppercased())
                        .appFont(12, weight: .bold)
                        .tracking(2.4)
                        .foregroundStyle(Theme.inkFaint)
                    Text("FOOD & DRINK")
                        .marqueeFont(80)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                SearchField(prompt: "Search stands, dishes or towns", text: $query)
                    .padding(.top, 16)

                filters
                    .padding(.top, 12)

                if areas.isEmpty {
                    EmptyStateView(
                        title: "No stands match",
                        message: "Try fewer dietary filters, or a different search.")
                        .frame(maxWidth: .infinity)
                }

                ForEach(areas) { area in
                    areaHeader(area)
                    ForEach(area.vendors) { vendor in
                        VendorCard(vendor: vendor,
                                   alsoIn: store.vendors.locations(of: vendor.id)
                                       .filter { $0.id != area.id })
                    }
                }

                legend
                    .padding(.top, 32)

                Horizon()
                    .padding(.top, 48)
                    .padding(.horizontal, -22)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
        .background(Theme.night)
        .navigationTitle("Food & Drink")
        .navigationBarTitleDisplayMode(.inline)
        // The field is in the page, so dragging the list is the natural way to put the
        // keyboard away.
        .scrollDismissesKeyboard(.immediately)
    }

    /// True while a search or a dietary filter is narrowing the list.
    private var isFiltering: Bool {
        !tags.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The area in Six Caps over a 2pt cream rule, with how many of its stands show:
    /// "9 STANDS", or "3 OF 9 STANDS" while something is filtering them.
    private func areaHeader(_ area: VendorArea) -> some View {
        let shown = area.vendors.count
        let total = store.vendors.areas.first { $0.id == area.id }?.vendors.count ?? shown
        let count = isFiltering && shown != total
            ? "\(shown) of \(total) \(total == 1 ? "stand" : "stands")"
            : "\(shown) \(shown == 1 ? "stand" : "stands")"
        return HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(area.name.uppercased())
                .marqueeFont(56)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(count.uppercased())
                .appFont(12, weight: .bold)
                .tracking(1.6)
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 32)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.ink).frame(height: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(area.name), \(count)")
        .accessibilityAddTraits(.isHeader)
    }

    /// Dietary filters combine: picking Vegan and Gluten-free leaves the stands that serve
    /// both, which is the question someone with two restrictions is actually asking.
    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Wrapped rather than scrolled sideways: every restriction has to be visible
            // to be pickable, and someone avoiding nuts shouldn't have to discover the
            // filter by dragging a row that looks like it ends.
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(store.vendors.presentTags) { tag in
                    let isOn = tags.contains(tag)
                    FilterChip(title: tag.label, isOn: isOn, onColor: Theme.firefly) {
                        if isOn { tags.remove(tag) } else { tags.insert(tag) }
                    }
                    .accessibilityLabel(tag.label)
                }
                if !tags.isEmpty {
                    FilterChip(title: "Clear", isOn: false) { tags.removeAll() }
                        .accessibilityLabel("Clear dietary filters")
                }
            }
            Text("\(matchCount) stand\(matchCount == 1 ? "" : "s") shown"
               + (tags.isEmpty ? "" : " serving \(tags.map(\.label).sorted().joined(separator: " + "))")
               + ".")
                .appFont(13)
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ABOUT THIS LIST")
                .appFont(12, weight: .bold)
                .tracking(2.4)
                .foregroundStyle(Theme.inkFaint)
                .accessibilityAddTraits(.isHeader)
            Text("Dietary offerings are as the festival lists them. A dashed tag means the "
               + "stand has an option that fits, not a whole menu — ask when you order. "
               + "Special dietary accommodation can be arranged in advance through "
               + "access@hinterlandiowa.com.")
                .readingFont(14)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let source = store.vendors.source, let url = URL(string: source) {
                Link(destination: url) {
                    Label("Vendor list on hinterlandiowa.com", systemImage: "arrow.up.right")
                }
                .buttonStyle(GlowButtonStyle(.quiet))
                .padding(.top, 4)
            }
        }
    }
}

/// One stand: what they sell, where they're from, and what they can feed you. The
/// VendorRow of the design system: when the stand has a website, the whole row opens it
/// rather than a separate link inside it, with the address in a caption so it's clear
/// where a tap goes.
struct VendorCard: View {
    let vendor: Vendor
    /// Other areas the same stand appears in, so a second location isn't a surprise.
    var alsoIn: [VendorArea] = []

    private var website: URL? { vendor.url.flatMap { URL(string: $0) } }

    var body: some View {
        if let website {
            Link(destination: website) {
                row(host: website.host()?.replacingOccurrences(of: "www.", with: ""))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens their website")
        } else {
            row(host: nil)
        }
    }

    /// A stand's name, town, menu and tags as one stop for VoiceOver: they were five or
    /// more swipes each, which across a food court is a long way to scroll by ear.
    private func row(host: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(vendor.name.uppercased())
                    .listNameFont()
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let hometown = vendor.hometown {
                    Text(hometown.uppercased())
                        .appFont(12, weight: .bold)
                        .tracking(1.4)
                        .foregroundStyle(Theme.inkFaint)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !vendor.offerings.isEmpty {
                Text(vendor.offerings)
                    .readingFont(15)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !vendor.tags.isEmpty || !vendor.optionTags.isEmpty {
                TagFlow(spacing: 6) {
                    ForEach(vendor.tags) { DietaryBadge(tag: $0) }
                    ForEach(vendor.optionTags) { DietaryBadge(tag: $0, isOption: true) }
                }
            } else if let note = vendor.dietaryNote {
                Text(note)
                    .appFont(13)
                    .foregroundStyle(Theme.inkFaint)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !alsoIn.isEmpty {
                Text("Also at \(alsoIn.map(\.name).joined(separator: ", "))")
                    .appFont(13)
                    .foregroundStyle(Theme.inkFaint)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let host {
                Label(host, systemImage: "arrow.up.right")
                    .appFont(13, weight: .semibold)
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A dietary code as a `firefly` outline; an "option" one dashed and quieter, the way
/// the festival qualifies it.
struct DietaryBadge: View {
    let tag: DietaryTag
    var isOption = false

    var body: some View {
        Text((isOption ? "\(tag.label) option" : tag.label).uppercased())
            .appFont(12, weight: .bold)
            .tracking(1.2)
            .foregroundStyle(isOption ? Theme.inkMuted : Theme.firefly)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .overlay(
                Rectangle()
                    .strokeBorder(isOption ? Theme.inkMuted : Theme.firefly,
                                  style: StrokeStyle(lineWidth: 1, dash: isOption ? [3, 2] : []))
            )
            .fixedSize()
    }
}

/// Wraps badges onto as many lines as they need. A stand can carry five of them, which
/// never fits one line on a phone.
struct TagFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(in: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].width
                + (rows[rows.count - 1].indices.isEmpty ? 0 : spacing) + size.width
            if needed > width && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let last = rows.count - 1
            rows[last].width += (rows[last].indices.isEmpty ? 0 : spacing) + size.width
            rows[last].height = max(rows[last].height, size.height)
            rows[last].indices.append(index)
        }
        return rows
    }
}
