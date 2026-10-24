#if DEBUG
import AppKit
import NaturalInputCore
import SwiftUI

@MainActor
enum WhatsNewSnapshots {
    static func run() async {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--whats-new-selftest"), i + 1 < args.count else {
            WhatsNewSnapshotsLine.emit(.usage); exit(2)
        }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let notes = WhatsNew.loadNotes(), let latest = notes.releases.first else { exit(61) }
        let view = WhatsNewView(releases: [latest], to: latest.version, from: nil, close: {})
        var shots = 0
        for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 540, height: 600)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                FileManager.default.createFile(atPath: dir.appendingPathComponent("whats-new-\(suffix).png").path, contents: png)
                shots += 1
            }
        }
        WhatsNewSnapshotsLine.emit(.saved(count: shots))
        exit(shots == 2 ? 0 : 1)
    }
}
#endif
