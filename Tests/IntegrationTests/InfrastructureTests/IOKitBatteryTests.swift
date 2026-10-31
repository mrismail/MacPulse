import Foundation
import MacPulseDomain
import Testing
@testable import MacPulseInfrastructure

/// Runs against the real machine. Must pass on MacBooks (battery) and on desktop Macs
/// or CI virtual machines (no battery).
@Suite("IOKit battery (integration)")
struct IOKitBatteryTests {
    @Test func readingIsConsistentWithHardware() async {
        let now = Date()
        let reading = await IOKitBatteryReadingSource().currentReading(at: now)
        #expect(reading.timestamp == now)

        guard reading.hasBattery else {
            // Desktop / VM: nothing may claim to be measured except the power source.
            #expect(reading.charge.value == nil)
            #expect(reading.cycleCount.value == nil)
            #expect(reading.healthPercentage.value == nil)
            return
        }

        let charge = reading.charge.value
        #expect(charge != nil)
        if let charge {
            #expect((0...100).contains(charge))
        }
        #expect(reading.powerSource.isAvailable)
        #expect(reading.chargingState.isAvailable)
        if let cycles = reading.cycleCount.value {
            #expect(cycles >= 0)
        }
        if let health = reading.healthPercentage.value {
            #expect((30...130).contains(health))
            #expect(!reading.healthPercentage.isMeasured)  // always labeled as an estimate
        }
    }

    @Test func probeReturnsWithoutCrashing() {
        let raw = IOKitBatteryProbe.read()
        if !raw.hasInternalBattery {
            #expect(raw.registry == nil)
        }
    }

    @Test func signedIntegersAreDecodedFromUnsignedStorage() {
        // Amperage while discharging is stored as an unsigned 64-bit two's-complement value.
        let stored = NSNumber(value: UInt64(bitPattern: -1_480))
        #expect(IOKitBatteryProbe.int(stored) == -1_480)
        #expect(IOKitBatteryProbe.int(NSNumber(value: 12_210)) == 12_210)
        #expect(IOKitBatteryProbe.int("12") == nil)
        #expect(IOKitBatteryProbe.int(nil) == nil)
    }

    @Test func powerEventStreamCanBeCancelled() async {
        let stream = IOKitPowerSourceEvents().events()
        let task = Task {
            for await _ in stream {}
        }
        task.cancel()
        await task.value  // finishes because cancellation terminates the stream
    }
}
