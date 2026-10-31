import Foundation
import Testing
@testable import MacPulseShared

@Suite("NumberFormatting")
struct NumberFormattingTests {
    private let enUS = Locale(identifier: "en_US")

    @Test func percentRoundsToWholeNumbers() {
        #expect(NumberFormatting.percent(72, locale: enUS) == "72%")
        #expect(NumberFormatting.percent(89.6, locale: enUS) == "90%")
        #expect(NumberFormatting.percent(0, locale: enUS) == "0%")
    }

    @Test func measurementUsesUnitAndPrecision() {
        #expect(NumberFormatting.measurement(31.07, unit: "°C", locale: enUS) == "31.1 °C")
        #expect(NumberFormatting.measurement(12.0, unit: "W", locale: enUS) == "12 W")
        #expect(NumberFormatting.measurement(12.483, unit: "V", fractionDigits: 2, locale: enUS) == "12.48 V")
    }

    @Test func measurementUsesLocaleSeparator() {
        #expect(NumberFormatting.measurement(12.5, unit: "V", locale: Locale(identifier: "de_DE")) == "12,5 V")
    }

    @Test func percentPerHour() {
        #expect(NumberFormatting.percentPerHour(14.62, locale: enUS) == "14.6% per hour")
    }
}
