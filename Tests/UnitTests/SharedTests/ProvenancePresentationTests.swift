import MacPulseDomain
import Testing
@testable import MacPulseShared

@Suite("Provenance presentation")
struct ProvenancePresentationTests {
    @Test func badgeTitlesAreDistinct() {
        let titles = [
            MetricProvenance.measured.badgeTitle,
            MetricProvenance.estimated(basis: "x").badgeTitle,
            MetricProvenance.unavailable(.notYetSampled).badgeTitle,
        ]
        #expect(Set(titles).count == 3)
    }

    @Test func estimateExplanationIncludesBasis() {
        let provenance = MetricProvenance.estimated(basis: "Based on the last 15 minutes of discharge.")
        #expect(provenance.explanation.contains("Based on the last 15 minutes of discharge."))
        #expect(provenance.kind == .estimated)
    }

    @Test(arguments: [
        UnavailabilityReason.notSupportedOnThisMac,
        .permissionRequired,
        .notYetSampled,
        .notYetImplemented,
        .sourceError("code 5"),
    ])
    func everyUnavailabilityReasonIsExplained(reason: UnavailabilityReason) {
        let provenance = MetricProvenance.unavailable(reason)
        #expect(!provenance.explanation.isEmpty)
        #expect(provenance.explanation == reason.explanation)
        #expect(provenance.kind == .unavailable)
    }

    @Test func sourceErrorDetailIsShown() {
        #expect(UnavailabilityReason.sourceError("code 5").explanation.contains("code 5"))
    }
}
