import Foundation

public enum OnboardingPlan {
    public static let currentVersion = 1

    public enum Keys {
        public static let completedVersion = "onboarding.completedVersion"
        public static let completedAt = "onboarding.completedAt"
        public static let audience = "onboarding.audience"
        public static let lastStep = "onboarding.lastStep"
    }

    public enum Audience: Int, Sendable, Equatable {
        case fullTour = 1
        case featuresOnly = 2
    }

    public enum Step: Int, CaseIterable, Sendable, Equatable {
        case permissions = 1
        case model = 2
        case start = 4
        case features = 5
    }

    public static func steps(audience: Audience, hasModelStep: Bool) -> [Step] {
        switch audience {
        case .featuresOnly: return [.features]
        case .fullTour: return [.permissions] + (hasModelStep ? [.model] : []) + [.start, .features]
        }
    }

    public static func mayOpen(allowsCapture: Bool) -> Bool { allowsCapture }

    public static func audience(consentedBeforeThisLaunch: Bool, hasSuccessfulInsertions: Bool) -> Audience {
        (consentedBeforeThisLaunch || hasSuccessfulInsertions) ? .featuresOnly : .fullTour
    }

    public struct State: Equatable, Sendable {
        public var completedVersion: Int?
        public var audience: Audience?
        public var lastStep: Step?

        public init(completedVersion: Int? = nil, audience: Audience? = nil, lastStep: Step? = nil) {
            self.completedVersion = completedVersion
            self.audience = audience
            self.lastStep = lastStep
        }

        public var isCompleted: Bool { (completedVersion ?? 0) >= OnboardingPlan.currentVersion }
    }

    public enum Presentation: Equatable, Sendable {
        case none
        case window
        case menuOnly
    }

    public static func presentation(state: State, allowsCapture: Bool) -> Presentation {
        guard mayOpen(allowsCapture: allowsCapture), !state.isCompleted, let audience = state.audience else { return .none }
        switch audience {
        case .featuresOnly: return .window
        case .fullTour: return state.lastStep == nil ? .window : .menuOnly
        }
    }

    public static func menuProgress(state: State, allowsCapture: Bool, hasModelStep: Bool) -> (step: Int, of: Int)? {
        guard mayOpen(allowsCapture: allowsCapture), !state.isCompleted, state.audience == .fullTour,
              let last = state.lastStep else { return nil }
        let all = steps(audience: .fullTour, hasModelStep: hasModelStep)
        guard let i = all.firstIndex(of: last) else { return nil }
        return (i + 1, all.count)
    }

    public static func completed(_ state: State) -> State {
        var next = state
        next.completedVersion = currentVersion
        return next
    }

    public static func moved(_ state: State, to step: Step) -> State {
        var next = state
        next.lastStep = step
        return next
    }
}
