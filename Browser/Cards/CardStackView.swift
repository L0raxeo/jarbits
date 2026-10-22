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
            // Keyed by slot, not by plan content. A `WebPage` can be shown by only one
            // `WebView` at a time; keying on the URL would rebuild the card for every
            // new query and attach a second `WebView` to the same page, which traps.
            ForEach(Array(plans.enumerated()), id: \.offset) { _, plan in
                card(for: plan)
            }
            #if DEBUG
            .overlay(alignment: .top) {
                if let decision = session.lastDecision {
                    RouteDebugRibbon(
                        decision: decision,
                        plan: plans.first,
                        answer: session.answer?.summary,
                        logURL: DecisionLog.shared.fileURL
                    )
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func card(for plan: CardPlan) -> some View {
        switch plan {
        case .web:
            WebCardView(page: session.page)
        case let .answer(format, query):
            AnswerCardView(format: format, query: query)
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
