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
    private let enUS = Locale(identifier: "en_US")

    @Test func formatsHoursAndMinutes() {
        let text = DurationFormatting.string(fromMinutes: 205, locale: enUS)
        #expect(text.contains("3"))
        #expect(text.contains("25"))
        #expect(text.contains("hr"))
        #expect(text.contains("min"))
    }

    @Test func wholeHoursOmitZeroMinutes() {
        let text = DurationFormatting.string(fromMinutes: 120, locale: enUS)
        #expect(text.contains("2"))
        #expect(!text.contains("min"))
    }

    @Test func negativeIsTreatedAsZero() {
        #expect(
            DurationFormatting.string(fromMinutes: -5, locale: enUS)
                == DurationFormatting.string(fromMinutes: 0, locale: enUS)
        )
    }

    @Test func usesLocaleDigits() {
        let text = DurationFormatting.string(fromMinutes: 45, locale: Locale(identifier: "ar_EG"))
        #expect(text.contains("٤٥"))
    }
}
