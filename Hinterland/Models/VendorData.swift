import Foundation

/// Contents of `vendors.json` — the food & drink directory, grouped the way the festival
/// groups it: by the part of the site a stand is parked in.
struct VendorData: Codable, Equatable {
    let version: Int
    /// The page this was scraped from, linked at the bottom of the directory.
    var source: String?
    let areas: [VendorArea]
}

struct VendorArea: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let vendors: [Vendor]

    var symbol: String {
        if id.contains("concourse") { return "fork.knife" }
        if id.hasPrefix("vip") { return "star" }
        if id.hasPrefix("ga") { return "sparkles" }
        if id.contains("campground") || id.contains("basecamp") { return "tent" }
        if id.contains("mobile") || id.contains("cart") { return "cart" }
        return "fork.knife"
    }
}

struct Vendor: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    /// What they're selling, in the festival's own words.
    let offerings: String
    var city: String?
    var state: String?
    /// Dietary shorthand as the site prints it — see `DietaryTag`. Unknown codes are
    /// ignored at read time rather than failing the whole decode.
    var dietary: [String]?
    /// Codes the site qualifies with "option": something on the menu is gluten-free, not
    /// the whole menu.
    var dietaryOptions: [String]?
    /// Free text for the stands that answer "Various offerings" instead of listing codes.
    var dietaryNote: String?
    var url: String?

    var hometown: String? {
        guard let city, let state else { return city ?? state }
        return "\(city), \(state)"
    }

    var tags: [DietaryTag] { (dietary ?? []).compactMap(DietaryTag.init(code:)) }
    var optionTags: [DietaryTag] { (dietaryOptions ?? []).compactMap(DietaryTag.init(code:)) }

    /// True when the stand serves this diet at all, whether the whole menu or one item —
    /// standing in a field, "they have something for you" is the useful answer.
    func serves(_ tag: DietaryTag) -> Bool {
        tags.contains(tag) || optionTags.contains(tag)
    }

    func matches(_ needle: String) -> Bool {
        [name, offerings, hometown ?? ""].contains { $0.lowercased().contains(needle) }
    }
}

/// The shorthand the vendor page prints with no legend of its own.
enum DietaryTag: String, CaseIterable, Identifiable {
    case vegetarian = "V"
    case vegan = "VG"
    case glutenFree = "GF"
    case dairyFree = "DF"
    case nutFree = "NF"
    case sugarFree = "SF"

    init?(code: String) {
        self.init(rawValue: code.uppercased())
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .glutenFree: return "Gluten-free"
        case .dairyFree: return "Dairy-free"
        case .nutFree: return "Nut-free"
        case .sugarFree: return "Sugar-free"
        }
    }
}

extension VendorData {
    var allVendors: [Vendor] { areas.flatMap(\.vendors) }

    /// Distinct stands, counting a vendor parked in two areas once.
    var vendorCount: Int { Set(allVendors.map(\.id)).count }

    /// Dietary tags anyone on site offers, in the order the enum declares them.
    var presentTags: [DietaryTag] {
        let present = Set(allVendors.flatMap { $0.tags + $0.optionTags })
        return DietaryTag.allCases.filter(present.contains)
    }

    /// Everywhere this stand appears — a couple of them run two locations.
    func locations(of vendorID: String) -> [VendorArea] {
        areas.filter { $0.vendors.contains { $0.id == vendorID } }
    }

    /// Areas with the vendors that survive the search text and dietary filter, dropping
    /// any area left with nothing.
    func matchingAreas(query: String, tags: Set<DietaryTag>) -> [VendorArea] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return areas.compactMap { area in
            let vendors = area.vendors.filter { vendor in
                (needle.isEmpty || vendor.matches(needle))
                    && tags.allSatisfy(vendor.serves)
            }
            return vendors.isEmpty
                ? nil
                : VendorArea(id: area.id, name: area.name, vendors: vendors)
        }
    }
}
