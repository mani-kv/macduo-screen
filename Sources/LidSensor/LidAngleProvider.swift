import Foundation

public protocol LidAngleProvider: AnyObject {
    var currentAngle: Double? { get }
    var onReading: ((LidReading) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    func start()
    func stop()
}
