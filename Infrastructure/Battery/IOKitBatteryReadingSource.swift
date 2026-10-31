import Foundation
import MacPulseDomain

/// Live `BatteryReadingSource` backed by IOKit.
public struct IOKitBatteryReadingSource: BatteryReadingSource {
    public init() {}

    public func currentReading(at timestamp: Date) async -> BatteryReading {
        BatteryReadingBuilder.build(from: IOKitBatteryProbe.read(), at: timestamp)
    }
}
