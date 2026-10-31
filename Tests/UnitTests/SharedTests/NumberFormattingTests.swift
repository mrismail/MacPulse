import Foundation
import Testing
@testable import MacPulseShared

@Suite("NumberFormatting")
struct NumberFormattingTests {
    private let enUS = Locale(identifier: "en_US")
    private let enGB = Locale(identifier: "en_GB")
    private let arabic = Locale(identifier: "ar_EG")

    @Test func percentRoundsToWholeNumbers() {
        #expect(NumberFormatting.percent(72, locale: enUS) == "72%")
        #expect(NumberFormatting.percent(89.6, locale: enUS) == "90%")
        #expect(NumberFormatting.percent(0, locale: enUS) == "0%")
    }

    @Test func percentUsesLocaleDigits() {
        let result = NumberFormatting.percent(72, locale: arabic)
        #expect(!result.contains("7"))  // Arabic-Indic digits, not Latin
        #expect(result.contains("٧٢"))
    }

    @Test func percentPerHour() {
        #expect(NumberFormatting.percentPerHour(14.62, locale: enUS) == "14.6% per hour")
    }

    @Test func temperatureFollowsLocalePreference() {
        let us = NumberFormatting.temperature(celsius: 31, locale: enUS)
        let uk = NumberFormatting.temperature(celsius: 31, locale: enGB)
        #expect(us.contains("°F"))
        #expect(us.contains("87.8"))
        #expect(uk.contains("°C"))
        #expect(uk.contains("31"))
    }

    @Test func electricalUnits() {
        #expect(NumberFormatting.volts(12.483, locale: enUS) == "12.48 V")
        #expect(NumberFormatting.watts(45.0, locale: enUS) == "45 W")
        #expect(NumberFormatting.milliampereHours(7_480, locale: enUS) == "7,480 mAh")
        #expect(NumberFormatting.integer(1_204, locale: enUS) == "1,204")
    }
}
