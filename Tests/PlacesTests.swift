import XCTest
@testable import Autopiloto

final class PlacesTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()
    private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h, minute: m))! }

    private var places: Places {
        var p = Places()
        p.upsert(Place(id: "office", name: "Office"))
        p.upsert(Place(id: "gym", name: "Gym"))
        p.setTravel("home", "office", minutes: 30)
        p.setTravel("office", "gym", minutes: 20)
        p.setTravel("home", "gym", minutes: 15)
        return p
    }

    func testTravelMatrixIsSymmetricAndLegsFollowTheDay() {
        let p = places
        XCTAssertEqual(p.minutes(from: "gym", to: "office"), 20)
        XCTAssertEqual(p.minutes(from: "gym", to: "gym"), 0)
        XCTAssertEqual(p.minutes(from: nil, to: "gym"), 0)
        let blocks = [
            Block(id: "w", label: "Wake", kind: .fixed, start: .hm(7, 0), end: .hm(7, 10), isAnchor: true),
            Block(id: "o", label: "Work", kind: .fixed, start: .hm(10, 0), end: .hm(17, 0), place: "office"),
            Block(id: "l", label: "Lunch", kind: .window, start: .hm(13, 0), end: .hm(13, 40)),            // no place: stays at the office
            Block(id: "g", label: "Gym", kind: .window, start: .hm(19, 0), end: .hm(20, 0), place: "gym"),
            Block(id: "d", label: "Dinner", kind: .window, start: .hm(20, 30), end: .hm(21, 0), place: "home"),
        ]
        let legs = DayLogic.travelLegs(blocks, places: p)
        XCTAssertEqual(legs["o"]?.minutes, 30); XCTAssertEqual(legs["o"]?.from, "Home")
        XCTAssertNil(legs["l"])
        XCTAssertEqual(legs["g"]?.minutes, 20); XCTAssertEqual(legs["g"]?.from, "Office")
        XCTAssertEqual(legs["d"]?.minutes, 15)
        var removed = p; removed.remove(id: "gym")
        XCTAssertEqual(removed.minutes(from: "home", to: "gym"), 0)
        XCTAssertEqual(removed.list.count, 2)
    }

    func testReplanKeepsTravelTimeAroundPlacedBlocks() {
        let work = Block(id: "o", label: "Work", kind: .fixed, start: .hm(10, 0), end: .hm(17, 0), place: "office")
        let gym = Block(id: "g", label: "Gym", kind: .window, start: .hm(8, 0), end: .hm(9, 0), place: "gym")   // missed morning gym
        let ctx = Replanner.Context(plan: [work, gym], override: DayOverride(), now: date(16, 8, 30), dayEnd: .hm(23, 0),
                                    completed: [], skipped: [], calendar: calendar, places: places)
        // Before work only 9:00 → 9:40 is free (20 min travel to the office); an hour fits after work: 17:00 + 20 min → 17:20.
        guard case .moved(let o, _, _) = Replanner.replan(gym, in: ctx) else { return XCTFail() }
        XCTAssertEqual(o.moved["g"]?.start, .hm(17, 20))

        // An explicit time that ignores the commute is refused with the reason.
        if case .rejected(let why) = Replanner.place(gym, at: .hm(17, 5), in: ctx) { XCTAssertTrue(why.contains("Work")) } else { XCTFail() }
        if case .rejected(let why) = Replanner.place(gym, at: .hm(9, 0), in: ctx) { XCTAssertTrue(why.contains("afterwards")) } else { XCTFail() }
        guard case .moved = Replanner.place(gym, at: .hm(17, 30), in: ctx) else { return XCTFail() }
    }

    func testLeaveRemindersFireTravelMinutesBeforeStart() {
        let blocks = [
            Block(id: "w", label: "Wake", kind: .fixed, start: .hm(7, 0), end: .hm(7, 10), isAnchor: true),
            Block(id: "o", label: "Work", kind: .fixed, start: .hm(10, 0), end: .hm(17, 0), place: "office"),
            Block(id: "g", label: "Gym", kind: .window, start: .hm(19, 0), end: .hm(20, 0), place: "gym"),
        ]
        let requests = NotificationScheduler.buildCheckIns(plan: { _ in blocks }, now: date(16, 8), completed: { _ in [] }, skipped: { $0 == "2026-09-16" ? ["o"] : [] },
                                                           checkIns: false, places: places, calendar: calendar)
        let leave = requests.filter { $0.identifier.hasPrefix("leave-") }
        XCTAssertEqual(leave.map(\.identifier), ["leave-g-2026-09-16", "leave-o-2026-09-17", "leave-g-2026-09-17"])   // work skipped today → no reminder
        let gymToday = leave[0]
        XCTAssertEqual(gymToday.content.title, "Leave for Gym")
        let trigger = gymToday.trigger as! UNCalendarNotificationTrigger
        XCTAssertEqual(trigger.dateComponents.hour, 18); XCTAssertEqual(trigger.dateComponents.minute, 40)   // 19:00 − 20 min (office → gym)
    }
}

final class PlacesMapsTests: XCTestCase {
    func testEstimablePairsSkipTypedValuesAndUnpinned() {
        var p = Places()
        p.upsert(Place(id: "office", name: "Office", latitude: 19.42, longitude: -99.17))
        p.upsert(Place(id: "gym", name: "Gym", latitude: 19.41, longitude: -99.16))
        p.upsert(Place(id: "track", name: "Track"))   // not pinned
        var home = p.list[0]; home.latitude = 19.43; home.longitude = -99.18; p.upsert(home)
        XCTAssertEqual(p.estimablePairs.count, 3)     // home-office, home-gym, office-gym
        p.setTravel("home", "office", minutes: 40)    // typed by hand → left alone
        XCTAssertEqual(p.estimablePairs.count, 2)
        p.setTravel("home", "gym", minutes: 20, estimated: true)
        XCTAssertEqual(p.estimablePairs.count, 2)     // estimates can be refreshed
        XCTAssertTrue(p.estimated.contains(Places.key("gym", "home")))
        p.setTravel("home", "gym", minutes: 25)       // typed over → no longer an estimate
        XCTAssertFalse(p.estimated.contains(Places.key("gym", "home")))

        // Older places.json (no coordinates / estimated / mode) still decodes.
        let legacy = Data(#"{"list":[{"id":"home","name":"Home","note":""}],"travel":{}}"#.utf8)
        let decoded = try? JSONDecoder().decode(Places.self, from: legacy)
        XCTAssertEqual(decoded?.mode, "driving")
        XCTAssertEqual(decoded?.list.first?.isPinned, false)
    }
}
