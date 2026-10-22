import SwiftUI

/// The search field inside a gradient capsule: white text and caret, a white
/// prompt, a web-search keyboard with a Go key. Shared by the orb and the
/// follow-up capsule so typing feels the same in both. `selection` lets the
/// owner select the whole draft, as Safari does when you tap its address bar.
struct QueryField: View {
    @Binding var draft: String
    var focus: FocusState<Bool>.Binding
    var selection: Binding<TextSelection?> = .constant(nil)
    var onSubmit: () -> Void

    var body: some View {
        TextField("", text: $draft, selection: selection, prompt: Text("Ask anything").foregroundStyle(.white.opacity(0.7)))
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
