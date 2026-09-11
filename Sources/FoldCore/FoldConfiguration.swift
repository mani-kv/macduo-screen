import Foundation

public struct FoldConfiguration: Codable, Equatable {
    public var enabled = true
    public var startAngle = 90.0
    public var endAngle = 5.0
    public var blur = 24.0
    public var darkening = 0.85
    public var fold = false
    public var perspective = 0.65
    public var compression = 0.85
    public var showDebug = false

    public init() {}

    public mutating func applyDuoLook() {
        blur = 36
        darkening = 0.35
        fold = true
        perspective = 0.40
        compression = 0.78
    }

    public func validated() -> Self {
        var copy = self
        copy.startAngle = Self.clamp(startAngle, 15...150, fallback: 90)
        copy.endAngle = Self.clamp(endAngle, 0...(copy.startAngle - 5), fallback: 5)
        copy.blur = Self.clamp(blur, 0...60, fallback: 24)
        copy.darkening = Self.clamp(darkening, 0...1, fallback: 0.85)
        copy.perspective = Self.clamp(perspective, 0...1, fallback: 0.65)
        copy.compression = Self.clamp(compression, 0...0.95, fallback: 0.85)
        return copy
    }

    public func progress(for angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        let safe = validated()
        return min(1, max(0, (safe.startAngle - angle) / (safe.startAngle - safe.endAngle)))
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
    }
}
