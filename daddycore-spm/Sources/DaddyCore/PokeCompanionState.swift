import Foundation

public struct PokeCompanionState: Codable, Equatable, Sendable {
    public let activeID: Int
    public let dex: [Int]
    public let collectedFinals: [Int]
    public let spentTokens: Int
    public let inventory: [String: Int]
    public let todayTokens: Int
    public let language: String
    public let lastDate: String
    public let active: ActivePokemon?

    enum CodingKeys: String, CodingKey {
        case active
        case dex
        case collectedFinals
        case spentTokens
        case inventory
        case lastDate
        case language
        case claimedTodayTokensByProvider
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dex = try container.decode([Int].self, forKey: .dex)
        self.collectedFinals = try container.decode([Int].self, forKey: .collectedFinals)
        self.spentTokens = try container.decode(Int.self, forKey: .spentTokens)
        self.inventory = try container.decode([String: Int].self, forKey: .inventory)
        self.language = try container.decode(String.self, forKey: .language)
        self.lastDate = try container.decode(String.self, forKey: .lastDate)
        self.active = try container.decodeIfPresent(ActivePokemon.self, forKey: .active)
        self.activeID = self.active?.baseID ?? 0

        var todayTotal = 0
        if let providers = try container.decodeIfPresent([String: Int].self, forKey: .claimedTodayTokensByProvider) {
            todayTotal = providers.values.reduce(0, +)
        }
        self.todayTokens = todayTotal
    }

    public init(
        activeID: Int,
        dex: [Int],
        collectedFinals: [Int],
        spentTokens: Int,
        inventory: [String: Int],
        todayTokens: Int,
        language: String,
        lastDate: String,
        active: ActivePokemon?
    ) {
        self.activeID = activeID
        self.dex = dex
        self.collectedFinals = collectedFinals
        self.spentTokens = spentTokens
        self.inventory = inventory
        self.todayTokens = todayTokens
        self.language = language
        self.lastDate = lastDate
        self.active = active
    }
}

public struct ActivePokemon: Codable, Equatable, Sendable {
    public let baseID: Int
    public let usedAtStage: Int
    public let nature: String
    public let rarity: String
    public let isShiny: Bool
    public let stageIndex: Int
}

extension PokeCompanionState {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(active, forKey: .active)
        try container.encode(dex, forKey: .dex)
        try container.encode(collectedFinals, forKey: .collectedFinals)
        try container.encode(spentTokens, forKey: .spentTokens)
        try container.encode(inventory, forKey: .inventory)
        try container.encode(lastDate, forKey: .lastDate)
        try container.encode(language, forKey: .language)
    }
}
