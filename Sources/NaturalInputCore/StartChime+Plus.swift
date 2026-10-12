import Foundation

extension StartChime.Preset {
    var plusTitle: String { rawValue }
}

extension StartChime {
    static func plusNotes(_ preset: Preset) -> [Note] {
        notes(defaultPreset)
    }
}
