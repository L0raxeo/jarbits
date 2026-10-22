import CoreLocation
import MapKit
import Observation
import Routing

/// "City, Region, Country" at reduced accuracy, fetched the first time an
/// answer needs it and kept for 15 minutes. The permission prompt appears on
/// that first use, not at launch. Denied or unavailable reads as `nil` and
/// the answer request simply omits the location line.
@Observable
@MainActor
final class ApproximateLocation {
    static let shared = ApproximateLocation()

    private(set) var description: String?
    private var fetchedAt: Date?
    /// Held for the app's life so Core Location keeps the when-in-use grant warm.
    private var serviceSession: CLServiceSession?
    private var inFlight: Task<String?, Never>?

    private let maxAge: TimeInterval = 15 * 60

    func current() async -> String? {
        if let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < maxAge {
            return description
        }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await fetch() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        description = result
        fetchedAt = .now
        return result
    }

    private func fetch() async -> String? {
        if serviceSession == nil {
            serviceSession = CLServiceSession(authorization: .whenInUse)
        }
        do {
            return try await withTimeout(.seconds(8)) { try await Self.resolve() }
        } catch {
            return nil
        }
    }

    private static func resolve() async throws -> String? {
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                return nil
            }
            guard let location = update.location else { continue }
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            let items = try await request.mapItems
            guard let address = items.first?.addressRepresentations else { return nil }
            if let city = address.cityWithContext { return city }
            let parts = [address.cityName, address.regionName].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        return nil
    }
}
