import Foundation
import Testing
@testable import Routing

@Suite struct PlaceTimeZonesTests {
    private let us = Locale(identifier: "en_US")

    private func zone(_ place: String, locale: Locale? = nil) -> String? {
        PlaceTimeZones.resolve(place, locale: locale ?? us)?.timeZone.identifier
    }

    private func label(_ place: String, locale: Locale? = nil) -> String? {
        PlaceTimeZones.resolve(place, locale: locale ?? us)?.label
    }

    @Test func citiesComeFromTheDeviceZoneDatabase() {
        #expect(zone("tokyo") == "Asia/Tokyo")
        #expect(zone("mexico city") == "America/Mexico_City")
        #expect(zone("buenos aires") == "America/Argentina/Buenos_Aires")
        #expect(zone("St. John's") == "America/St_Johns")
        #expect(zone("Port-au-Prince") == "America/Port-au-Prince")
        #expect(zone("zürich") == "Europe/Zurich")
        #expect(zone("são paulo") == "America/Sao_Paulo")
        #expect(label("tokyo") == nil)
    }

    @Test func aliasesWinOverTheDatabase() {
        #expect(zone("nyc") == "America/New_York")
        #expect(zone("sf") == "America/Los_Angeles")
        #expect(zone("L.A.") == "America/Los_Angeles")
        #expect(zone("kolkata") == "Asia/Kolkata")
        #expect(zone("beijing") == "Asia/Shanghai")
        #expect(zone("saigon") == "Asia/Ho_Chi_Minh")
        #expect(zone("san juan") == "America/Puerto_Rico")
        #expect(zone("the hague") == "Europe/Amsterdam")
        #expect(zone("washington") == "America/New_York")
        #expect(label("washington") == "Washington, DC")
    }

    @Test func countriesByEnglishAndColloquialName() {
        #expect(zone("mexico") == "America/Mexico_City")
        #expect(label("mexico") == "Mexico City")
        #expect(zone("japan") == "Asia/Tokyo")
        #expect(label("japan") == nil)
        #expect(zone("united states") == "America/New_York")
        #expect(zone("usa") == "America/New_York")
        #expect(zone("U.S.") == "America/New_York")
        #expect(zone("uk") == "Europe/London")
        #expect(zone("the uk") == "Europe/London")
        #expect(zone("the philippines") == "Asia/Manila")
        #expect(zone("turkey") == "Europe/Istanbul")
        #expect(zone("türkiye") == "Europe/Istanbul")
        #expect(zone("ivory coast") == "Africa/Abidjan")
        #expect(zone("cote d'ivoire") == "Africa/Abidjan")
        #expect(zone("burma") == "Asia/Yangon")
        #expect(zone("myanmar") == "Asia/Yangon")
        #expect(zone("bosnia and herzegovina") == "Europe/Sarajevo")
        #expect(zone("south korea") == "Asia/Seoul")
        #expect(zone("australia") == "Australia/Sydney")
        #expect(label("australia") == "Sydney")
    }

    @Test func countryNamesInTheUsersLanguage() {
        let german = Locale(identifier: "de_DE")
        #expect(zone("deutschland", locale: german) == "Europe/Berlin")
        #expect(zone("vereinigte staaten", locale: german) == "America/New_York")
        #expect(zone("mexiko", locale: german) == "America/Mexico_City")
        #expect(zone("deutschland") == nil, "an English locale knows only English names")
    }

    @Test func statesAndTheGeorgiaAmbiguity() {
        #expect(zone("california") == "America/Los_Angeles")
        #expect(zone("texas") == "America/Chicago")
        #expect(zone("florida") == "America/New_York")
        #expect(label("florida") == "Miami")
        #expect(zone("georgia") == "America/New_York")
        #expect(label("georgia") == "Atlanta")
        #expect(zone("georgia", locale: Locale(identifier: "en_GB")) == "Asia/Tbilisi")
        #expect(label("georgia", locale: Locale(identifier: "en_GB")) == "Tbilisi")
    }

    @Test func wordsThatAreZoneCitiesButNotPlacesPeopleMean() {
        for name in PlaceTimeZones.denylist {
            #expect(zone(name) == nil, "\(name)")
        }
    }

    @Test func compoundsAndUnknownsDoNotResolve() {
        for place in ["mexico vs spain", "mexico and spain", "mexico city airport", "mexico tomorrow", "narnia", "the", ""] {
            #expect(zone(place) == nil, "\(place)")
        }
    }

    @Test func everyTableRowIsAValidZoneWithANormalisedKey() {
        for (name, row) in PlaceTimeZones.aliases {
            #expect(TimeZone(identifier: row.zone) != nil, "\(name): \(row.zone)")
            #expect(TimeQuery.normalized(name).joined(separator: " ") == name, "\(name)")
        }
        for (name, row) in PlaceTimeZones.states {
            #expect(TimeZone(identifier: row.zone) != nil, "\(name): \(row.zone)")
            #expect(TimeQuery.normalized(name).joined(separator: " ") == name, "\(name)")
        }
        for (code, row) in PlaceTimeZones.countries {
            #expect(TimeZone(identifier: row.zone) != nil, "\(code): \(row.zone)")
            #expect(code.count == 2, "\(code)")
            #expect(Locale(identifier: "en_US").localizedString(forRegionCode: code) != nil, "\(code)")
        }
        for (name, code) in PlaceTimeZones.countryAliases {
            #expect(PlaceTimeZones.countries[code] != nil, "\(name) → \(code)")
            #expect(TimeQuery.normalized(name).joined(separator: " ") == name, "\(name)")
        }
        for name in PlaceTimeZones.denylist {
            #expect(TimeQuery.normalized(name).joined(separator: " ") == name, "\(name)")
        }
    }

    @Test func countriesThatSpanZonesNameTheirCity() {
        for code in ["MX", "US", "CA", "BR", "AU", "RU", "ID", "CL", "KZ"] {
            #expect(PlaceTimeZones.countries[code]?.label != nil, "\(code)")
        }
    }
}
