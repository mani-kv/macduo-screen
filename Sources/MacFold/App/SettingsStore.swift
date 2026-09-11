import Foundation
import FoldCore

final class SettingsStore {
    private let defaults = UserDefaults.standard
    var onChange: (() -> Void)?
    var configuration: FoldConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(configuration.validated()) {
                defaults.set(data, forKey: "foldConfiguration")
            }
            onChange?()
        }
    }

    init() {
        if let data = defaults.data(forKey: "foldConfiguration"),
           let stored = try? JSONDecoder().decode(FoldConfiguration.self, from: data) {
            configuration = stored.validated()
        } else {
            configuration = FoldConfiguration()
        }
    }

    func update(_ body: (inout FoldConfiguration) -> Void) {
        var value = configuration
        body(&value)
        configuration = value.validated()
    }
}
