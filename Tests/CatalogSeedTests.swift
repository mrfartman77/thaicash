import XCTest
@testable import ThaiCash

/// The bundled seed must always decode with the app's strict JSONDecoder —
/// one enum value the models don't know fails the whole decode and the app
/// silently falls back to the empty catalog.
@MainActor
final class CatalogSeedTests: XCTestCase {

    private func loadSeed() throws -> Catalog {
        // Hosted unit tests run inside the app, so the seed lives in Bundle.main;
        // fall back to the test bundle just in case.
        let url = Bundle.main.url(forResource: "catalog", withExtension: "json")
            ?? Bundle(for: CatalogSeedTests.self).url(forResource: "catalog", withExtension: "json")
        let u = try XCTUnwrap(url, "catalog.json missing from the bundle")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: u))
    }

    func testSeedDecodesWithExpectedLegs() throws {
        let c = try loadSeed()

        XCTAssertEqual(c.schemaVersion, 4)
        XCTAssertEqual(c.schemaVersion, CatalogService.maxSupportedSchema,
                       "Seed schema and the app's schema guard must move together")
        XCTAssertFalse(c.catalogUpdated.isEmpty)
        XCTAssertTrue(c.atmHostFeeThb > 0)
        XCTAssertTrue(c.atmCapThb > 0)

        let expectedIds: Set<String> = [
            "booth", "schwab_debit_atm", "wise_card_atm", "revolut_card_atm",
            "atm_debit", "cc_advance",
            "wise_transfer_bank", "remitly_transfer_bank", "revolut_transfer_bank",
            "xe_transfer_bank", "ofx_transfer_bank",
            "binance_th_usdt", "bitkub_usdt", "bitazza_usdt",
        ]
        XCTAssertEqual(c.legs.count, 14)
        XCTAssertEqual(Set(c.legs.map(\.id)), expectedIds)   // count + set ⇒ no duplicates

        for l in c.legs {
            XCTAssertFalse(l.label.isEmpty, "\(l.id): empty label")
        }
    }

    func testSeedBoothsAndDirectories() throws {
        let c = try loadSeed()

        let booths = try XCTUnwrap(c.booths)
        XCTAssertFalse(booths.isEmpty)
        for b in booths {
            XCTAssertFalse(b.id.isEmpty)
            XCTAssertFalse(b.name.isEmpty, "\(b.id): empty name")
            XCTAssertFalse(b.areas.isEmpty, "\(b.id): empty areas")
        }

        let dirs = try XCTUnwrap(c.directories)
        let atm = try XCTUnwrap(dirs["atm_cash"], "atm_cash locator missing")
        XCTAssertFalse(atm.entries.isEmpty)
        for e in atm.entries {
            XCTAssertFalse(e.id.isEmpty)
            XCTAssertFalse(e.name.isEmpty, "\(e.id): empty name")
            XCTAssertFalse(e.areas.isEmpty, "\(e.id): empty areas")
        }
    }

    /// Smoke test: every seed leg runs through the engine and yields a usable
    /// result with a defaults profile — no leg hits the rate-unavailable path.
    func testSeedComparesCleanly() throws {
        let c = try loadSeed()
        let out = Engine.compare(catalog: c, profile: Profile(), targetThb: 35_000, rMid: 35)

        XCTAssertEqual(Set(out.keys), Set(c.legs.map(\.group)))
        for (group, results) in out {
            XCTAssertEqual(results.filter(\.isBest).count, 1, "\(group): exactly one best")
            for r in results {
                XCTAssertTrue(r.usdCost > 0, "\(r.id): no cost computed")
                XCTAssertTrue(r.effectiveRate > 0, "\(r.id): no rate")
            }
        }
    }
}
