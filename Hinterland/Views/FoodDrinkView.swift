import SwiftUI

enum VendorRoute: Hashable {
    /// The full food & drink directory.
    case directory
}

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
        List {
            filters

            if areas.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "fork.knife",
                        title: "No stands match",
                        message: "Try fewer dietary filters, or a different search.")
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            }

            ForEach(areas) { area in
                Section {
                    ForEach(area.vendors) { vendor in
                        VendorCard(vendor: vendor,
                                   alsoIn: store.vendors.locations(of: vendor.id)
                                       .filter { $0.id != area.id })
                    }
                } header: {
                    HStack {
                        Label(area.name, systemImage: area.symbol)
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        Text("\(area.vendors.count)")
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
                .listRowBackground(Theme.surface)
            }

            legend
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Food & Drink")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search stands, dishes or towns")
    }

    /// Dietary filters combine: picking Vegan and Gluten-free leaves the stands that serve
    /// both, which is the question someone with two restrictions is actually asking.
    private var filters: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.vendors.presentTags) { tag in
                        let isOn = tags.contains(tag)
                        Button {
                            if isOn { tags.remove(tag) } else { tags.insert(tag) }
                        } label: {
                            Text(tag.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isOn ? Theme.background : Theme.dietary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isOn ? Theme.dietary : Theme.dietary.opacity(0.16),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if !tags.isEmpty {
                        Button("Clear") { tags.removeAll() }
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } footer: {
            Text("\(matchCount) stand\(matchCount == 1 ? "" : "s") shown"
               + (tags.isEmpty ? "" : " serving \(tags.map(\.label).sorted().joined(separator: " + "))")
               + ".")
                .font(.system(size: 11))
        }
        .listRowBackground(Theme.surface)
    }

    private var legend: some View {
        Section {
            Text("Dietary offerings are as the festival lists them. A faded tag means the "
               + "stand has an option that fits, not a whole menu — ask when you order. "
               + "Special dietary accommodation can be arranged in advance through "
               + "access@hinterlandiowa.com.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            if let source = store.vendors.source, let url = URL(string: source) {
                Link(destination: url) {
                    Label("Vendor list on hinterlandiowa.com", systemImage: "arrow.up.right")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                }
            }
        } header: {
            Text("About this list").foregroundStyle(Theme.tertiaryText)
        }
        .listRowBackground(Theme.surface)
    }
}

/// One stand: what they sell, where they're from, and what they can feed you.
struct VendorCard: View {
    let vendor: Vendor
    /// Other areas the same stand appears in, so a second location isn't a surprise.
    var alsoIn: [VendorArea] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(vendor.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if let hometown = vendor.hometown {
                    Text(hometown)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                        .multilineTextAlignment(.trailing)
                }
            }

            if !vendor.offerings.isEmpty {
                Text(vendor.offerings)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !vendor.tags.isEmpty || !vendor.optionTags.isEmpty {
                TagFlow(spacing: 6) {
                    ForEach(vendor.tags) { DietaryBadge(tag: $0) }
                    ForEach(vendor.optionTags) { DietaryBadge(tag: $0, isOption: true) }
                }
            } else if let note = vendor.dietaryNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }

            if !alsoIn.isEmpty {
                Label("Also in \(alsoIn.map(\.name).joined(separator: ", "))",
                      systemImage: "mappin.and.ellipse")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }

            if let link = vendor.url, let url = URL(string: link) {
                Link(destination: url) {
                    Text(url.host()?.replacingOccurrences(of: "www.", with: "") ?? link)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DietaryBadge: View {
    let tag: DietaryTag
    var isOption = false

    var body: some View {
        Text(isOption ? "\(tag.label) option" : tag.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dietary.opacity(isOption ? 0.62 : 1))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.dietary.opacity(isOption ? 0.08 : 0.16), in: Capsule())
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
