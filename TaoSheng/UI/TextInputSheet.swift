import SwiftUI

/// 一个输入框的描述。用 sheet 装输入框，而不是 .alert + TextField：
/// 系统 alert 里的 TextField 在部分机型/系统版本上会被裁成半截（真机反馈）。
struct TextInputField: Identifiable {
    enum Kind {
        case single
        case multiline
    }

    let id = UUID()
    var label: String
    var placeholder: String = ""
    var kind: Kind = .single
    var text: String = ""
}

struct TextInputSheet: View {
    let title: String
    let fields: [TextInputField]
    /// 前 N 个字段必填（去首尾空白后非空才能确定）。
    var requiredCount: Int = 1
    var confirmTitle: String = "确定"
    var message: String?
    let onCommit: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String]
    @FocusState private var focused: Int?

    init(title: String,
         fields: [TextInputField],
         requiredCount: Int = 1,
         confirmTitle: String = "确定",
         message: String? = nil,
         onCommit: @escaping ([String]) -> Void) {
        self.title = title
        self.fields = fields
        self.requiredCount = max(0, min(requiredCount, fields.count))
        self.confirmTitle = confirmTitle
        self.message = message
        self.onCommit = onCommit
        _values = State(initialValue: fields.map(\.text))
    }

    private var trimmed: [String] {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var canCommit: Bool {
        guard values.count == fields.count else { return false }
        let t = trimmed
        return (0..<requiredCount).allSatisfy { !t[$0].isEmpty }
    }

    private var detentHeight: CGFloat {
        var h: CGFloat = 132
        for f in fields {
            h += f.kind == .multiline ? 184 : 92
        }
        if message != nil { h += 34 }
        return min(max(h, 220), 560)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.sp4) {
                    ForEach(Array(fields.enumerated()), id: \.element.id) { i, field in
                        VStack(alignment: .leading, spacing: Theme.sp2) {
                            Text(field.label)
                                .font(.system(size: Theme.fsSmall, weight: .medium))
                                .foregroundStyle(Theme.text2)

                            boxed(field, index: i)
                        }
                    }

                    if let message {
                        Text(message)
                            .font(.system(size: Theme.fsCaption))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.sp4)
            }
            .background(Theme.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .tint(Theme.dim)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(confirmTitle) {
                        guard canCommit else { return }
                        onCommit(trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .tint(Theme.accent)
                    .disabled(!canCommit)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    if !fields.isEmpty { focused = 0 }
                }
            }
        }
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func boxed(_ field: TextInputField, index i: Int) -> some View {
        let binding = Binding<String>(
            get: { i < values.count ? values[i] : "" },
            set: { new in if i < values.count { values[i] = new } }
        )

        Group {
            if field.kind == .multiline {
                TextEditor(text: binding)
                    .focused($focused, equals: i)
                    .frame(minHeight: 132)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Theme.sp2)
                    .padding(.vertical, Theme.sp2)
            } else {
                TextField(field.placeholder, text: binding)
                    .focused($focused, equals: i)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .padding(.horizontal, Theme.sp3)
                    .padding(.vertical, 12)
            }
        }
        .font(.system(size: Theme.fsBody))
        .foregroundStyle(Theme.text)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.cardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .stroke(Theme.line, lineWidth: 0.8)
        )
    }
}
