import AulaCore
import Foundation

/// Everything AULA Studio remembers, saved as JSON in Application Support.
struct StoreData: Codable {
    var profiles: [Profile] = []
    /// Active profile per keyboard.
    var active: [String: UUID] = [:]
    var selectedModel: KeyboardModel = .f75Pro
    /// What was last written to each S75 Pro profile's keyboard, to know what changed.
    var lastApplied: [UUID: Profile] = [:]
    var simulateS75 = false

    static func fresh() -> StoreData {
        var d = StoreData()
        for model in KeyboardModel.allCases {
            let p = Profile(name: "Default", model: model)
            d.profiles.append(p)
            d.active[model.rawValue] = p.id
        }
        return d
    }
}

enum ProfileStore {
    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AULA Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profiles.json")
    }

    static func load() -> StoreData {
        guard let data = try? Data(contentsOf: fileURL),
              var store = try? JSONDecoder().decode(StoreData.self, from: data) else { return .fresh() }
        // Every keyboard needs at least one profile and an active one.
        for model in KeyboardModel.allCases {
            if !store.profiles.contains(where: { $0.model == model }) {
                store.profiles.append(Profile(name: "Default", model: model))
            }
            let ids = store.profiles.filter { $0.model == model }.map(\.id)
            if store.active[model.rawValue].map({ !ids.contains($0) }) ?? true { store.active[model.rawValue] = ids[0] }
        }
        return store
    }

    static func save(_ store: StoreData) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Import / export

    static func export(_ profile: Profile, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: url, options: .atomic)
    }

    static func importProfile(from url: URL) throws -> Profile {
        var p = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: url))
        p.id = UUID()
        return p
    }
}
