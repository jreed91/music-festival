import Foundation

/// Reading `schedule.json` from wherever the newest copy is.
///
/// The app has `ScheduleStore` for this, but a widget timeline runs in the extension's
/// process with no `ScheduleStore` in it, and a Live Activity has to agree with the app
/// about what time Lorde is on. So the "bundled copy, unless a newer one was cached"
/// rule lives here once and both sides call it.
enum ScheduleFile {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Where a refreshed schedule is cached. In the app group so a set time changed
    /// mid-festival reaches the widget too, rather than the widget confidently showing
    /// the times that shipped in the binary.
    static var cacheURL: URL {
        let directory = AppGroup.containerURL ?? applicationSupport
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("schedule.json")
    }

    private static var applicationSupport: URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Builds before the widget cached into Application Support, which the extension
    /// can't see. Move that copy across once rather than discarding a refresh someone
    /// picked up in the car on the way down.
    static func migrateLegacyCacheIfNeeded() {
        guard AppGroup.containerURL != nil else { return }
        let manager = FileManager.default
        let legacy = applicationSupport.appendingPathComponent("schedule.json")
        let destination = cacheURL
        guard manager.fileExists(atPath: legacy.path),
              !manager.fileExists(atPath: destination.path) else { return }
        try? manager.moveItem(at: legacy, to: destination)
    }

    static func decode(_ data: Data?) -> FestivalData? {
        guard let data else { return nil }
        return try? decoder().decode(FestivalData.self, from: data)
    }

    static func bundled(in bundle: Bundle = .main) -> FestivalData? {
        guard let url = bundle.url(forResource: "schedule", withExtension: "json") else {
            return nil
        }
        return decode(try? Data(contentsOf: url))
    }

    static func cached() -> FestivalData? {
        decode(try? Data(contentsOf: cacheURL))
    }

    /// The bundled schedule unless a cached refresh is genuinely newer, so shipping a
    /// corrected build always beats a stale download.
    static func newest(in bundle: Bundle = .main) -> FestivalData? {
        let bundled = bundled(in: bundle)
        guard let cached = cached() else { return bundled }
        guard let bundled else { return cached }
        return cached.generatedAt > bundled.generatedAt ? cached : bundled
    }
}
