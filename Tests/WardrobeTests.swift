import XCTest
@testable import Autopiloto

@MainActor
final class WardrobeTests: XCTestCase {
    private var fileURL: URL!
    private let now = Date(timeIntervalSince1970: 1_789_000_000)

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("wardrobe.json")
    }

    private func g(_ name: String, _ c: GarmentCategory, warmth: Int = 2, formality: Formality = .casual, worn: Int = 0, lastWorn: Date? = nil) -> Garment {
        Garment(name: name, category: c, color: "x", warmth: warmth, formality: formality, washAfter: c.defaultWashAfter, wearsSinceWash: worn, lastWorn: lastWorn)
    }

    func testGuessParsesJSONInsideProse() {
        let text = "Sure:\n{\"name\":\"navy hoodie\",\"category\":\"outer\",\"color\":\"navy\",\"warmth\":5,\"formality\":\"casual\"}\nDone."
        let guess = GarmentGuess.parse(text)
        XCTAssertEqual(guess?.name, "navy hoodie")
        XCTAssertEqual(guess?.category, .outer)
        XCTAssertEqual(guess?.warmth, 3)
        XCTAssertNil(GarmentGuess.parse("no json here"))
    }

    func testOutfitPrefersCleanWarmthMatchedAndLeastRecentlyWorn() {
        let dirtyTop = g("dirty tee", .top, worn: 1)
        let cleanTop = g("clean tee", .top, warmth: 1)
        let warmTop = g("sweater", .top, warmth: 3, lastWorn: now.addingTimeInterval(-86_400 * 10))
        let jeans = g("jeans", .bottom, warmth: 2)
        let shorts = g("shorts", .bottom, warmth: 1, lastWorn: now.addingTimeInterval(-86_400))
        let shoes = g("sneakers", .shoes, formality: .sport)
        let coat = g("coat", .outer, warmth: 3)
        let closet = [dirtyTop, cleanTop, warmTop, jeans, shorts, shoes, coat]

        let hot = OutfitPicker.pick(from: closet, weather: .hot, formality: .casual, now: now).map(\.name)
        XCTAssertEqual(hot, ["clean tee", "shorts", "sneakers"])

        let cold = OutfitPicker.pick(from: closet, weather: .cold, formality: .casual, now: now).map(\.name)
        XCTAssertEqual(cold, ["sweater", "jeans", "sneakers", "coat"])
    }

    func testWearLaundryAndPersistence() {
        let store = WardrobeStore(fileURL: fileURL)
        let tee = g("tee", .top)
        let jeans = g("jeans", .bottom)
        store.add(tee, imageData: nil)
        store.add(jeans, imageData: nil)
        store.wear([tee, jeans], now: now)
        store.wear([tee], now: now)   // same day: no double count
        XCTAssertEqual(store.closet.first { $0.id == tee.id }?.wearsSinceWash, 1)
        XCTAssertEqual(store.laundry.map(\.name), ["tee"])
        XCTAssertEqual(store.todaysOutfit(now: now)?.count, 2)

        let again = WardrobeStore(fileURL: fileURL)
        XCTAssertEqual(again.laundry.map(\.name), ["tee"])
        again.washed(id: tee.id)
        XCTAssertTrue(again.laundry.isEmpty)
        again.wear([jeans], now: now.addingTimeInterval(86_400))
        again.wear([jeans], now: now.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(again.laundry.map(\.name), ["jeans"])
        again.washAll()
        XCTAssertTrue(again.laundry.isEmpty)
        XCTAssertTrue(again.coachSummary().contains("Closet: 2 items"))
    }
}
