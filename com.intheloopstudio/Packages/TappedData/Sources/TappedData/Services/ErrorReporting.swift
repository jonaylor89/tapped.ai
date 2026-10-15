import Foundation
@preconcurrency import PostHog

/// Non-fatal errors go to PostHog error tracking; crashes are autocaptured (`PostHogAnalytics.configure`).
/// A no-op until PostHog is configured, so mock and local-stack runs report nothing.
public enum ErrorReporting {
    public static func record(error: any Error) {
        PostHogSDK.shared.captureException(error)
    }
}
