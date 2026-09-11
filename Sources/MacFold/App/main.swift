import AppKit

let app = NSApplication.shared
if CommandLine.arguments.contains("--window-check") {
    do {
        try RenderDiagnostics.checkWindow()
        exit(0)
    } catch {
        fputs("Window check failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}
if let index = CommandLine.arguments.firstIndex(of: "--render-check"), CommandLine.arguments.count > index + 1 {
    do {
        try RenderDiagnostics.run(directory: CommandLine.arguments[index + 1])
        exit(0)
    } catch {
        fputs("Render check failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
