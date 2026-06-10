import Foundation

/// Loads the method catalog. Resolution order at launch: cached → bundled seed,
/// so the app always has data offline. Remote refresh adopts newer *data* freely
/// but refuses a *structure* newer than this build understands (schema guard).
@MainActor
final class CatalogService: ObservableObject {
    @Published private(set) var data: Catalog
    @Published private(set) var needsAppUpdate = false

    static let maxSupportedSchema = 3
    static let remoteURL = URL(string: "https://cdn.yourco.com/thaicash/catalog.json")!  // replace for prod

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("thbfx_catalog.json")
    }

    init() { data = Self.loadCached() ?? Self.loadSeed() }

    func refresh() async {
        guard let fresh = try? await fetch() else { return }              // offline → keep current
        guard fresh.schemaVersion <= Self.maxSupportedSchema else {       // structure too new for this build
            needsAppUpdate = true; return
        }
        guard fresh.catalogUpdated > data.catalogUpdated else { return }  // only adopt newer data
        data = fresh
        try? JSONEncoder().encode(fresh).write(to: Self.cacheURL)
    }

    private func fetch() async throws -> Catalog {
        let (bytes, resp) = try await URLSession.shared.data(from: Self.remoteURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Catalog.self, from: bytes)
    }

    private static func loadCached() -> Catalog? {
        guard let d = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Catalog.self, from: d)
    }

    private static func loadSeed() -> Catalog {
        if let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
           let d = try? Data(contentsOf: url),
           let c = try? JSONDecoder().decode(Catalog.self, from: d) {
            return c
        }
        // Seed should always be in the bundle; this empty fallback just prevents a crash.
        return Catalog(schemaVersion: maxSupportedSchema, catalogUpdated: "1970-01-01",
                       atmHostFeeThb: 220, atmCapThb: 20_000, legs: [])
    }
}
