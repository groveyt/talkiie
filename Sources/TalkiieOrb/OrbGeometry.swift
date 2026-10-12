import Foundation

/// 兩個模式共用同一條帶子：Thinking Orbs（© 2026 Jakub Antalik，MIT，見 `THIRD_PARTY_NOTICES.md`）
public struct OrbDot: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var r: Double
    public var white: Double
    public var alpha: Double
}

public enum OrbGeometry {
    public enum Mode: Equatable, Sendable {
        case listening(level: Double)
        case transcribing
    }

    public static let staticTime = 0.6

    enum Ribbon {
        static let nativeSize = 64.0
        static let speed = 2.34
        static let lanes = 3, segs = 44, ghostN = 38
        static let rBase = 0.935, rDepth = 1.445
        static let spin = 0.0, bandMul = 3.9, wobMul = 1.0
        static let voiceWob = 0.9, voiceWiden = 0.4, voiceSwell = 0.25
        static let scanRate = 2.4, scanWidth = 0.12, scanDim = 0.5
    }

    static let rsPow = 0.6, rMin = 0.3

    public static func frame(_ mode: Mode, size: Double, time: Double) -> [OrbDot] {
        let n = Ribbon.nativeSize, k = size / n
        let dots: [OrbDot]
        switch mode {
        case .listening(let level):
            dots = ribbon(size: n, t: time * Ribbon.speed, voice: voiceShape(level: level), scan: nil)
        case .transcribing:
            let t = time * Ribbon.speed
            dots = ribbon(size: n, t: t, voice: voiceShape(level: 0), scan: t * Ribbon.scanRate)
        }
        return finalize(dots).map {
            var d = $0
            d.x *= k; d.y *= k; d.r *= k
            return d
        }
    }

    public struct VoiceShape: Equatable, Sendable {
        public var wob: Double
        public var widen: Double
        public var swell: Double
    }

    public static func voiceShape(level: Double) -> VoiceShape {
        let l = level.isFinite ? min(1, max(0, level)) : 0
        return VoiceShape(wob: 1 + Ribbon.voiceWob * l, widen: 1 + Ribbon.voiceWiden * l, swell: 1 + Ribbon.voiceSwell * l)
    }

    static func ribbon(size: Double, t: Double, voice: VoiceShape, scan: Double?) -> [OrbDot] {
        let c = size / 2
        let R = c * 0.78
        let camTilt = 0.3
        let proj = projector(yaw: t * 0.1 * Ribbon.spin, tilt: camTilt, cx: c, cy: c, scale: 1)
        let rs = radiusScale(size)
        var dots: [OrbDot] = []

        for i in 0..<Ribbon.ghostN {
            let d = fibDir(i, Ribbon.ghostN)
            let p = proj(d.x * R, d.y * R, d.z * R)
            let depth = (p.z / R + 1) / 2
            dots.append(OrbDot(x: p.x, y: p.y, z: p.z, r: 0.8 * rs, white: 0.78, alpha: 0.1 + 0.22 * depth))
        }

        let ya = t * 0.24 * Ribbon.spin
        let ta = 0.55 + 0.3 * sin(t * 0.18) * Ribbon.spin
        let ux = cos(ya), uy = 0.0, uz = sin(ya)
        let vx = -uz * sin(ta), vy = cos(ta), vz = ux * sin(ta)
        let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx

        let lanes = max(1, Int((Double(Ribbon.lanes) * Ribbon.bandMul).rounded()))
        let mid = Double(lanes - 1) / 2
        for w in 0..<lanes {
            let side = Double(w) - mid
            let laneOff = side * 0.075 * (side > 0 ? voice.widen : 1)
            let edge = abs(side) / max(1, mid)
            for k in 0..<Ribbon.segs {
                let a = Double(k) / Double(Ribbon.segs) * 2 * .pi
                let wob = (0.16 * sin(a * 3 - t * 1.7 + Double(w) * 0.22) + 0.07 * sin(a * 5 + t * 1.1))
                    * Ribbon.wobMul * voice.wob
                let off = laneOff + wob
                let x = ux * cos(a) + vx * sin(a) + nx * off
                let y = uy * cos(a) + vy * sin(a) + ny * off
                let z = uz * cos(a) + vz * sin(a) + nz * off
                let l = (x * x + y * y + z * z).squareRoot()
                let p = proj(x / l * R, y / l * R, z / l * R)
                let depth = (p.z / R + 1) / 2
                let glow = scan.map { s -> Double in
                    let d1 = angleDelta(a, s), d2 = angleDelta(a, s + .pi)
                    return exp(-min(d1 * d1, d2 * d2) / Ribbon.scanWidth)
                } ?? 0
                let dim = scan == nil ? 1 : Ribbon.scanDim + (1 - Ribbon.scanDim) * glow
                dots.append(OrbDot(
                    x: p.x, y: p.y, z: p.z,
                    r: (Ribbon.rBase + Ribbon.rDepth * depth) * (1 - 0.25 * edge) * rs * voice.swell * (1 + 0.8 * glow),
                    white: 0.52 - 0.44 * depth + 0.18 * edge - 0.3 * glow,
                    alpha: (0.4 + 0.6 * depth) * dim))
            }
        }
        return dots
    }

    static func projector(yaw: Double, tilt: Double, cx: Double, cy: Double, scale: Double)
        -> (Double, Double, Double) -> (x: Double, y: Double, z: Double)
    {
        let st = sin(tilt), ct = cos(tilt), sy = sin(yaw), cyw = cos(yaw)
        return { x, y, z in
            let x1 = x * cyw + z * sy
            let z1 = -x * sy + z * cyw
            let y1 = y * ct - z1 * st
            let z2 = y * st + z1 * ct
            return (cx + x1 * scale, cy - y1 * scale, z2)
        }
    }

    static func radiusScale(_ size: Double) -> Double { pow(size / 300, rsPow) }

    static func angleDelta(_ a: Double, _ b: Double) -> Double { atan2(sin(a - b), cos(a - b)) }

    static func fibDir(_ i: Int, _ n: Int) -> (x: Double, y: Double, z: Double) {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let y = 1 - 2 * (Double(i) + 0.5) / Double(n)
        let rad = (1 - y * y).squareRoot()
        let a = Double(i) * golden
        return (rad * cos(a), y, rad * sin(a))
    }

    static func finalize(_ dots: [OrbDot]) -> [OrbDot] {
        dots.filter { $0.alpha >= 0.02 }
            .map { var d = $0; d.r = max(rMin, d.r); return d }
            .sorted { $0.z < $1.z }
    }
}
