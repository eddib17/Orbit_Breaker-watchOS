public struct WorldInfo: Equatable, Sendable {
    public let number: Int
    public let name: String
    public let tagline: String
}

/// The six worlds of the campaign; each has 10 levels and ends with a boss.
public enum Worlds {
    public static let levelsPerWorld = 10

    public static let all: [WorldInfo] = [
        WorldInfo(number: 1, name: "First Light", tagline: "Learn the ropes"),
        WorldInfo(number: 2, name: "Orbit", tagline: "Spinning rings"),
        WorldInfo(number: 3, name: "Iron", tagline: "Armor and explosives"),
        WorldInfo(number: 4, name: "Flux", tagline: "Warps and gravity"),
        WorldInfo(number: 5, name: "Eclipse", tagline: "Feel what you can't see"),
        WorldInfo(number: 6, name: "Singularity", tagline: "Everything at once"),
    ]

    public static func of(levelId: Int) -> WorldInfo {
        all[((levelId - 1) / levelsPerWorld).clamped(0, all.count - 1)]
    }
}
