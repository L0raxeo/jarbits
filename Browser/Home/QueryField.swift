import SwiftUI

/// The search field inside a gradient capsule: white text and caret, a white
/// prompt, a web-search keyboard with a Go key. Shared by the orb and the
/// follow-up capsule so typing feels the same in both.
struct QueryField: View {
    @Binding var draft: String
    var focus: FocusState<Bool>.Binding
    var onSubmit: () -> Void

    var body: some View {
        TextField("", text: $draft, prompt: Text("Ask anything").foregroundStyle(.white.opacity(0.7)))
            .font(.body)
            .foregroundStyle(.white)
            .tint(.white)
            .focused(focus)
            .keyboardType(.webSearch)
            .submitLabel(.go)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(onSubmit)
            .padding(.horizontal, 20)
    }
}
