import Foundation
import Testing
@testable import Routing

@Suite struct LocalTimeAnswerTests {
    /// 2026-10-21 16:26:40 UTC: 11:26 in Chicago, 01:26 the next day in Tokyo.
    private let now = Date(timeIntervalSince1970: 1_792_600_000)
    private let us = Locale(identifier: "en_US")
    private let chicago = TimeZone(identifier: "America/Chicago")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func time(in zone: String, locale: Locale) -> String {
        now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: TimeZone(identifier: zone)!))
    }

    @Test func aCityOnTheSameDayIsJustTheTime() {
        let text = LocalTimeAnswer.text(for: TimeQuery(place: "london"), now: now, locale: us, homeZone: chicago)
        #expect(text == "==\(time(in: "Europe/London", locale: us))==")
        #expect(text?.contains("PM") == true)
    }

    @Test func aCountryThatSpansZonesNamesTheCity() {
        let text = LocalTimeAnswer.text(for: TimeQuery(place: "mexico"), now: now, locale: us, homeZone: chicago)
        #expect(text == "==\(time(in: "America/Mexico_City", locale: us))== in Mexico City")
    }

    @Test func aPlaceAlreadyOnTomorrowSaysSo() {
        let text = LocalTimeAnswer.text(for: TimeQuery(place: "tokyo"), now: now, locale: us, homeZone: chicago)
        #expect(text == "==\(time(in: "Asia/Tokyo", locale: us))== tomorrow")
        let australia = LocalTimeAnswer.text(for: TimeQuery(place: "australia"), now: now, locale: us, homeZone: chicago)
        #expect(australia == "==\(time(in: "Australia/Sydney", locale: us))== tomorrow in Sydney")
    }

    @Test func aPlaceStillOnYesterdaySaysSo() {
        let text = LocalTimeAnswer.text(for: TimeQuery(place: "honolulu"), now: now, locale: us, homeZone: tokyo)
        #expect(text == "==\(time(in: "Pacific/Honolulu", locale: us))== yesterday")
    }

    @Test func theBareQuestionUsesTheHomeZone() {
        let text = LocalTimeAnswer.text(for: TimeQuery(place: nil), now: now, locale: us, homeZone: tokyo)
        #expect(text == "==\(time(in: "Asia/Tokyo", locale: us))==")
    }

    @Test func theLocaleDecidesTheClock() {
        let uk = Locale(identifier: "en_GB")
        let text = LocalTimeAnswer.text(for: TimeQuery(place: "tokyo"), now: now, locale: uk, homeZone: chicago)
        #expect(text?.hasSuffix(":26== tomorrow") == true)
        #expect(text?.contains("AM") == false)
    }

    @Test func anUnknownPlaceIsNoAnswer() {
        #expect(LocalTimeAnswer.text(for: TimeQuery(place: "narnia"), now: now, locale: us, homeZone: chicago) == nil)
    }
}
