import Answers
import SwiftUI

extension AttributedString {
    /// Answer spans as attributed text: bold and italic through presentation
    /// intents, underline as a single line, highlight as the palette purple
    /// behind white text. `Text` renders all four natively.
    init(spans: [StyledSpan], ink: Color) {
        var result = AttributedString()
        for span in spans {
            var run = AttributedString(span.text)
            var intent: InlinePresentationIntent = []
            if span.styles.contains(.bold) { intent.insert(.stronglyEmphasized) }
            if span.styles.contains(.italic) { intent.insert(.emphasized) }
            if !intent.isEmpty { run.inlinePresentationIntent = intent }
            if span.styles.contains(.underline) { run.underlineStyle = .single }
            if span.styles.contains(.highlight) {
                run.backgroundColor = Palette.highlight
                run.foregroundColor = .white
            } else {
                run.foregroundColor = ink
            }
            result.append(run)
        }
        self = result
    }
}
