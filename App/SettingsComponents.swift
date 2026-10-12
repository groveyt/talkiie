import AppKit
import NaturalInputCore
import SwiftUI

struct FeatureLabel: View {
    let title: String
    var summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct FeatureToggleRow: View {
    let title: String
    var summary: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { FeatureLabel(title: title, summary: summary) }
    }
}

struct FeatureSegmentedRow<Value: Hashable>: View {
    let title: String
    var summary: String?
    let options: [Value]
    let label: (Value) -> String
    let defaultValue: Value
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FeatureLabel(title: title, summary: summary)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            DefaultHint(defaultTitle: label(defaultValue), isDefault: selection == defaultValue) {
                selection = defaultValue
            }
        }
    }
}

struct DefaultHint: View {
    let defaultTitle: String
    let isDefault: Bool
    var reset: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text("預設：\(defaultTitle)")
            if !isDefault, let reset {
                Button("恢復預設", action: reset)
                    .buttonStyle(.link)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ExampleDisclosure<Content: View>: View {
    var title = "看例子"
    @ViewBuilder let content: () -> Content
    @State private var expanded = ExampleDisclosureDebug.startExpanded

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct ExampleBlock<Content: View>: View {
    let caption: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(caption).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.6)))
        }
        .accessibilityElement(children: .combine)
    }
}

struct DeletionExample: View {
    let original: String
    let result: String
    var resultCaption = "打出來的是"

    var body: some View {
        ExampleBlock(caption: "說的是") { Text(Self.marked(original: original, result: result)) }
        ExampleBlock(caption: resultCaption) { Text(result) }
    }

    static func marked(original: String, result: String) -> AttributedString {
        var out = AttributedString()
        for seg in ExampleDiff.segments(original: original, result: result) where seg.kind != .added {
            var piece = AttributedString(seg.text)
            if seg.kind == .removed {
                piece.strikethroughStyle = .single
                piece.foregroundColor = .secondary
            }
            out += piece
        }
        return out
    }
}

struct TagBadge: View {
    let text: String
    var symbol: String?
    var help: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(.quaternary))
        .overlay(Capsule().strokeBorder(.tertiary.opacity(0.5), lineWidth: 0.5))
        .help(help ?? "")
        .accessibilityElement(children: .combine)
    }
}

struct HoverDeleteButton: View {
    let hovering: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(hovering ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tertiary))
        .opacity(hovering ? 1 : 0.55)
        .help("刪除")
        .accessibilityLabel(accessibilityLabel)
    }
}

struct NavigationRow: View {
    let symbol: String
    let title: String
    var detail: String?
    var showsChevron = true
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SettingsIcon(symbol: symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .background(RoundedRectangle(cornerRadius: 5).fill(hovering && enabled ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear))
            .padding(-4))
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

struct SettingsIcon: View {
    let symbol: String
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.68, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum ExampleDisclosureDebug {
    #if DEBUG
    static let startExpanded = CommandLine.arguments.contains("--expand-examples")
    #else
    static let startExpanded = false
    #endif
}
