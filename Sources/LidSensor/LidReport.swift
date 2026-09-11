import Foundation

public struct LidReading {
    public let angle: Double
    public let rawValue: UInt16
    public let report: [UInt8]
    public let timestamp: TimeInterval
}

public enum LidReport {
    /// Report 1 exposes an unsigned 9-bit value, with matching logical and
    /// physical ranges of 0...360 on the validated Apple orientation sensor.
    public static func decode(_ bytes: [UInt8]) -> UInt16? {
        guard bytes.count >= 3, bytes[0] == 1 else { return nil }
        let value = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        guard value <= 360 else { return nil }
        return value
    }
}
