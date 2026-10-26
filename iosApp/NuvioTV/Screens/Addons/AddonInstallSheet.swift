import SwiftUI

/// What the install sheet's status modal shows. Derived from the hub's typed outcome, never from
/// the localized `statusMessage`.
nonisolated enum InstallPhase: Equatable {
    case idle
    case checking
    case installed(name: String)
    case failed(message: String)
}

/// Add-ons hub C, H3: the install sheet. The field and Install button stay; progress and the
/// result moved into a status modal that mirrors upstream's `NuvioStatusModal` (a dialog surface
/// with an optional busy indicator, a title, a message and one or two buttons; while busy it
/// cannot be dismissed). The sheet closes on Done, so the viewer reads the confirmation first.
///
/// Menu during Checking: `.onExitCommand` swallows it as best effort, but the sheet's own Menu
/// recogniser may still close the sheet (the repo saw this on a full-screen cover,
/// `MPVPlayerView.swift:820-845`). A mid-install close is therefore made harmless: the install
/// keeps running in the view model, a reopened sheet seeds `.checking` while it is still busy,
/// and the hub toasts and focuses the new card if the add-on lands while the sheet is closed.
/// DEBUG knob `-debug.installPrefillUrl <url>`: prefills the URL field on appear (typing into the
/// tvOS field from XCUITest is unreliable); used by `AddonsHubUITests.testInstallReorderPickerAndRemove`.
/// DEVICE CHECK OWED IN H5: press Menu during Checking on the box, with a slow stub install, and
/// confirm which of the two happens (swallowed, or closed and recovered).
struct AddonInstallSheet: View {
    @ObservedObject var model: AddonsViewModel
    @State private var newUrl = ""
    @State private var phase: InstallPhase = .idle
    /// Serial of the newest install outcome this sheet has handled (or that the hub handled
    /// before the sheet opened), so a stale outcome never shows on reopen.
    @State private var handledSerial: Int?
    @FocusState private var fieldFocused: Bool
    @Namespace private var focusNamespace
    @Environment(\.dismiss) private var dismiss

    init(model: AddonsViewModel, handledSerial: Int? = nil) {
        self.model = model
        _handledSerial = State(initialValue: handledSerial)
    }

    nonisolated static func serial(of outcome: AddonsViewModel.InstallOutcome) -> Int {
        switch outcome {
        case .installed(_, let serial), .failed(_, let serial): return serial
        }
    }

    /// The repository's failure text already opens with "Couldn't install: " (box, 2026-10-26:
    /// the modal read it twice under its own title); the modal shows only the reason.
    nonisolated static func reason(_ message: String) -> String {
        let prefix = "Couldn't install: "
        return message.hasPrefix(prefix) ? String(message.dropFirst(prefix.count)) : message
    }

    /// The pure phase rule behind `.onChange`: busy wins, then the typed outcome, else idle.
    nonisolated static func installPhase(isInstalling: Bool, outcome: AddonsViewModel.InstallOutcome?) -> InstallPhase {
        if isInstalling { return .checking }
        switch outcome {
        case .installed(let name, _)?: return .installed(name: name)
        case .failed(let message, _)?: return .failed(message: Self.reason(message))
        case nil: return .idle
        }
    }

    var body: some View {
        form
            .disabled(phase != .idle)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .focusScope(focusNamespace)
            .overlay {
                if phase != .idle {
                    StatusModal(
                        phase: phase,
                        onDone: { dismiss() },
                        onRetry: returnToField,
                        onCancel: returnToField
                    )
                }
            }
            .onAppear {
                fieldFocused = true
                seedPhase()
                #if DEBUG
                // `-debug.installPrefillUrl <url>` prefills the field (never persisted, never
                // written back); used by `AddonsHubUITests.testInstallReorderPickerAndRemove`.
                if newUrl.isEmpty, let prefill = UserDefaults.standard.string(forKey: "debug.installPrefillUrl"), !prefill.isEmpty {
                    newUrl = prefill
                }
                #endif
            }
            .onChange(of: model.isInstalling) { _, installing in
                if installing { phase = Self.installPhase(isInstalling: true, outcome: model.installOutcome) }
            }
            .onChange(of: model.installOutcome) { _, outcome in
                if let outcome { handledSerial = Self.serial(of: outcome) }
                phase = Self.installPhase(isInstalling: model.isInstalling, outcome: outcome)
                // The typed URL survives a failure; it clears only once the add-on is in.
                if case .installed? = outcome { newUrl = "" }
            }
            .onExitCommand {
                switch phase {
                case .idle, .installed: dismiss()
                case .checking: break
                case .failed: returnToField()
                }
            }
    }

    /// A sheet opened (or reopened) mid-install shows Checking; an outcome shows only when it is
    /// newer than the last one handled.
    private func seedPhase() {
        if model.isInstalling {
            phase = .checking
        } else if let outcome = model.installOutcome, Self.serial(of: outcome) > (handledSerial ?? Int.min) {
            handledSerial = Self.serial(of: outcome)
            phase = Self.installPhase(isInstalling: false, outcome: outcome)
        }
    }

    private func returnToField() {
        phase = .idle
        DispatchQueue.main.async { fieldFocused = true }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Install add-on").font(Theme.Font.screenTitle)
            Text("Paste the manifest URL from your streaming addon's config page (e.g. your TorBox or Torrentio URL with your API key). It ends in /manifest.json.")
                .font(Theme.Font.body).foregroundStyle(.secondary)
                .frame(maxWidth: 1200, alignment: .leading)

            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("https://\u{2026}/manifest.json", text: $newUrl)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.screenTitle.weight(.regular))
                    .focused($fieldFocused)
                    .prefersDefaultFocus(true, in: focusNamespace)
                    .accessibilityIdentifier("addons_hub_install_field")
            }
            .padding(Theme.Spacing.lg)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card))

            HStack(spacing: Theme.Spacing.lg) {
                // Not `.disabled` while installing: that disabled the button the user had just
                // pressed and focus jumped away. Guarded in the action instead.
                Button {
                    guard !model.isInstalling else { return }
                    model.install(newUrl)
                } label: {
                    Label("Install", systemImage: "plus.circle.fill")
                        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.xxs)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("addons_hub_install_button")

                #if DEBUG
                if DebugConfig.hasManifestURL {
                    Button {
                        guard !model.isInstalling else { return }
                        model.install(DebugConfig.manifestURL)
                    } label: {
                        Label("Quick install (from DebugConfig)", systemImage: "wrench.and.screwdriver")
                            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.xxs)
                    }
                    .buttonStyle(.chip)
                }
                #endif
            }
        }
        .padding(Theme.Spacing.screen)
        .focusSection()
    }
}

/// Dimmed scrim plus a card: a busy indicator while checking, then a glyph, title, message and
/// the confirm (and, on failure, dismiss) buttons.
private struct StatusModal: View {
    let phase: InstallPhase
    /// The modal's own scope, apart from the form's, for Done / Try again's default focus.
    @Namespace private var focusNamespace
    /// Where focus sits inside the modal. The form keeps the engine's focus when it is disabled
    /// underneath an overlay (observed on the FA87 sim: Install stayed focused after Installed),
    /// so the modal moves focus itself on appear and on every phase change.
    private enum Target: Hashable { case card, done, retry, cancel }
    @FocusState private var focus: Target?
    let onDone: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            card
        }
        // Default focus for the engine's own update (the card stops being focusable when
        // Checking ends, which empties focus on the FA87 sim), plus explicit requests at 50 ms,
        // 350 ms and 1.25 s after the phase change: a request made in the same pass as the
        // button's insertion is dropped. The requests stop as soon as anything in the modal holds
        // focus, so a user who has already moved to Cancel is not pulled back.
        .defaultFocus($focus, Self.target(for: phase))
        .task(id: phase) {
            let target = Self.target(for: phase)
            for delay in [0.05, 0.3, 0.9] {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled || focus != nil { return }
                focus = target
            }
        }
    }

    private nonisolated static func target(for phase: InstallPhase) -> Target? {
        switch phase {
        case .idle: return nil
        case .checking: return .card
        case .installed: return .done
        case .failed: return .retry
        }
    }

    private var title: String {
        switch phase {
        case .idle: return ""
        case .checking: return String(localized: "Checking the add-on\u{2026}")
        case .installed(let name): return String(localized: "Installed \(name).")
        case .failed: return String(localized: "Couldn't install that add-on.")
        }
    }

    /// `.focusable(false)` on the card would make its buttons unreachable too (the FA87 sim kept
    /// focus on the disabled Install button, then on nothing), so the modifier is only applied
    /// while Checking, when the card itself must hold focus.
    @ViewBuilder private var card: some View {
        if phase == .checking {
            cardBody.focusable().focused($focus, equals: .card)
        } else {
            cardBody
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            switch phase {
            case .idle:
                EmptyView()
            case .checking:
                ProgressView()
                Text(title).font(Theme.Font.sectionTitle)
                Text("Fetching its manifest.").font(Theme.Font.body).foregroundStyle(.secondary)
            case .installed:
                Image(systemName: "checkmark.circle.fill")
                    .font(Theme.Font.screenTitle).foregroundStyle(Theme.Palette.accent)
                Text(title).font(Theme.Font.sectionTitle)
                Text("It is on and will answer the next search for streams.")
                    .font(Theme.Font.body).foregroundStyle(.secondary)
                HStack(spacing: Theme.Spacing.lg) {
                    Button(action: onDone) {
                        Text("Done").padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.xxs)
                    }
                    .buttonStyle(.borderedProminent)
                    .focused($focus, equals: .done)
                    .prefersDefaultFocus(true, in: focusNamespace)
                    .accessibilityIdentifier("addons_hub_install_done")
                }
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Font.screenTitle).foregroundStyle(Theme.Palette.error)
                Text(title).font(Theme.Font.sectionTitle)
                Text(message).font(Theme.Font.body).foregroundStyle(.secondary).lineLimit(4)
                HStack(spacing: Theme.Spacing.lg) {
                    Button(action: onRetry) {
                        Text("Try again").padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.xxs)
                    }
                    .buttonStyle(.borderedProminent)
                    .focused($focus, equals: .retry)
                    .prefersDefaultFocus(true, in: focusNamespace)
                    .accessibilityIdentifier("addons_hub_install_retry")
                    Button(action: onCancel) {
                        Text("Cancel").padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.xxs)
                    }
                    .buttonStyle(.bordered)
                    .focused($focus, equals: .cancel)
                    .accessibilityIdentifier("addons_hub_install_cancel")
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 720, alignment: .leading)
        .background(Theme.Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.hero))
        // While checking there is no button: the card itself holds focus (see `card`) so Menu
        // reaches the sheet's `.onExitCommand` (which swallows it) instead of closing the sheet.
        .focusScope(focusNamespace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("addons_hub_install_modal")
    }
}
