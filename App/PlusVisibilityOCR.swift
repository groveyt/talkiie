#if DEBUG
import AppKit
import Vision

@MainActor
enum PlusVisibilityOCR {
    static func texts(in view: NSView) -> [String] {
        var targets: [NSView] = [view]
        if let doc = scrollDocument(in: view) { targets.append(doc) }
        var out: [String] = []
        for target in targets {
            guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { continue }
            target.cacheDisplay(in: target.bounds, to: rep)
            guard let cg = rep.cgImage else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hant", "en-US"]
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: cg).perform([request])
            for obs in request.results ?? [] {
                if let s = obs.topCandidates(1).first?.string { out.append(s) }
            }
        }
        return out
    }

    private static func scrollDocument(in view: NSView) -> NSView? {
        if let s = view as? NSScrollView { return s.documentView }
        for sub in view.subviews { if let d = scrollDocument(in: sub) { return d } }
        return nil
    }
}
#endif
