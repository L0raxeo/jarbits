import Foundation

/// The seam between a query and what the app shows for it.
///
/// `LocalRouter` is the hardcoded implementation used today. The HTTP router
/// backed by the System One model replaces it once there is a second format.
protocol Router: Sendable {
    func route(_ query: String) async -> CardPlan
}
