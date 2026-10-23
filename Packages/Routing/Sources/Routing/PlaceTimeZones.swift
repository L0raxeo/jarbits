import Foundation

/// A place resolved to a zone, with the city to name when the place itself
/// spans several ("7:56 PM in Mexico City" for "Mexico").
public struct PlaceZone: Equatable, Sendable {
    public var timeZone: TimeZone
    public var label: String?

    public init(timeZone: TimeZone, label: String? = nil) {
        self.timeZone = timeZone
        self.label = label
    }
}

/// A table row: a zone identifier and, when the row stands for an area
/// with more than one zone, the city whose time is shown.
struct CountryZone: Hashable, Sendable {
    var zone: String
    var label: String?

    init(_ zone: String, label: String? = nil) {
        self.zone = zone
        self.label = label
    }
}

/// Place names to time zones by exact match on normalised words, no model.
/// Order: a denylist of zone cities that are English words, hand aliases,
/// US states, countries by name (localised through Foundation), then every
/// city in the device's zone database. Anything else is unknown, so a
/// compound like "mexico vs spain" never resolves.
public enum PlaceTimeZones {
    public static func resolve(_ place: String, locale: Locale = .current) -> PlaceZone? {
        let words = TimeQuery.normalized(place)
        guard !words.isEmpty else { return nil }
        if let found = lookup(words.joined(separator: " "), locale: locale) { return found }
        if words.first == "the", words.count > 1 {
            return lookup(words.dropFirst().joined(separator: " "), locale: locale)
        }
        return nil
    }

    static func lookup(_ name: String, locale: Locale) -> PlaceZone? {
        if denylist.contains(name) { return nil }
        if name == "georgia" {
            // The state at home, the country everywhere else; the label says which.
            return locale.region?.identifier == "US" ? zone(states[name]) : country("GE")
        }
        if let alias = aliases[name] { return zone(alias) }
        if let code = countryAliases[name] { return country(code) }
        if let state = states[name] { return zone(state) }
        if let code = englishCountryNames[name] ?? localizedCountryNames(locale)[name] { return country(code) }
        if let id = derivedCities[name] { return zone(CountryZone(id)) }
        return nil
    }

    private static func zone(_ row: CountryZone?) -> PlaceZone? {
        guard let row, let timeZone = TimeZone(identifier: row.zone) else { return nil }
        return PlaceZone(timeZone: timeZone, label: row.label)
    }

    private static func country(_ code: String) -> PlaceZone? {
        zone(countries[code])
    }

    /// Zone cities that are also English words or the wrong place for most
    /// people, so they never resolve ("what time is it in center").
    static let denylist: Set<String> = [
        "center", "gmt", "troll", "wake", "oral", "knox", "resolute", "christmas", "easter", "canary", "jersey",
        "petersburg", "south pole", "south georgia", "currie", "norfolk", "davis", "casey", "palmer", "johnston",
    ]

    /// Cities the zone database spells differently or lacks, and
    /// ambiguities settled by hand. Keys are normalised words.
    static let aliases: [String: CountryZone] = [
        "nyc": CountryZone("America/New_York"), "new york city": CountryZone("America/New_York"),
        "manhattan": CountryZone("America/New_York"), "brooklyn": CountryZone("America/New_York"),
        "boston": CountryZone("America/New_York"), "philadelphia": CountryZone("America/New_York"),
        "philly": CountryZone("America/New_York"), "miami": CountryZone("America/New_York"),
        "atlanta": CountryZone("America/New_York"), "orlando": CountryZone("America/New_York"),
        "tampa": CountryZone("America/New_York"), "charlotte": CountryZone("America/New_York"),
        "pittsburgh": CountryZone("America/New_York"), "baltimore": CountryZone("America/New_York"),
        "washington": CountryZone("America/New_York", label: "Washington, DC"),
        "washington dc": CountryZone("America/New_York"), "dc": CountryZone("America/New_York"),
        "washington state": CountryZone("America/Los_Angeles"),
        "houston": CountryZone("America/Chicago"), "dallas": CountryZone("America/Chicago"),
        "austin": CountryZone("America/Chicago"), "san antonio": CountryZone("America/Chicago"),
        "new orleans": CountryZone("America/Chicago"), "minneapolis": CountryZone("America/Chicago"),
        "st louis": CountryZone("America/Chicago"), "kansas city": CountryZone("America/Chicago"),
        "nashville": CountryZone("America/Chicago"), "memphis": CountryZone("America/Chicago"),
        "milwaukee": CountryZone("America/Chicago"), "oklahoma city": CountryZone("America/Chicago"),
        "salt lake city": CountryZone("America/Denver"), "albuquerque": CountryZone("America/Denver"),
        "la": CountryZone("America/Los_Angeles"), "sf": CountryZone("America/Los_Angeles"),
        "san francisco": CountryZone("America/Los_Angeles"), "silicon valley": CountryZone("America/Los_Angeles"),
        "oakland": CountryZone("America/Los_Angeles"), "san diego": CountryZone("America/Los_Angeles"),
        "seattle": CountryZone("America/Los_Angeles"), "portland": CountryZone("America/Los_Angeles"),
        "las vegas": CountryZone("America/Los_Angeles"), "vegas": CountryZone("America/Los_Angeles"),
        "sacramento": CountryZone("America/Los_Angeles"),
        "ottawa": CountryZone("America/Toronto"), "quebec": CountryZone("America/Toronto"),
        "quebec city": CountryZone("America/Toronto"), "calgary": CountryZone("America/Edmonton"),
        "san juan": CountryZone("America/Puerto_Rico"),
        "cdmx": CountryZone("America/Mexico_City"), "ciudad de mexico": CountryZone("America/Mexico_City"),
        "mexico df": CountryZone("America/Mexico_City"), "guadalajara": CountryZone("America/Mexico_City"),
        "rio": CountryZone("America/Sao_Paulo"), "rio de janeiro": CountryZone("America/Sao_Paulo"),
        "brasilia": CountryZone("America/Sao_Paulo"),
        "manchester": CountryZone("Europe/London"), "birmingham": CountryZone("Europe/London"),
        "edinburgh": CountryZone("Europe/London"), "glasgow": CountryZone("Europe/London"),
        "liverpool": CountryZone("Europe/London"), "cambridge": CountryZone("Europe/London"),
        "oxford": CountryZone("Europe/London"), "belfast": CountryZone("Europe/London"),
        "the hague": CountryZone("Europe/Amsterdam"), "rotterdam": CountryZone("Europe/Amsterdam"),
        "munich": CountryZone("Europe/Berlin"), "frankfurt": CountryZone("Europe/Berlin"),
        "hamburg": CountryZone("Europe/Berlin"), "cologne": CountryZone("Europe/Berlin"),
        "milan": CountryZone("Europe/Rome"), "florence": CountryZone("Europe/Rome"),
        "venice": CountryZone("Europe/Rome"), "naples": CountryZone("Europe/Rome"),
        "barcelona": CountryZone("Europe/Madrid"), "seville": CountryZone("Europe/Madrid"),
        "lyon": CountryZone("Europe/Paris"), "marseille": CountryZone("Europe/Paris"), "nice": CountryZone("Europe/Paris"),
        "geneva": CountryZone("Europe/Zurich"), "basel": CountryZone("Europe/Zurich"), "bern": CountryZone("Europe/Zurich"),
        "krakow": CountryZone("Europe/Warsaw"), "porto": CountryZone("Europe/Lisbon"),
        "st petersburg": CountryZone("Europe/Moscow"),
        "ankara": CountryZone("Europe/Istanbul"),
        "tel aviv": CountryZone("Asia/Jerusalem"), "haifa": CountryZone("Asia/Jerusalem"),
        "abu dhabi": CountryZone("Asia/Dubai"), "doha": CountryZone("Asia/Qatar"),
        "mecca": CountryZone("Asia/Riyadh"), "jeddah": CountryZone("Asia/Riyadh"),
        "islamabad": CountryZone("Asia/Karachi"), "lahore": CountryZone("Asia/Karachi"),
        "kolkata": CountryZone("Asia/Kolkata"), "calcutta": CountryZone("Asia/Kolkata"),
        "mumbai": CountryZone("Asia/Kolkata"), "bombay": CountryZone("Asia/Kolkata"),
        "delhi": CountryZone("Asia/Kolkata"), "new delhi": CountryZone("Asia/Kolkata"),
        "bangalore": CountryZone("Asia/Kolkata"), "bengaluru": CountryZone("Asia/Kolkata"),
        "chennai": CountryZone("Asia/Kolkata"), "madras": CountryZone("Asia/Kolkata"),
        "hyderabad": CountryZone("Asia/Kolkata"), "pune": CountryZone("Asia/Kolkata"), "goa": CountryZone("Asia/Kolkata"),
        "beijing": CountryZone("Asia/Shanghai"), "peking": CountryZone("Asia/Shanghai"),
        "shenzhen": CountryZone("Asia/Shanghai"), "guangzhou": CountryZone("Asia/Shanghai"),
        "saigon": CountryZone("Asia/Ho_Chi_Minh"), "ho chi minh city": CountryZone("Asia/Ho_Chi_Minh"),
        "hanoi": CountryZone("Asia/Ho_Chi_Minh"),
        "phuket": CountryZone("Asia/Bangkok"), "chiang mai": CountryZone("Asia/Bangkok"),
        "bali": CountryZone("Asia/Makassar"), "denpasar": CountryZone("Asia/Makassar"),
        "kyoto": CountryZone("Asia/Tokyo"), "osaka": CountryZone("Asia/Tokyo"), "busan": CountryZone("Asia/Seoul"),
        "canberra": CountryZone("Australia/Sydney"), "gold coast": CountryZone("Australia/Brisbane"),
        "cape town": CountryZone("Africa/Johannesburg"), "durban": CountryZone("Africa/Johannesburg"),
        "marrakech": CountryZone("Africa/Casablanca"), "marrakesh": CountryZone("Africa/Casablanca"),
    ]

    /// Colloquial country names, keyed by normalised words, to ISO codes in
    /// `countries`. Foundation's own names ("Türkiye", "Myanmar (Burma)")
    /// are added at run time; these are the spellings people type.
    static let countryAliases: [String: String] = [
        "uk": "GB", "united kingdom": "GB", "england": "GB", "britain": "GB", "great britain": "GB",
        "scotland": "GB", "wales": "GB", "northern ireland": "GB",
        "usa": "US", "us": "US", "america": "US", "united states of america": "US", "the states": "US",
        "uae": "AE", "emirates": "AE", "saudi": "SA", "holland": "NL",
        "korea": "KR", "south korea": "KR", "north korea": "KP",
        "turkey": "TR", "ivory coast": "CI",
        "congo": "CD", "drc": "CD", "dr congo": "CD", "democratic republic of the congo": "CD",
        "republic of the congo": "CG", "congo brazzaville": "CG",
        "burma": "MM", "bosnia": "BA", "czech republic": "CZ", "swaziland": "SZ", "palestine": "PS",
        "macau": "MO", "macao": "MO", "viet nam": "VN", "east timor": "TL", "slovak republic": "SK",
        "vatican": "VA", "the vatican": "VA", "cabo verde": "CV", "the gambia": "GM",
    ]

    /// US states and DC: the zone most of the state keeps, with the main
    /// city named where the state is split.
    static let states: [String: CountryZone] = [
        "alabama": CountryZone("America/Chicago"), "alaska": CountryZone("America/Anchorage"),
        "arizona": CountryZone("America/Phoenix"), "arkansas": CountryZone("America/Chicago"),
        "california": CountryZone("America/Los_Angeles"), "colorado": CountryZone("America/Denver"),
        "connecticut": CountryZone("America/New_York"), "delaware": CountryZone("America/New_York"),
        "florida": CountryZone("America/New_York", label: "Miami"),
        "georgia": CountryZone("America/New_York", label: "Atlanta"),
        "hawaii": CountryZone("Pacific/Honolulu"), "idaho": CountryZone("America/Boise", label: "Boise"),
        "illinois": CountryZone("America/Chicago"),
        "indiana": CountryZone("America/Indiana/Indianapolis", label: "Indianapolis"),
        "iowa": CountryZone("America/Chicago"), "kansas": CountryZone("America/Chicago"),
        "kentucky": CountryZone("America/Kentucky/Louisville", label: "Louisville"),
        "louisiana": CountryZone("America/Chicago"), "maine": CountryZone("America/New_York"),
        "maryland": CountryZone("America/New_York"), "massachusetts": CountryZone("America/New_York"),
        "michigan": CountryZone("America/Detroit"), "minnesota": CountryZone("America/Chicago"),
        "mississippi": CountryZone("America/Chicago"), "missouri": CountryZone("America/Chicago"),
        "montana": CountryZone("America/Denver"), "nebraska": CountryZone("America/Chicago", label: "Omaha"),
        "nevada": CountryZone("America/Los_Angeles"), "new hampshire": CountryZone("America/New_York"),
        "new jersey": CountryZone("America/New_York"), "new mexico": CountryZone("America/Denver"),
        "new york": CountryZone("America/New_York"), "north carolina": CountryZone("America/New_York"),
        "north dakota": CountryZone("America/Chicago"), "ohio": CountryZone("America/New_York"),
        "oklahoma": CountryZone("America/Chicago"), "oregon": CountryZone("America/Los_Angeles"),
        "pennsylvania": CountryZone("America/New_York"), "rhode island": CountryZone("America/New_York"),
        "south carolina": CountryZone("America/New_York"),
        "south dakota": CountryZone("America/Chicago", label: "Sioux Falls"),
        "tennessee": CountryZone("America/Chicago", label: "Nashville"),
        "texas": CountryZone("America/Chicago"), "utah": CountryZone("America/Denver"),
        "vermont": CountryZone("America/New_York"), "virginia": CountryZone("America/New_York"),
        "west virginia": CountryZone("America/New_York"), "wisconsin": CountryZone("America/Chicago"),
        "wyoming": CountryZone("America/Denver"), "puerto rico": CountryZone("America/Puerto_Rico"),
    ]

    /// Every ISO 3166 country with a zone, keyed by code. Single-zone rows
    /// come from tzdata's zone.tab; the rows with a label are countries
    /// that span zones, each pinned to its capital or largest city by hand.
    static let countries: [String: CountryZone] = [
        "AD": CountryZone("Europe/Andorra"),
        "AE": CountryZone("Asia/Dubai"),
        "AF": CountryZone("Asia/Kabul"),
        "AG": CountryZone("America/Antigua"),
        "AI": CountryZone("America/Anguilla"),
        "AL": CountryZone("Europe/Tirane"),
        "AM": CountryZone("Asia/Yerevan"),
        "AO": CountryZone("Africa/Luanda"),
        "AS": CountryZone("Pacific/Pago_Pago"),
        "AT": CountryZone("Europe/Vienna"),
        "AW": CountryZone("America/Aruba"),
        "AX": CountryZone("Europe/Mariehamn"),
        "AZ": CountryZone("Asia/Baku"),
        "BA": CountryZone("Europe/Sarajevo"),
        "BB": CountryZone("America/Barbados"),
        "BD": CountryZone("Asia/Dhaka"),
        "BE": CountryZone("Europe/Brussels"),
        "BF": CountryZone("Africa/Ouagadougou"),
        "BG": CountryZone("Europe/Sofia"),
        "BH": CountryZone("Asia/Bahrain"),
        "BI": CountryZone("Africa/Bujumbura"),
        "BJ": CountryZone("Africa/Porto-Novo"),
        "BL": CountryZone("America/St_Barthelemy"),
        "BM": CountryZone("Atlantic/Bermuda"),
        "BN": CountryZone("Asia/Brunei"),
        "BO": CountryZone("America/La_Paz"),
        "BQ": CountryZone("America/Kralendijk"),
        "BS": CountryZone("America/Nassau"),
        "BT": CountryZone("Asia/Thimphu"),
        "BW": CountryZone("Africa/Gaborone"),
        "BY": CountryZone("Europe/Minsk"),
        "BZ": CountryZone("America/Belize"),
        "CC": CountryZone("Indian/Cocos"),
        "CF": CountryZone("Africa/Bangui"),
        "CG": CountryZone("Africa/Brazzaville"),
        "CH": CountryZone("Europe/Zurich"),
        "CI": CountryZone("Africa/Abidjan"),
        "CK": CountryZone("Pacific/Rarotonga"),
        "CM": CountryZone("Africa/Douala"),
        "CO": CountryZone("America/Bogota"),
        "CR": CountryZone("America/Costa_Rica"),
        "CU": CountryZone("America/Havana"),
        "CV": CountryZone("Atlantic/Cape_Verde"),
        "CW": CountryZone("America/Curacao"),
        "CX": CountryZone("Indian/Christmas"),
        "CZ": CountryZone("Europe/Prague"),
        "DJ": CountryZone("Africa/Djibouti"),
        "DK": CountryZone("Europe/Copenhagen"),
        "DM": CountryZone("America/Dominica"),
        "DO": CountryZone("America/Santo_Domingo"),
        "DZ": CountryZone("Africa/Algiers"),
        "EE": CountryZone("Europe/Tallinn"),
        "EG": CountryZone("Africa/Cairo"),
        "EH": CountryZone("Africa/El_Aaiun"),
        "ER": CountryZone("Africa/Asmara"),
        "ET": CountryZone("Africa/Addis_Ababa"),
        "FI": CountryZone("Europe/Helsinki"),
        "FJ": CountryZone("Pacific/Fiji"),
        "FK": CountryZone("Atlantic/Stanley"),
        "FO": CountryZone("Atlantic/Faroe"),
        "FR": CountryZone("Europe/Paris"),
        "GA": CountryZone("Africa/Libreville"),
        "GB": CountryZone("Europe/London"),
        "GD": CountryZone("America/Grenada"),
        "GF": CountryZone("America/Cayenne"),
        "GG": CountryZone("Europe/Guernsey"),
        "GH": CountryZone("Africa/Accra"),
        "GI": CountryZone("Europe/Gibraltar"),
        "GM": CountryZone("Africa/Banjul"),
        "GN": CountryZone("Africa/Conakry"),
        "GP": CountryZone("America/Guadeloupe"),
        "GQ": CountryZone("Africa/Malabo"),
        "GR": CountryZone("Europe/Athens"),
        "GS": CountryZone("Atlantic/South_Georgia"),
        "GT": CountryZone("America/Guatemala"),
        "GU": CountryZone("Pacific/Guam"),
        "GW": CountryZone("Africa/Bissau"),
        "GY": CountryZone("America/Guyana"),
        "HK": CountryZone("Asia/Hong_Kong"),
        "HN": CountryZone("America/Tegucigalpa"),
        "HR": CountryZone("Europe/Zagreb"),
        "HT": CountryZone("America/Port-au-Prince"),
        "HU": CountryZone("Europe/Budapest"),
        "IE": CountryZone("Europe/Dublin"),
        "IL": CountryZone("Asia/Jerusalem"),
        "IM": CountryZone("Europe/Isle_of_Man"),
        "IN": CountryZone("Asia/Kolkata"),
        "IO": CountryZone("Indian/Chagos"),
        "IQ": CountryZone("Asia/Baghdad"),
        "IR": CountryZone("Asia/Tehran"),
        "IS": CountryZone("Atlantic/Reykjavik"),
        "IT": CountryZone("Europe/Rome"),
        "JE": CountryZone("Europe/Jersey"),
        "JM": CountryZone("America/Jamaica"),
        "JO": CountryZone("Asia/Amman"),
        "JP": CountryZone("Asia/Tokyo"),
        "KE": CountryZone("Africa/Nairobi"),
        "KG": CountryZone("Asia/Bishkek"),
        "KH": CountryZone("Asia/Phnom_Penh"),
        "KM": CountryZone("Indian/Comoro"),
        "KN": CountryZone("America/St_Kitts"),
        "KP": CountryZone("Asia/Pyongyang"),
        "KR": CountryZone("Asia/Seoul"),
        "KW": CountryZone("Asia/Kuwait"),
        "KY": CountryZone("America/Cayman"),
        "LA": CountryZone("Asia/Vientiane"),
        "LB": CountryZone("Asia/Beirut"),
        "LC": CountryZone("America/St_Lucia"),
        "LI": CountryZone("Europe/Vaduz"),
        "LK": CountryZone("Asia/Colombo"),
        "LR": CountryZone("Africa/Monrovia"),
        "LS": CountryZone("Africa/Maseru"),
        "LT": CountryZone("Europe/Vilnius"),
        "LU": CountryZone("Europe/Luxembourg"),
        "LV": CountryZone("Europe/Riga"),
        "LY": CountryZone("Africa/Tripoli"),
        "MA": CountryZone("Africa/Casablanca"),
        "MC": CountryZone("Europe/Monaco"),
        "MD": CountryZone("Europe/Chisinau"),
        "ME": CountryZone("Europe/Podgorica"),
        "MF": CountryZone("America/Marigot"),
        "MG": CountryZone("Indian/Antananarivo"),
        "MK": CountryZone("Europe/Skopje"),
        "ML": CountryZone("Africa/Bamako"),
        "MM": CountryZone("Asia/Yangon"),
        "MO": CountryZone("Asia/Macau"),
        "MP": CountryZone("Pacific/Saipan"),
        "MQ": CountryZone("America/Martinique"),
        "MR": CountryZone("Africa/Nouakchott"),
        "MS": CountryZone("America/Montserrat"),
        "MT": CountryZone("Europe/Malta"),
        "MU": CountryZone("Indian/Mauritius"),
        "MV": CountryZone("Indian/Maldives"),
        "MW": CountryZone("Africa/Blantyre"),
        "MZ": CountryZone("Africa/Maputo"),
        "NA": CountryZone("Africa/Windhoek"),
        "NC": CountryZone("Pacific/Noumea"),
        "NE": CountryZone("Africa/Niamey"),
        "NF": CountryZone("Pacific/Norfolk"),
        "NG": CountryZone("Africa/Lagos"),
        "NI": CountryZone("America/Managua"),
        "NL": CountryZone("Europe/Amsterdam"),
        "NO": CountryZone("Europe/Oslo"),
        "NP": CountryZone("Asia/Kathmandu"),
        "NR": CountryZone("Pacific/Nauru"),
        "NU": CountryZone("Pacific/Niue"),
        "OM": CountryZone("Asia/Muscat"),
        "PA": CountryZone("America/Panama"),
        "PE": CountryZone("America/Lima"),
        "PH": CountryZone("Asia/Manila"),
        "PK": CountryZone("Asia/Karachi"),
        "PL": CountryZone("Europe/Warsaw"),
        "PM": CountryZone("America/Miquelon"),
        "PN": CountryZone("Pacific/Pitcairn"),
        "PR": CountryZone("America/Puerto_Rico"),
        "PW": CountryZone("Pacific/Palau"),
        "PY": CountryZone("America/Asuncion"),
        "QA": CountryZone("Asia/Qatar"),
        "RE": CountryZone("Indian/Reunion"),
        "RO": CountryZone("Europe/Bucharest"),
        "RS": CountryZone("Europe/Belgrade"),
        "RW": CountryZone("Africa/Kigali"),
        "SA": CountryZone("Asia/Riyadh"),
        "SB": CountryZone("Pacific/Guadalcanal"),
        "SC": CountryZone("Indian/Mahe"),
        "SD": CountryZone("Africa/Khartoum"),
        "SE": CountryZone("Europe/Stockholm"),
        "SG": CountryZone("Asia/Singapore"),
        "SH": CountryZone("Atlantic/St_Helena"),
        "SI": CountryZone("Europe/Ljubljana"),
        "SJ": CountryZone("Arctic/Longyearbyen"),
        "SK": CountryZone("Europe/Bratislava"),
        "SL": CountryZone("Africa/Freetown"),
        "SM": CountryZone("Europe/San_Marino"),
        "SN": CountryZone("Africa/Dakar"),
        "SO": CountryZone("Africa/Mogadishu"),
        "SR": CountryZone("America/Paramaribo"),
        "SS": CountryZone("Africa/Juba"),
        "ST": CountryZone("Africa/Sao_Tome"),
        "SV": CountryZone("America/El_Salvador"),
        "SX": CountryZone("America/Lower_Princes"),
        "SY": CountryZone("Asia/Damascus"),
        "SZ": CountryZone("Africa/Mbabane"),
        "TC": CountryZone("America/Grand_Turk"),
        "TD": CountryZone("Africa/Ndjamena"),
        "TF": CountryZone("Indian/Kerguelen"),
        "TG": CountryZone("Africa/Lome"),
        "TH": CountryZone("Asia/Bangkok"),
        "TJ": CountryZone("Asia/Dushanbe"),
        "TK": CountryZone("Pacific/Fakaofo"),
        "TL": CountryZone("Asia/Dili"),
        "TM": CountryZone("Asia/Ashgabat"),
        "TN": CountryZone("Africa/Tunis"),
        "TO": CountryZone("Pacific/Tongatapu"),
        "TR": CountryZone("Europe/Istanbul"),
        "TT": CountryZone("America/Port_of_Spain"),
        "TV": CountryZone("Pacific/Funafuti"),
        "TW": CountryZone("Asia/Taipei"),
        "TZ": CountryZone("Africa/Dar_es_Salaam"),
        "UG": CountryZone("Africa/Kampala"),
        "UY": CountryZone("America/Montevideo"),
        "VA": CountryZone("Europe/Vatican"),
        "VC": CountryZone("America/St_Vincent"),
        "VE": CountryZone("America/Caracas"),
        "VG": CountryZone("America/Tortola"),
        "VI": CountryZone("America/St_Thomas"),
        "VN": CountryZone("Asia/Ho_Chi_Minh"),
        "VU": CountryZone("Pacific/Efate"),
        "WF": CountryZone("Pacific/Wallis"),
        "WS": CountryZone("Pacific/Apia"),
        "YE": CountryZone("Asia/Aden"),
        "YT": CountryZone("Indian/Mayotte"),
        "ZA": CountryZone("Africa/Johannesburg"),
        "ZM": CountryZone("Africa/Lusaka"),
        "ZW": CountryZone("Africa/Harare"),
        "GE": CountryZone("Asia/Tbilisi", label: "Tbilisi"),
        "AR": CountryZone("America/Argentina/Buenos_Aires"),
        "AU": CountryZone("Australia/Sydney", label: "Sydney"),
        "BR": CountryZone("America/Sao_Paulo", label: "Brasília"),
        "CA": CountryZone("America/Toronto", label: "Toronto"),
        "CD": CountryZone("Africa/Kinshasa", label: "Kinshasa"),
        "CL": CountryZone("America/Santiago", label: "Santiago"),
        "CN": CountryZone("Asia/Shanghai"),
        "CY": CountryZone("Asia/Nicosia"),
        "DE": CountryZone("Europe/Berlin"),
        "EC": CountryZone("America/Guayaquil"),
        "ES": CountryZone("Europe/Madrid"),
        "FM": CountryZone("Pacific/Pohnpei", label: "Pohnpei"),
        "GL": CountryZone("America/Nuuk", label: "Nuuk"),
        "ID": CountryZone("Asia/Jakarta", label: "Jakarta"),
        "KI": CountryZone("Pacific/Tarawa", label: "Tarawa"),
        "KZ": CountryZone("Asia/Almaty", label: "Almaty"),
        "MH": CountryZone("Pacific/Majuro"),
        "MN": CountryZone("Asia/Ulaanbaatar"),
        "MX": CountryZone("America/Mexico_City", label: "Mexico City"),
        "MY": CountryZone("Asia/Kuala_Lumpur"),
        "NZ": CountryZone("Pacific/Auckland"),
        "PF": CountryZone("Pacific/Tahiti", label: "Tahiti"),
        "PG": CountryZone("Pacific/Port_Moresby"),
        "PS": CountryZone("Asia/Gaza"),
        "PT": CountryZone("Europe/Lisbon"),
        "RU": CountryZone("Europe/Moscow", label: "Moscow"),
        "UA": CountryZone("Europe/Kyiv"),
        "US": CountryZone("America/New_York", label: "New York"),
        "UZ": CountryZone("Asia/Tashkent"),
    ]

    /// Normalised English country names to codes, from Foundation.
    static let englishCountryNames: [String: String] = countryNames(for: Locale(identifier: "en_US"))

    /// The same in the user's language, when it is not English.
    static func localizedCountryNames(_ locale: Locale) -> [String: String] {
        guard locale.language.languageCode != .english else { return [:] }
        return countryNames(for: locale)
    }

    static func countryNames(for locale: Locale) -> [String: String] {
        var names: [String: String] = [:]
        for code in countries.keys.sorted() {
            guard let name = locale.localizedString(forRegionCode: code) else { continue }
            for variant in variants(of: name) where names[variant] == nil {
                names[variant] = code
            }
        }
        return names
    }

    /// "Myanmar (Burma)" is also "myanmar" and "burma"; "Bosnia & Herzegovina"
    /// is also "bosnia and herzegovina".
    static func variants(of name: String) -> [String] {
        var raw = [name, name.replacingOccurrences(of: "&", with: " and ")]
        if let open = name.firstIndex(of: "("), let close = name.firstIndex(of: ")"), open < close {
            raw.append(String(name[..<open]))
            raw.append(String(name[name.index(after: open)..<close]))
        }
        return raw.map { TimeQuery.normalized($0).joined(separator: " ") }.filter { !$0.isEmpty }
    }

    /// Every city in the device's zone database by its normalised name:
    /// "America/Mexico_City" is "mexico city". Built once.
    static let derivedCities: [String: String] = {
        var cities: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let last = identifier.split(separator: "/").last else { continue }
            let name = TimeQuery.normalized(last.replacingOccurrences(of: "_", with: " ")).joined(separator: " ")
            if cities[name] == nil { cities[name] = identifier }
        }
        return cities
    }()
}
