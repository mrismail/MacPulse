import SwiftUI

/// A label/value row for detail lists (diagnostics, file info).
public struct KeyValueRow: View {
    private let label: String
    private let value: String

    /// - Parameter label: looked up in the String Catalog.
    public init(_ label: LocalizedStringResource, value: String) {
        self.label = String(localized: label)
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
