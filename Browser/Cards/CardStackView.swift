import SwiftUI

/// Renders the cards for the current plan. One card today; the stack
/// exists so a plan can grow to several cards without touching the shell.
struct CardStackView: View {
    @Environment(BrowserSession.self) private var session
    let plans: [CardPlan]

    var body: some View {
        if plans.isEmpty {
            emptyState
        } else {
            ForEach(plans, id: \.self) { plan in
                card(for: plan)
            }
        }
    }

    @ViewBuilder
    private func card(for plan: CardPlan) -> some View {
        switch plan {
        case .web:
            WebCardView(page: session.page)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Search anything")
                .font(.title2.weight(.semibold))
            Text("A query becomes the card that answers it.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
