import SwiftUI

/// A label/value row for detail lists (diagnostics, file info).
public struct KeyValueRow: View {
    private let label: String
    private let value: String

    public init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        LabeledContent(label) {
            Text(value)
                .textSelection(.enabled)
                .monospacedDigit()
        }
    }
}
