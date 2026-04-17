import SwiftUI

struct PickerOption: Identifiable, Equatable {
    var id: String
    var label: String
    var value: String
}

struct SearchablePicker: View {
    var placeholder: String = "请选择"
    var options: [PickerOption]
    @Binding var selectedValue: String?

    @State private var isOpen = false
    @State private var searchText = ""
    @State private var highlightedIndex = 0
    @FocusState private var searchFocused: Bool

    private var filtered: [PickerOption] {
        searchText.isEmpty ? options : options.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedLabel: String {
        options.first(where: { $0.value == selectedValue })?.label ?? placeholder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isOpen.toggle()
                if isOpen { searchFocused = true; highlightedIndex = 0 }
            } label: {
                HStack {
                    Text(selectedLabel)
                        .font(.bodyMedium)
                        .foregroundStyle(selectedValue == nil ? Color.text3 : Color.text0)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.labelSmall)
                        .foregroundStyle(Color.text3)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
                .background(Color.bg1)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(isOpen ? Color.accent : Color.border0, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 0) {
                    TextField("搜索...", text: $searchText)
                        .textFieldStyle(AppTextFieldStyle())
                        .focused($searchFocused)
                        .padding(Spacing.xs)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, option in
                                Button {
                                    selectedValue = option.value
                                    isOpen = false
                                    searchText = ""
                                } label: {
                                    HStack {
                                        Text(option.label)
                                            .font(.bodyMedium)
                                            .foregroundStyle(Color.text0)
                                        Spacer()
                                        if option.value == selectedValue {
                                            Image(systemName: "checkmark")
                                                .font(.labelSmall)
                                                .foregroundStyle(Color.accent)
                                        }
                                    }
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.sm)
                                    .background(idx == highlightedIndex ? Color.accentLight : Color.clear)
                                }
                                .buttonStyle(.plain)
                                .onHover { if $0 { highlightedIndex = idx } }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .cardShadow()
                .zIndex(100)
            }
        }
        .onKeyPress(.escape) { isOpen = false; return .handled }
        .onKeyPress(.return) {
            if isOpen, !filtered.isEmpty {
                selectedValue = filtered[min(highlightedIndex, filtered.count - 1)].value
                isOpen = false
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if highlightedIndex > 0 { highlightedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if highlightedIndex < filtered.count - 1 { highlightedIndex += 1 }
            return .handled
        }
    }
}
