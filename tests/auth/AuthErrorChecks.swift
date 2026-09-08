import Foundation

@main struct AuthErrorChecks {
    static func main() {
        let raw = "HTTP request to https://localhost/auth/v1/signup failed: NSURLErrorDomain Code=-1004"
        let clean = AuthErrorMessage.readable(raw)
        precondition(clean.contains("Check your connection"))
        precondition(!clean.contains("localhost") && !clean.contains("NSURLError"))
        precondition(AuthErrorMessage.readable("Invalid login credentials").contains("email or password"))
        precondition(AuthErrorMessage.readable("Email not confirmed").contains("Confirm your email"))
        precondition(AuthErrorMessage.readable("Request failed with HTTP 429").contains("wait"))
        precondition(AuthErrorMessage.readable("unexpected secret request body").contains("could not be completed"))
        print("PASS: 6 authentication error checks")
    }
}
