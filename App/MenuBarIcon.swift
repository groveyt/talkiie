import AppKit
import ImageIO

enum MenuBarState: Equatable {
    case idle
    case recording
    case processing
}

struct MenuBarCarousel {
    let frames: [NSImage]
    let durations: [Double]

    static func load(directory: URL, pointSize: NSSize) -> MenuBarCarousel? {
        guard let json = FileManager.default.contents(atPath: directory.appendingPathComponent("carousel.json").path),
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let entries = root["frames"] as? [[String: Any]], !entries.isEmpty
        else { return nil }
        var frames: [NSImage] = []
        var durations: [Double] = []
        frames.reserveCapacity(entries.count)
        durations.reserveCapacity(entries.count)
        for entry in entries {
            guard let file = entry["file"] as? String,
                  let seconds = entry["durationSeconds"] as? Double, seconds > 0,
                  let image = decode(directory.appendingPathComponent(file), pointSize: pointSize)
            else { return nil }
            frames.append(image)
            durations.append(seconds)
        }
        return MenuBarCarousel(frames: frames, durations: durations)
    }

    private static func decode(_ url: URL, pointSize: NSSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0,
                                                       [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg, size: pointSize)
        image.isTemplate = true
        return image
    }
}

@MainActor
final class MenuBarIcon: ObservableObject {
    static let shared = MenuBarIcon()
    static let pointSize = NSSize(width: 18, height: 18)

    @Published private(set) var state: MenuBarState = .idle
    @Published private(set) var image: NSImage

    let idle: NSImage
    let carousel: MenuBarCarousel?
    private(set) var frameIndex = 0
    private var timer: Timer?
    var reduceMotion: () -> Bool = { Motion.reduceMotion }

    var isAnimating: Bool { timer != nil }

    private init() {
        let idle = NSImage(named: "MenuBarIdle")?.copy() as? NSImage
            ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "Talkiie")!
        idle.isTemplate = true
        idle.size = Self.pointSize
        idle.accessibilityDescription = "Talkiie"
        self.idle = idle
        image = idle
        carousel = Bundle.main.url(forResource: "carousel", withExtension: nil)
            .flatMap { MenuBarCarousel.load(directory: $0, pointSize: Self.pointSize) }
        Log.record(.menuBarCarousel(frames: carousel?.frames.count ?? 0))
    }

    func update(_ new: MenuBarState) {
        guard new != state else { return }
        state = new
        if new == .processing, let carousel, !reduceMotion() {
            start(carousel)
        } else {
            stop()
        }
    }

    private func start(_ carousel: MenuBarCarousel) {
        timer?.invalidate()
        frameIndex = 0
        image = carousel.frames[0]
        #if DEBUG
        debugStarts += 1
        #endif
        schedule(after: carousel.durations[0])
    }

    private func schedule(after seconds: Double) {
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func advance() {
        guard state == .processing, let carousel else { return stop() }
        frameIndex = (frameIndex + 1) % carousel.frames.count
        image = carousel.frames[frameIndex]
        schedule(after: carousel.durations[frameIndex])
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        frameIndex = 0
        if image !== idle { image = idle }
    }

    #if DEBUG
    private(set) var debugStarts = 0
    #endif
}
