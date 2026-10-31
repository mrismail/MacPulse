import Testing
@testable import MacPulseDomain

@Suite("Metric")
struct MetricTests {
    @Test func measuredCarriesValueAndProvenance() {
        let metric = Metric<Double>.measured(0.82)
        #expect(metric.value == 0.82)
        #expect(metric.provenance == .measured)
        #expect(metric.isAvailable)
        #expect(metric.isMeasured)
    }

    @Test func estimatedKeepsBasis() {
        let metric = Metric<Int>.estimated(185, basis: "Based on the last 15 minutes")
        #expect(metric.value == 185)
        #expect(metric.provenance == .estimated(basis: "Based on the last 15 minutes"))
        #expect(metric.isAvailable)
        #expect(!metric.isMeasured)
    }

    @Test(arguments: [
        UnavailabilityReason.notSupportedOnThisMac,
        .permissionRequired,
        .notYetSampled,
        .notYetImplemented,
        .sourceError("bad value"),
    ])
    func unavailableNeverHasValue(reason: UnavailabilityReason) {
        let metric = Metric<UInt64>.unavailable(reason)
        #expect(metric.value == nil)
        #expect(!metric.isAvailable)
        #expect(!metric.isMeasured)
        #expect(metric.provenance == .unavailable(reason))
    }

    @Test func mapPreservesProvenance() {
        let estimate = Metric<Int>.estimated(90, basis: "basis").map { Double($0) / 60 }
        #expect(estimate.value == 1.5)
        #expect(estimate.provenance == .estimated(basis: "basis"))

        let missing = Metric<Int>.unavailable(.notYetSampled).map { $0 * 2 }
        #expect(missing.value == nil)
        #expect(missing.provenance == .unavailable(.notYetSampled))
    }
}
