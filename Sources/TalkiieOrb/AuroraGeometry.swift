public struct AuroraPalette: Equatable, Sendable {
    private let variant: Int

    public static let warm = AuroraPalette(variant: 0)
    public static let cool = AuroraPalette(variant: 1)
}
