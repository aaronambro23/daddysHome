import SwiftUI
import DaddyCore

struct PokeCompanionWidget: View {
    @Environment(MockStore.self) private var store

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            if let state = store.pokeState, let active = state.active {
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        pokemonSprite(for: active.baseID)
                            .frame(height: 120)

                        VStack(spacing: 4) {
                            Text("ID #\(active.baseID)")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DaddyTheme.textMuted)

                            Text(pokemonName(for: active.baseID))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DaddyTheme.textPrimary)
                        }
                    }

                    GlassHairline()

                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Today's tokens")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DaddyTheme.textMuted)
                            Spacer()
                            Text("\(formatTokens(state.todayTokens))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DaddyTheme.textPrimary)
                        }

                        HStack(spacing: 8) {
                            Text("Progress")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DaddyTheme.textMuted)
                            Spacer()
                            Text("\(formatTokens(active.usedAtStage))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DaddyTheme.textPrimary)
                        }

                        ProgressView(value: min(Double(active.usedAtStage) / 2_500_000, 1.0))
                            .controlSize(.small)
                    }

                    GlassHairline()

                    HStack(spacing: 16) {
                        VStack(spacing: 4) {
                            Text("\(state.dex.count)")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(DaddyTheme.textPrimary)
                            Text("caught")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DaddyTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .insetSurface(cornerRadius: 10)

                        VStack(spacing: 4) {
                            Text("\(state.collectedFinals.count)")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(DaddyTheme.textPrimary)
                            Text("graduated")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DaddyTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .insetSurface(cornerRadius: 10)
                    }
                }
                .padding(16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "egg")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(DaddyTheme.textVeryDim)

                    VStack(spacing: 6) {
                        Text("PokeTokenBar not found")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DaddyTheme.textMuted)

                        Text("Launch PokeTokenBar to see your companion")
                            .font(.system(size: 10))
                            .foregroundStyle(DaddyTheme.textVeryDim)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DaddyTheme.popoverBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(DaddyTheme.insetStroke, lineWidth: 1)
        }
    }

    private func pokemonSprite(for id: Int) -> some View {
        let spritePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PokeTokenBar/sprites/\(id)-s.png")

        if FileManager.default.fileExists(atPath: spritePath.path),
           let image = NSImage(contentsOf: spritePath) {
            return AnyView(Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 100))
        } else {
            return AnyView(Image(systemName: "egg.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DaddyTheme.textVeryDim))
        }
    }

    private func pokemonName(for id: Int) -> String {
        let names: [Int: String] = [
            1: "Bulbasaur", 4: "Charmander", 7: "Squirtle",
            10: "Caterpie", 13: "Weedle", 16: "Pidgeot",
            19: "Rattata", 21: "Spearow", 23: "Ekans",
            27: "Sandshrew", 29: "Nidoran♀", 32: "Nidoran♂",
            35: "Clefairy", 37: "Vulpix", 39: "Jigglypuff",
            41: "Zubat", 43: "Oddish", 45: "Vileplume",
            47: "Paras", 50: "Diglett", 52: "Meowth",
            54: "Psyduck", 56: "Mankey", 58: "Growlithe",
            60: "Poliwag", 63: "Abra", 66: "Machop",
            69: "Bellsprout", 72: "Tentacool", 524: "Roggenrola",
        ]
        return names[id] ?? "Pokémon #\(id)"
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

#Preview {
    PokeCompanionWidget()
        .environment(MockStore())
        .padding(20)
}
