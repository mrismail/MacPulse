import Foundation
import Testing
@testable import MacPulseShared

@Suite("ByteFormatting")
struct ByteFormattingTests {
    private let enUS = Locale(identifier: "en_US")

    @Test(arguments: [
        (UInt64(0), "0 bytes"),
        (1, "1 byte"),
        (999, "999 bytes"),
        (1_000, "1 KB"),
        (1_500, "1.5 KB"),
        (1_500_000, "1.5 MB"),
        (12_345_678_900, "12.3 GB"),
        (250_000_000_000, "250 GB"),
        (999_999, "1 MB"),  // rounds up into the next unit, never "1000 KB"
        (2_000_000_000_000, "2 TB"),
    ])
    func formatsDecimalUnits(bytes: UInt64, expected: String) {
        #expect(ByteFormatting.string(fromBytes: bytes, locale: enUS) == expected)
    }

    @Test func usesLocaleDecimalSeparator() {
        let german = Locale(identifier: "de_DE")
        #expect(ByteFormatting.string(fromBytes: 1_500_000, locale: german) == "1,5 MB")
    }

    @Test func handlesMaximumValue() {
        let result = ByteFormatting.string(fromBytes: .max, locale: enUS)
        #expect(result.hasSuffix("PB"))
    }
}

@Suite("DurationFormatting")
struct DurationFormattingTests {
    @Test(arguments: [
        (-5, "0 min"),
        (0, "0 min"),
        (45, "45 min"),
        (60, "1 h"),
        (205, "3 h 25 min"),
        (600, "10 h"),
    ])
    func formatsMinutes(minutes: Int, expected: String) {
        #expect(DurationFormatting.string(fromMinutes: minutes) == expected)
    }
}
