import Foundation
import IOKit.hid

/// All device access and callbacks are serialized on the main run loop.
public final class HIDAngleProvider: LidAngleProvider {
    public private(set) var currentAngle: Double?
    public var onReading: ((LidReading) -> Void)?
    public var onError: ((String) -> Void)?
    public var onDevice: ((String) -> Void)?

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: Timer?
    private var failures = 0
    private var lastDiscovery: TimeInterval = -.infinity
    private var lastError: String?

    public init() {}

    public func start() {
        guard timer == nil else { return }
        discover()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        disconnect()
        currentAngle = nil
        lastDiscovery = -.infinity
        lastError = nil
    }

    private func disconnect() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil
    }

    private func discover() {
        lastDiscovery = ProcessInfo.processInfo.systemUptime
        disconnect()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        // Match only Apple's orientation sensor, never keyboards or mice.
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDDeviceUsagePageKey: 0x0020,
            kIOHIDDeviceUsageKey: 0x008A
        ] as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            reportError("No Apple lid-angle HID sensor found. This Mac may not expose one.")
            return
        }
        for candidate in devices {
            let result = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
            guard result == kIOReturnSuccess else {
                reportError(String(format: "Cannot open lid sensor (IOKit 0x%08x).", result))
                continue
            }
            device = candidate
            failures = 0
            let properties = [kIOHIDProductKey, kIOHIDVendorIDKey, kIOHIDProductIDKey,
                              kIOHIDPrimaryUsagePageKey, kIOHIDPrimaryUsageKey]
            let details = properties.map { key in
                "\(key)=\(IOHIDDeviceGetProperty(candidate, key as CFString).map { String(describing: $0) } ?? "unknown")"
            }.joined(separator: ", ")
            var descriptor = ""
            if let elements = IOHIDDeviceCopyMatchingElements(candidate, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
                for element in elements where IOHIDElementGetUsage(element) == 0x047F {
                    descriptor += "\nAngle element: usage=0x047F, report=\(IOHIDElementGetReportID(element)), bits=\(IOHIDElementGetReportSize(element)), logical=\(IOHIDElementGetLogicalMin(element))...\(IOHIDElementGetLogicalMax(element)), physical=\(IOHIDElementGetPhysicalMin(element))...\(IOHIDElementGetPhysicalMax(element)), unit=\(IOHIDElementGetUnit(element)), exponent=\(IOHIDElementGetUnitExponent(element))"
                }
            }
            onDevice?(details + descriptor)
            return
        }
    }

    private func poll() {
        guard let device else {
            if ProcessInfo.processInfo.systemUptime - lastDiscovery >= 2 { discover() }
            return
        }
        var bytes = [UInt8](repeating: 0, count: 8)
        var length = bytes.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length)
        guard result == kIOReturnSuccess, length >= 3, length <= bytes.count,
              let raw = LidReport.decode(Array(bytes.prefix(length))) else {
            failures += 1
            if failures >= 3 {
                reportError(String(format: "Lid sensor stopped returning valid readings (IOKit 0x%08x). Retrying…", result))
                currentAngle = nil
                disconnect()
            }
            return
        }
        failures = 0
        lastError = nil
        let angle = Double(raw)
        currentAngle = angle
        onReading?(LidReading(angle: angle, rawValue: raw, report: Array(bytes.prefix(length)),
                             timestamp: ProcessInfo.processInfo.systemUptime))
    }

    private func reportError(_ message: String) {
        guard message != lastError else { return }
        lastError = message
        onError?(message)
    }
}
