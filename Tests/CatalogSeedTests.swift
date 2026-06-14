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

    func testSeedDecodesWithExpectedCorridors() throws {
        let c = try loadSeed()

        XCTAssertEqual(c.schemaVersion, 5)
        XCTAssertEqual(c.schemaVersion, CatalogService.maxSupportedSchema,
                       "Seed schema and the app's schema guard must move together")
        XCTAssertFalse(c.catalogUpdated.isEmpty)

        XCTAssertEqual(c.corridors.map(\.id), ["usd_thb", "eur_thb", "aud_thb", "cny_thb", "usdt_thb"])
        for cor in c.corridors {
            XCTAssertFalse(cor.base.isEmpty)
            XCTAssertFalse(cor.baseSymbol.isEmpty)
            XCTAssertFalse(cor.label.isEmpty)
            let ids = cor.legs.map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "\(cor.id): duplicate leg ids")
            for l in cor.legs {
                XCTAssertFalse(l.label.isEmpty, "\(cor.id)/\(l.id): empty label")
            }
        }

        let usd = c.corridors[0]
        XCTAssertEqual(Set(usd.legs.map(\.id)), [
            "booth", "schwab_debit_atm", "wise_card_atm", "revolut_card_atm",
            "atm_debit", "cc_advance",
            "wise_transfer_bank", "remitly_transfer_bank", "revolut_transfer_bank",
            "xe_transfer_bank", "ofx_transfer_bank",
        ])

        let eur = c.corridors[1]
        XCTAssertTrue(eur.legs.contains { $0.id == "trade_republic_atm" }, "EUR hero card missing")
        XCTAssertTrue(eur.legs.contains { $0.id == "instarem_transfer_bank" })

        let aud = c.corridors[2]
        XCTAssertTrue(aud.legs.contains { $0.id == "macquarie_atm" }, "AUD hero card missing")
        XCTAssertTrue(aud.legs.contains { $0.id == "instarem_transfer_bank" })

        let cny = c.corridors[3]
        XCTAssertTrue(cny.legs.contains { $0.id == "unionpay_atm" }, "CNY UnionPay rail missing")
        XCTAssertTrue(cny.legs.contains { $0.id == "alipay_remit_bank" })
        // AEON's ATM network is defunct — it must never reappear in a locator.
        for cor in c.corridors {
            for (_, dir) in cor.directories ?? [:] {
                XCTAssertFalse(dir.entries.contains { $0.id == "aeon" },
                               "\(cor.id): defunct AEON entry present")
            }
        }

        let usdt = c.corridors[4]
        XCTAssertEqual(Set(usdt.legs.map(\.id)), ["binance_th_usdt", "bitkub_usdt", "bitazza_usdt"])
        XCTAssertTrue(usdt.legs.allSatisfy { $0.group == .cryptoThb })
        XCTAssertEqual(usdt.stablecoin, true, "USDT corridor must be flagged stablecoin")

        // Crypto lives ONLY in its own corridor — never in the fiat menus.
        for cor in c.corridors.dropLast() {
            XCTAssertFalse(cor.legs.contains { $0.group == .cryptoThb },
                           "\(cor.id): crypto leg leaked into a fiat corridor")
        }
    }

    func testSeedBoothsAndDirectories() throws {
        let c = try loadSeed()

        // Every fiat corridor carries the booth directory + ATM locator.
        for cor in c.corridors where cor.id != "usdt_thb" {
            let booths = try XCTUnwrap(cor.booths, "\(cor.id): booths missing")
            XCTAssertFalse(booths.isEmpty)
            for b in booths {
                XCTAssertFalse(b.id.isEmpty)
                XCTAssertFalse(b.name.isEmpty, "\(b.id): empty name")
                XCTAssertFalse(b.areas.isEmpty, "\(b.id): empty areas")
            }

            let dirs = try XCTUnwrap(cor.directories, "\(cor.id): directories missing")
            let atm = try XCTUnwrap(dirs["atm_cash"], "\(cor.id): atm_cash locator missing")
            XCTAssertFalse(atm.entries.isEmpty)
            for e in atm.entries {
                XCTAssertFalse(e.id.isEmpty)
                XCTAssertFalse(e.name.isEmpty, "\(e.id): empty name")
                XCTAssertFalse(e.areas.isEmpty, "\(e.id): empty areas")
            }
        }
    }

    /// Smoke test: every corridor's legs run through the engine and yield a
    /// usable result with a defaults profile — no leg hits the rate-unavailable
    /// path. Mid rates roughly match each base so the math stays plausible.
    func testSeedComparesCleanly() throws {
        let c = try loadSeed()
        let mids: [String: Decimal] = ["USD": 33, "EUR": 38, "AUD": 23, "CNY": 4.85, "USDT": 33]

        for cor in c.corridors {
            let rMid = try XCTUnwrap(mids[cor.base], "\(cor.id): no test mid for \(cor.base)")
            let out = Engine.compare(legs: cor.legs, profile: Profile(),
                                     targetThb: 35_000, rMid: rMid)
            XCTAssertEqual(Set(out.keys), Set(cor.legs.map(\.group)))
            for (group, results) in out {
                XCTAssertEqual(results.filter(\.isBest).count, 1, "\(cor.id)/\(group): exactly one best")
                for r in results {
                    XCTAssertTrue(r.usdCost > 0, "\(cor.id)/\(r.id): no cost computed")
                    XCTAssertTrue(r.effectiveRate > 0, "\(cor.id)/\(r.id): no rate")
                }
            }
        }
    }
}
