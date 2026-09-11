import Foundation
import LidSensor

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") {
    print("Usage: lid-angle [--seconds N]\nPolls the Apple lid sensor at 60 Hz. Prints report bytes, raw value, and degrees. Ctrl-C to stop.")
    exit(0)
}
var duration: Double?
if !arguments.isEmpty {
    guard arguments.count == 2, arguments[0] == "--seconds",
          let value = Double(arguments[1]), value.isFinite, value > 0 else {
        fputs("Usage: lid-angle [--seconds N]\n", stderr)
        exit(2)
    }
    duration = value
}
setbuf(stdout, nil)
let provider = HIDAngleProvider()
let start = ProcessInfo.processInfo.systemUptime
var count = 0
var low = Double.infinity
var high = -Double.infinity
provider.onDevice = { print("Sensor: \($0)\nConversion: report[1] | report[2] << 8, 1 count = 1 degree; valid range 0...360°.") }
provider.onError = { fputs("\($0)\n", stderr) }
provider.onReading = { reading in
    count += 1
    low = min(low, reading.angle)
    high = max(high, reading.angle)
    let bytes = reading.report.map { String(format: "%02X", $0) }.joined(separator: " ")
    print(String(format: "Lid angle: %5.1f° | raw: %3d | report: %@", reading.angle, reading.rawValue, bytes))
}
provider.start()
if let duration {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    provider.stop()
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    if count > 0 {
        print(String(format: "Read %d samples in %.2fs (%.1f Hz); observed %.1f...%.1f°. Hardware update rate may be lower than polling rate.", count, elapsed, Double(count) / elapsed, low, high))
    }
    exit(count > 0 ? 0 : 1)
}
RunLoop.main.run()
