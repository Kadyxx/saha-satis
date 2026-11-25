import XCTest
@testable import SahaSatis

final class PostponeRuleTests: XCTestCase {
    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 11, 25, 14)

    private func newDate(_ due: Date, _ option: PostponeOption) -> Date {
        PostponeRule.newDueDate(current: due, option: option, now: now, calendar: cal)
    }

    func testTodayTaskPostponedByDaysKeepsItsTime() {
        let due = TestCalendar.date(2026, 11, 25, 9)
        XCTAssertEqual(newDate(due, .days(1)), TestCalendar.date(2026, 11, 26, 9))
        XCTAssertEqual(newDate(due, .days(3)), TestCalendar.date(2026, 11, 28, 9))
        XCTAssertEqual(newDate(due, .days(7)), TestCalendar.date(2026, 12, 2, 9))
    }

    func testOverdueTaskIsCountedFromToday() {
        let due = TestCalendar.date(2026, 11, 20, 9, 30)
        XCTAssertEqual(newDate(due, .days(1)), TestCalendar.date(2026, 11, 26, 9, 30))
        XCTAssertEqual(newDate(due, .days(3)), TestCalendar.date(2026, 11, 28, 9, 30))
    }

    func testFutureTaskIsCountedFromItsOwnDay() {
        let due = TestCalendar.date(2026, 11, 27, 9)
        XCTAssertEqual(newDate(due, .days(1)), TestCalendar.date(2026, 11, 28, 9))
    }

    func testChosenDateKeepsTimeOfDay() {
        let due = TestCalendar.date(2026, 11, 20, 16, 15)
        let chosen = TestCalendar.date(2026, 12, 10, 0)
        XCTAssertEqual(newDate(due, .date(chosen)), TestCalendar.date(2026, 12, 10, 16, 15))
    }

    func testTomorrowShortcutIsOneDay() {
        XCTAssertEqual(PostponeOption.tomorrow, .days(1))
    }

    func testTitles() {
        XCTAssertEqual(PostponeOption.presets.map(\.title), ["1 gün", "3 gün", "1 hafta"])
        XCTAssertEqual(PostponeOption.date(Date()).title, "Tarih seç…")
    }

    func testBackgroundRefreshRunsEarlyNextMorning() {
        XCTAssertEqual(
            BackgroundRefresh.nextEarliestDate(after: TestCalendar.date(2026, 11, 25, 10), calendar: cal),
            TestCalendar.date(2026, 11, 26, 5)
        )
        XCTAssertEqual(
            BackgroundRefresh.nextEarliestDate(after: TestCalendar.date(2026, 11, 25, 3), calendar: cal),
            TestCalendar.date(2026, 11, 25, 5)
        )
    }
}
