import Foundation

/// The time instinct's answer, computed from the device clock: the time
/// here, or in the place the reading named. The time is wrapped in `==…==`,
/// the highlight marker the one-line answer prompt in `Answers` uses, so
/// the card styles it like a model's answer. Shapes: `==7:56 PM==`,
/// `==7:56 PM== in Mexico City`, `==9:56 AM== tomorrow`, `==9:56 AM==
/// tomorrow in Sydney`. No grammar: the place is a value the reading read.
public enum LocalTimeAnswer {
    /// Nil when the place is not one `PlaceTimeZones` knows; a nil place is here.
    public static func text(place: String?, now: Date, locale: Locale, homeZone: TimeZone) -> String? {
        let zone: PlaceZone
        if let name = place, !name.isEmpty {
            guard let found = PlaceTimeZones.resolve(name, locale: locale) else { return nil }
            zone = found
        } else {
            zone = PlaceZone(timeZone: homeZone, label: nil)
        }
        let time = now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: zone.timeZone))
        var parts = ["==\(time)=="]
        if let shift = dayShift(at: now, from: homeZone, to: zone.timeZone, locale: locale) {
            parts.append(shift)
        }
        if let label = zone.label {
            parts.append("in \(label)")
        }
        return parts.joined(separator: " ")
    }

    /// "tomorrow" or "yesterday" when the calendar date there differs from
    /// the user's; the weekday for any larger gap (none exists today, but the
    /// zone database may change). Nil on the same date.
    static func dayShift(at now: Date, from homeZone: TimeZone, to zone: TimeZone, locale: Locale) -> String? {
        var home = Calendar(identifier: .gregorian)
        home.timeZone = homeZone
        var there = Calendar(identifier: .gregorian)
        there.timeZone = zone
        let homeDay = home.dateComponents([.year, .month, .day], from: now)
        let thereDay = there.dateComponents([.year, .month, .day], from: now)
        guard homeDay != thereDay, let a = home.date(from: homeDay), let b = home.date(from: thereDay) else { return nil }
        switch home.dateComponents([.day], from: a, to: b).day {
        case 1: return "tomorrow"
        case -1: return "yesterday"
        default: return now.formatted(Date.FormatStyle(locale: locale, timeZone: zone).weekday(.abbreviated))
        }
    }
}
