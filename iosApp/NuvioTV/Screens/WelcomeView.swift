import SwiftUI

/// Phone approval is the primary TV sign-in route; every supported account path stays available.
struct WelcomeView: View {
    @ObservedObject var model: AuthViewModel
    @StateObject private var server = ActiveServerObserver()
    private enum AuthSheet: String, Identifiable {
        case signIn, signUp, qr, server
        var id: String { rawValue }
    }
    @State private var sheet: AuthSheet?
    @Namespace private var focusNamespace

    var body: some View {
        ZStack {
            AccountBackdrop()
            HStack(spacing: 150) {
                VStack(alignment: .leading, spacing: 30) {
                    Image("LogoMark").resizable().scaledToFit().frame(width: 180, height: 130)
                        .accessibilityLabel("Nuvio")
                    Text("Your next watch.\nRight where you left off.")
                        .font(.system(size: 58, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text("Your library, profiles and watch progress, together on every Nuvio device.")
                        .font(.title3).foregroundStyle(.secondary)
                }.frame(width: 680, alignment: .leading)
                VStack(alignment: .leading, spacing: 30) {
                    Text("Welcome to Nuvio").font(.largeTitle.bold())
                    if server.isCustom { Text(server.displayHost).font(.callout).foregroundStyle(.secondary) }
                    GlassEffectContainer(spacing: 24) {
                        VStack(alignment: .leading, spacing: 24) {
                            if server.supportsTvLogin {
                                Button { open(.qr) } label: {
                                    Label("Sign In with Your Phone", systemImage: "qrcode")
                                        .frame(width: 490, alignment: .leading)
                                }.buttonStyle(.glassProminent).prefersDefaultFocus(true, in: focusNamespace)
                            }
                            if server.supportsEmailPassword {
                                Button { open(.signIn) } label: {
                                    Label("Sign In with Email", systemImage: "envelope")
                                        .frame(width: 490, alignment: .leading)
                                }.buttonStyle(.glass).prefersDefaultFocus(!server.supportsTvLogin, in: focusNamespace)
                                Button("Create Account") { open(.signUp) }.buttonStyle(.glass)
                            }
                            Button("Continue as Guest") { model.continueAsGuest() }
                                .buttonStyle(.glass).disabled(model.isBusy)
                        }
                    }.focusScope(focusNamespace)
                    Button(server.isCustom ? "Change Server" : "Connect to a Server") { open(.server) }
                        .buttonStyle(.borderless).font(.callout)
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(width: 560, alignment: .leading)
            }.padding(80)
        }
        .fullScreenCover(item: $sheet) { mode in
            switch mode {
            case .signIn: AuthView(model: model, isSignUp: false)
            case .signUp: AuthView(model: model, isSignUp: true)
            case .qr: QrSignInView()
            case .server: ServerConnectionView()
            }
        }
    }
    private func open(_ mode: AuthSheet) { model.clearError(); sheet = mode }
}

/// A quiet opaque base keeps native glass controls and account text readable.
struct AccountBackdrop: View {
    var body: some View {
        ZStack {
            Theme.Palette.background
            RadialGradient(colors: [Theme.Palette.accent.opacity(0.18), .clear],
                           center: .topLeading, startRadius: 30, endRadius: 1200)
        }.ignoresSafeArea()
    }
}
