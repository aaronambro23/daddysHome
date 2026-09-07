import Foundation

/// What an agent is allowed to build, and what it must leave to the human.
///
/// Orthogonal to `WorkMode` on purpose: a Debug session and a Plan & Build
/// session raise the same question of who runs the build, so folding this into
/// the mode would mean four modes times four policies of prose.
///
/// The line that matters is *compile* versus *run*. Compiling is cheap, has no
/// side effects and catches the agent's own mistakes before they reach anyone.
/// Running — `swift run`, `bun dev`, `flutter run`, a localhost server, opening
/// a built `.app` — takes over the machine, competes with the instance the
/// human already has going, and produces logs they wanted to watch themselves.
public enum BuildPolicy: String, Codable, Sendable, CaseIterable {
    /// Nothing. Not even a typecheck. Report what changed and hand over the
    /// command to run.
    case frozen

    /// Compile, typecheck and test to prove the code builds — but never run,
    /// serve or launch anything, and ask before a release build.
    case compile

    /// Compiling, plus running the app or a dev server locally when that is
    /// what actually verifies the change.
    case run

    /// Anything, including release builds and packaging.
    case free

    /// The policy a session starts in when nothing else says otherwise.
    ///
    /// Compile, because an agent that cannot check its own work ships errors
    /// to the human instead of catching them — and compiling is the half with
    /// no side effects.
    public static let `default`: BuildPolicy = .compile

    public var displayName: String {
        switch self {
        case .frozen: return "Frozen"
        case .compile: return "Compile"
        case .run: return "Run"
        case .free: return "Free"
        }
    }

    /// Uppercase and short, for controls that put four of these side by side.
    public var shortName: String {
        switch self {
        case .frozen: return "FROZEN"
        case .compile: return "COMPILE"
        case .run: return "RUN"
        case .free: return "FREE"
        }
    }

    public var iconName: String {
        switch self {
        case .frozen: return "snowflake"
        case .compile: return "hammer.fill"
        case .run: return "play.fill"
        case .free: return "infinity"
        }
    }

    public var summary: String {
        switch self {
        case .frozen: return "No builds at all. You run everything."
        case .compile: return "Compiles and tests. Never runs or serves."
        case .run: return "Compiles, and may run the app locally."
        case .free: return "Anything, including release builds."
        }
    }

    /// The slash command that selects this policy from a session's own input.
    ///
    /// `/run` is taken by a built-in skill, hence `/allowrun`.
    public var slashCommand: String {
        switch self {
        case .frozen: return "/frozen"
        case .compile: return "/compile"
        case .run: return "/allowrun"
        case .free: return "/freebuild"
        }
    }

    /// What gets injected into the agent's system prompt at launch.
    ///
    /// Same reasoning as `WorkMode.systemPrompt`: name the policy, let
    /// `AGENTS.md` carry the definition. Every one of these CLIs reads it.
    public var systemPrompt: String? {
        switch self {
        case .compile:
            // The contract's own default. Repeating it here would only spend
            // tokens saying what the file already says.
            return nil
        case .frozen:
            return """
                BUILD POLICY: FROZEN. Run no builds of any kind — no compile, \
                no typecheck, no tests, no run, no release. Make the changes, \
                say plainly that they are unverified, and give me the exact \
                command to run myself.
                """
        case .run:
            return """
                BUILD POLICY: RUN. You may compile, test, and run the app or a \
                dev server locally when that is what verifies the change. Ask \
                before a release build or packaging step.
                """
        case .free:
            return """
                BUILD POLICY: FREE. You may compile, test, run, serve, and \
                produce release builds without asking.
                """
        }
    }

    /// Sent into a running session to change its policy without a restart.
    public var switchInstruction: String {
        switch self {
        case .frozen:
            return "Switch to BUILD POLICY: FROZEN for the rest of this session: "
                + "run no builds at all — no compile, no tests, no run, no release. "
                + "Say plainly when something is unverified and hand me the command."
        case .compile:
            return "Switch to BUILD POLICY: COMPILE for the rest of this session: "
                + "compile, typecheck and test to prove the code builds, but never "
                + "run, serve or launch anything, and ask before a release build."
        case .run:
            return "Switch to BUILD POLICY: RUN for the rest of this session: "
                + "compile and test freely, and run the app or a dev server locally "
                + "when that is what verifies the change. Ask before a release build."
        case .free:
            return "Switch to BUILD POLICY: FREE for the rest of this session: "
                + "compile, test, run, serve and produce release builds without asking."
        }
    }
}
