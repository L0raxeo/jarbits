import CoreLocation
import Engine
import MapKit

/// A place to read the weather for: where it is, what Jarbits calls it, and
/// the time zone its hours are shown in.
struct WeatherPlace: Sendable {
    var location: CLLocation
    var name: String
    var timeZone: TimeZone
}

/// Where the weather is read for. Here is the user's approximate city, read
/// the first time it is needed and kept for 15 minutes; the permission
/// prompt appears on that first use, not at launch. A named place is found
/// by MapKit's geocoder, as a person would type it.
@MainActor
final class Places {
    static let shared = Places()

    /// Held for the app's life so Core Location keeps the when-in-use grant warm.
    private var serviceSession: CLServiceSession?
    private var here: (place: WeatherPlace, at: Date)?
    private var inFlight: Task<Result<WeatherPlace, PlaceError>, Never>?
    private let maxAge: TimeInterval = 15 * 60

    enum PlaceError: Error {
        case denied, unavailable, unknown(String)

        /// Why, in Jarbits's words, for the planner to take over from.
        var reason: String {
            switch self {
            case .denied: "I'm not allowed to know where you are; name a place, or allow location for Jarbits in Settings"
            case .unavailable: "I couldn't tell where you are just now"
            case let .unknown(name): "I don't know where \(name) is"
            }
        }
    }

    /// The place the words named, or here when they named none.
    func resolve(_ name: String?) async -> Result<WeatherPlace, PlaceError> {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return await named(name)
        }
        return await current()
    }

    func current() async -> Result<WeatherPlace, PlaceError> {
        if let here, Date.now.timeIntervalSince(here.at) < maxAge { return .success(here.place) }
        if let inFlight { return await inFlight.value }
        if serviceSession == nil { serviceSession = CLServiceSession(authorization: .whenInUse) }
        let task = Task { await Self.locate() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        if case let .success(place) = result { here = (place, .now) }
        return result
    }

    private static func locate() async -> Result<WeatherPlace, PlaceError> {
        // The first time, the permission prompt is up: wait for the user's answer, not just the fix.
        let asking = CLLocationManager().authorizationStatus == .notDetermined
        do {
            return try await withTimeout(asking ? .seconds(60) : .seconds(8)) {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                        return .failure(.denied)
                    }
                    guard let location = update.location else { continue }
                    return .success(await named(at: location))
                }
                return .failure(.unavailable)
            }
        } catch {
            return .failure(.unavailable)
        }
    }

    /// The city around `location`; "here" when it has no name.
    private static func named(at location: CLLocation) async -> WeatherPlace {
        let item = try? await MKReverseGeocodingRequest(location: location)?.mapItems.first
        let name = item?.addressRepresentations?.cityName ?? item?.name ?? "here"
        return WeatherPlace(location: location, name: name, timeZone: item?.timeZone ?? .current)
    }

    private func named(_ name: String) async -> Result<WeatherPlace, PlaceError> {
        guard let request = MKGeocodingRequest(addressString: name),
              let item = try? await request.mapItems.first else {
            return .failure(.unknown(name))
        }
        let label = item.addressRepresentations?.cityName ?? item.name ?? name
        return .success(WeatherPlace(location: item.location, name: label, timeZone: item.timeZone ?? .current))
    }
}
