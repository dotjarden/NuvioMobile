import Foundation

/// Keep transport diagnostics and request URLs out of the television interface.
nonisolated enum AuthErrorMessage {
    static func readable(_ message: String) -> String {
        let value = message.lowercased()
        if value.contains("invalid login") || value.contains("invalid_credentials") {
            return "The email or password is incorrect. Please try again."
        }
        if value.contains("email not confirmed") || value.contains("email_not_confirmed") {
            return "Confirm your email address, then try signing in again."
        }
        if value.contains("already registered") || value.contains("already exists") {
            return "An account already exists with this email. Choose Sign In instead."
        }
        if value.contains("password") && (value.contains("short") || value.contains("at least") || value.contains("weak")) {
            return "Choose a stronger password with at least six characters."
        }
        if value.contains("expired") { return "This sign-in code has expired. Try again to get a new code." }
        if value.contains("429") || value.contains("rate limit") || value.contains("too many") {
            return "Too many sign-in attempts. Please wait a moment before trying again."
        }
        if value.contains("nsurlerrordomain") || value.contains("connect") || value.contains("timeout") || value.contains("timed out") {
            return "Unable to reach the sign-in server. Check your connection and try again."
        }
        return "Sign-in could not be completed. Please try again."
    }
}
