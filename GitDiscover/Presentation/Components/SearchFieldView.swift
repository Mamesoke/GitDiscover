import SwiftUI

struct SearchFieldView: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("search-field")
            Button {
                text = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .disabled(text.isEmpty)
            .accessibilityLabel("Clear search")
            .accessibilityIdentifier("clear-search")
            .help("Clear search")
        }
    }
}
