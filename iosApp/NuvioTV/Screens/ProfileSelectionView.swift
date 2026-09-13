import SwiftUI
import SharedCore

/// Profile avatar: renders the cloud avatar image (custom `avatarUrl` or catalog `avatarId`,
/// resolved via the shared `profileAvatarImageUrl`) when available, otherwise the colored circle
/// with the profile's initial (guest-mode / pre-cloud behavior).
struct ProfileAvatar: View {
    let profile: NuvioProfile
    var size: CGFloat = 170
    /// The avatar catalog (for `avatarId` lookups). Empty is fine — falls back to color+initial.
    var avatars: [AvatarCatalogItem] = []

    var body: some View {
        ZStack {
            if let url = imageUrl {
                CachedAsyncImage(string: url)
                    .clipShape(Circle())
            } else {
                Circle().fill(Color(hexString: profile.avatarColorHex) ?? Theme.Palette.accent)
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }

    private var imageUrl: String? {
        let catalogItem = avatars.first { $0.id == profile.avatarId }
        return ProfileModelsKt.profileAvatarImageUrl(profile: profile, avatar: catalogItem)
    }

    private var initial: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }
}

/// The launch gate keeps profile selection separate from explicit profile management.
/// Account repositories and PIN checks remain the authority for every action.
struct ProfileSelectionView: View {
    @ObservedObject var model: ProfilesViewModel
    var onSelected: () -> Void

    @State private var editing: ProfileEditTarget?
    @State private var managing = false
    @State private var pinPrompt: PinPrompt?
    @Namespace private var defaultFocusNamespace
    @FocusState private var focusedProfile: Int32?
    @State private var didSeedDefaultFocus = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedColor: Color {
        let profile = model.profiles.first { $0.profileIndex == focusedProfile } ?? model.activeProfile
        return profile.flatMap { Color(hexString: $0.avatarColorHex) } ?? Theme.Palette.accent
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            RadialGradient(colors: [selectedColor.opacity(0.24), .clear],
                           center: UnitPoint(x: 0.5, y: 0.46), startRadius: 60, endRadius: 850)
                .ignoresSafeArea()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: focusedProfile)

            VStack {
                HStack {
                    HStack(spacing: 14) {
                        Image("LogoMark").resizable().scaledToFit().frame(width: 48, height: 38)
                        Text("Nuvio").font(.system(size: 30, weight: .semibold))
                    }.accessibilityElement(children: .combine)
                    Spacer()
                    Label(model.isCloudAccount ? "Nuvio account" : "Guest",
                          systemImage: model.isCloudAccount ? "person.crop.circle" : "appletv")
                        .font(.system(size: 22)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 90).padding(.vertical, 60)

            VStack(spacing: 64) {
                Text(managing ? "Manage Profiles" : "Who’s watching?")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("profiles.heading")

                // Six fixed-width portraits fit without clipping the native focus lift.
                HStack(alignment: .top, spacing: 36) {
                    ForEach(model.profiles, id: \.profileIndex) { profile in
                        Button {
                            requirePin(for: profile, action: managing ? .edit : .select)
                        } label: {
                            ProfileTileLabel(profile: profile, avatars: model.avatars,
                                             managing: managing,
                                             isCurrent: profile.profileIndex == model.activeProfile?.profileIndex)
                        }
                        .buttonStyle(.borderless)
                        .focused($focusedProfile, equals: profile.profileIndex)
                        .prefersDefaultFocus(
                            profile.profileIndex == (model.activeProfile?.profileIndex ?? model.profiles.first?.profileIndex),
                            in: defaultFocusNamespace
                        )
                        .accessibilityLabel(profile.name)
                        .accessibilityValue(managing ? "Edit profile" : (profile.pinEnabled ? "Locked" : ""))
                        .accessibilityIdentifier("profiles.profile.\(profile.profileIndex)")
                        .contextMenu {
                            Button {
                                requirePin(for: profile, action: .edit)
                            } label: { Label("Edit Profile", systemImage: "pencil") }
                            if model.profiles.count > 1 {
                                Button(role: .destructive) {
                                    requirePin(for: profile, action: .delete)
                                } label: { Label("Delete Profile", systemImage: "trash") }
                            }
                        }
                    }
                }
                .frame(minHeight: 310)
                .padding(.vertical, 20)
                .focusSection()
                .focusScope(defaultFocusNamespace)

                GlassEffectContainer(spacing: 30) {
                    HStack(spacing: 30) {
                        Button {
                            managing.toggle()
                        } label: {
                            Label(managing ? "Done" : "Manage Profiles", systemImage: managing ? "checkmark" : "pencil")
                                .font(.system(size: 23, weight: .medium))
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("profiles.manage")
                        if model.profiles.count < model.maxProfiles {
                            Button {
                                editing = ProfileEditTarget(profile: nil)
                            } label: {
                                Label("Add Profile", systemImage: "plus")
                                    .font(.system(size: 23, weight: .medium))
                            }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("profiles.add")
                        }
                    }
                }.focusSection()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 80)
        }
        .onAppear { model.start() }
        .onChange(of: model.profiles.count) { oldCount, newCount in
            // One-shot: profiles land after initial focus may have already settled on Add, so
            // nudge focus onto the first real profile the moment they arrive (empty → non-empty).
            guard !didSeedDefaultFocus, oldCount == 0, newCount > 0 else { return }
            didSeedDefaultFocus = true
            let firstProfileIndex = model.activeProfile?.profileIndex ?? model.profiles.first?.profileIndex
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                focusedProfile = firstProfileIndex
            }
        }
        .fullScreenCover(item: $editing) { target in
            ProfileEditView(model: model, target: target)
        }
        .fullScreenCover(item: $pinPrompt) { prompt in
            PinEntryView(
                title: String(localized: "Enter PIN for \(prompt.profile.name)"),
                subtitle: prompt.action == .select ? nil : String(localized: "This profile is locked."),
                onCancel: { pinPrompt = nil },
                onSubmit: { pin, done in
                    model.verifyPin(prompt.profile, pin: pin) { result in
                        if result?.unlocked == true {
                            pinPrompt = nil
                            perform(prompt.action, on: prompt.profile)
                        } else {
                            done(pinErrorMessage(result))
                        }
                    }
                }
            )
        }
    }

    // MARK: - PIN gating

    private struct PinPrompt: Identifiable {
        enum Action { case select, edit, delete }
        let profile: NuvioProfile
        let action: Action
        var id: String { "\(profile.profileIndex)-\(action)" }
    }

    private func requirePin(for profile: NuvioProfile, action: PinPrompt.Action) {
        if profile.pinEnabled {
            pinPrompt = PinPrompt(profile: profile, action: action)
        } else {
            perform(action, on: profile)
        }
    }

    private func perform(_ action: PinPrompt.Action, on profile: NuvioProfile) {
        switch action {
        case .select:
            model.select(profile)
            onSelected()
        case .edit:
            editing = ProfileEditTarget(profile: profile)
        case .delete:
            model.deleteProfile(profile)
        }
    }

}

/// Native focus lift, one portrait outline and a fixed caption slot keep selection legible
/// without a rectangular tile or a second scaling animation.
private struct ProfileTileLabel: View {
    let profile: NuvioProfile
    let avatars: [AvatarCatalogItem]
    let managing: Bool
    let isCurrent: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(spacing: 24) {
            ProfileAvatar(profile: profile, size: 220, avatars: avatars)
                .overlay {
                    Circle().strokeBorder(.white.opacity(isFocused ? 0.95 : 0.12), lineWidth: isFocused ? 4 : 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    if managing || profile.pinEnabled {
                        Image(systemName: managing ? "pencil" : "lock.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Color(white: 0.14), in: Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    }
                }
            VStack(spacing: 8) {
                Text(profile.name)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(isFocused ? .white : .white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(managing ? "Edit Profile" : (isCurrent ? "Last used" : ""))
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(height: 24)
            }
        }.frame(width: 240)
    }
}

/// Formats a failed `PinVerifyResult` for display (server message, lockout countdown, or default).
func pinErrorMessage(_ result: PinVerifyResult?) -> String {
    if let message = result?.message, !message.isEmpty { return message }
    if let retry = result?.retryAfterSeconds, retry > 0 {
        return String(localized: "Too many attempts. Try again in \(retry)s.")
    }
    return String(localized: "Incorrect PIN. Try again.")
}

/// Identifiable wrapper so add (nil) / edit (existing) can drive `.fullScreenCover(item:)`.
struct ProfileEditTarget: Identifiable {
    let profile: NuvioProfile?
    var id: Int { profile.map { Int($0.profileIndex) } ?? -1 }
}

/// Add / edit form: name, avatar (cloud catalog picker when available, else color palette), and —
/// for cloud accounts editing an existing profile — the PIN lock (set / change / remove).
struct ProfileEditView: View {
    @ObservedObject var model: ProfilesViewModel
    let target: ProfileEditTarget

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: String
    @State private var avatarId: String?
    @State private var pinFlow: PinFlow?

    /// A custom avatar URL set elsewhere (e.g. on mobile); preserved unless a catalog avatar or
    /// the color tile is picked here.
    private let originalCustomAvatarUrl: String?

    private let palette = [
        "#E53935", "#1E88E5", "#8E24AA", "#43A047",
        "#FB8C00", "#D81B60", "#00ACC1", "#5E35B1",
    ]

    init(model: ProfilesViewModel, target: ProfileEditTarget) {
        self.model = model
        self.target = target
        _name = State(initialValue: target.profile?.name ?? "")
        _colorHex = State(initialValue: target.profile?.avatarColorHex ?? "#E53935")
        _avatarId = State(initialValue: target.profile?.avatarId)
        originalCustomAvatarUrl = target.profile?.avatarId == nil ? target.profile?.avatarUrl : nil
    }

    /// Live copy of the profile being edited (PIN state refreshes after set/clear → pullProfiles).
    private var liveProfile: NuvioProfile? {
        guard let index = target.profile?.profileIndex else { return nil }
        return model.profiles.first { $0.profileIndex == index }
    }

    private var selectedCatalogItem: AvatarCatalogItem? {
        model.avatars.first { $0.id == avatarId }
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.Spacing.xl) {
                    Text(target.profile == nil ? String(localized: "Add Profile") : String(localized: "Edit Profile"))
                        .font(Theme.Font.screenTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)

                    // Preview
                    ZStack {
                        if let item = selectedCatalogItem {
                            CachedAsyncImage(string: ProfileModelsKt.avatarStorageUrl(storagePath: item.storagePath))
                                .clipShape(Circle())
                        } else if let url = originalCustomAvatarUrl, avatarId == nil {
                            CachedAsyncImage(string: url)
                                .clipShape(Circle())
                        } else {
                            Circle().fill(Color(hexString: colorHex) ?? Theme.Palette.accent)
                            Text(name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
                                .font(Theme.Font.hero)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 150, height: 150)

                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.body)
                        .frame(maxWidth: 700)

                    // Cloud avatar catalog (hidden when empty — guest mode / offline).
                    if !model.avatars.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.lg) {
                                // "Color" tile — clears the catalog avatar.
                                Button { avatarId = nil } label: {
                                    ZStack {
                                        Circle().fill(Color(hexString: colorHex) ?? Theme.Palette.accent)
                                        Image(systemName: "paintpalette")
                                            .font(Theme.Font.body)
                                            .foregroundStyle(.white)
                                    }
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Circle().strokeBorder(
                                            Theme.Palette.textPrimary,
                                            lineWidth: avatarId == nil ? 5 : 0
                                        )
                                    )
                                    .modifier(FocusRingCircle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(String(localized: "Use color avatar"))

                                ForEach(model.avatars, id: \.id) { item in
                                    Button { avatarId = item.id } label: {
                                        CachedAsyncImage(string: ProfileModelsKt.avatarStorageUrl(storagePath: item.storagePath))
                                            .frame(width: 100, height: 100)
                                            .clipShape(Circle())
                                            .overlay(
                                                Circle().strokeBorder(
                                                    Theme.Palette.textPrimary,
                                                    lineWidth: avatarId == item.id ? 5 : 0
                                                )
                                            )
                                            .modifier(FocusRingCircle())
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(
                                        item.displayName.isEmpty
                                            ? String(localized: "Avatar")
                                            : item.displayName
                                    )
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.md)
                        }
                    }

                    // Color palette (used when no catalog avatar is selected).
                    HStack(spacing: Theme.Spacing.lg) {
                        ForEach(palette, id: \.self) { hex in
                            Button {
                                colorHex = hex
                                avatarId = nil
                            } label: {
                                Circle()
                                    .fill(Color(hexString: hex) ?? .gray)
                                    .frame(width: 70, height: 70)
                                    .overlay(
                                        Circle().strokeBorder(
                                            Theme.Palette.textPrimary,
                                            lineWidth: (hex == colorHex && avatarId == nil) ? 5 : 0
                                        )
                                    )
                                    .modifier(FocusRingCircle())
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    // PIN lock — existing profiles on cloud accounts only (RPCs need a session).
                    if let profile = liveProfile, model.isCloudAccount {
                        HStack(spacing: Theme.Spacing.lg) {
                            if profile.pinEnabled {
                                Button {
                                    pinFlow = .enterCurrent(remove: false)
                                } label: {
                                    Label("Change PIN", systemImage: "lock.rotation")
                                        .font(Theme.Font.body)
                                }
                                .buttonStyle(.chip)

                                Button(role: .destructive) {
                                    pinFlow = .enterCurrent(remove: true)
                                } label: {
                                    Label("Remove PIN", systemImage: "lock.slash")
                                        .font(Theme.Font.body)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.chip)
                            } else {
                                Button {
                                    pinFlow = .enterNew(current: nil)
                                } label: {
                                    Label("Set PIN Lock", systemImage: "lock")
                                        .font(Theme.Font.body)
                                }
                                .buttonStyle(.chip)
                            }
                        }
                    }

                    Button { save() } label: {
                        Text("Save")
                            .font(Theme.Font.meta)
                            .prominentAccentLabel()
                            .padding(.horizontal, Theme.Spacing.xl)
                            .padding(.vertical, Theme.Spacing.xs)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.accent)
                    .disabled(model.isBusy)

                    if let profile = target.profile, model.profiles.count > 1 {
                        Button(role: .destructive) {
                            model.deleteProfile(profile) { dismiss() }
                        } label: {
                            Label("Delete Profile", systemImage: "trash")
                                .font(Theme.Font.body)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.chip)
                    }
                }
                .padding(Theme.Spacing.screen)
            }
        }
        .fullScreenCover(item: $pinFlow) { flow in
            pinFlowView(flow)
        }
    }

    // MARK: - PIN flows

    private enum PinFlow: Identifiable {
        /// Verify the current PIN, then either remove the lock or continue to a new PIN.
        case enterCurrent(remove: Bool)
        /// Set a new PIN (with the verified current PIN when changing).
        case enterNew(current: String?)

        var id: String {
            switch self {
            case .enterCurrent(let remove): return "current-\(remove)"
            case .enterNew(let current): return "new-\(current ?? "none")"
            }
        }
    }

    @ViewBuilder
    private func pinFlowView(_ flow: PinFlow) -> some View {
        switch flow {
        case .enterCurrent(let remove):
            PinEntryView(
                title: String(localized: "Enter current PIN"),
                subtitle: remove ? String(localized: "Confirm the PIN to remove the lock.") : String(localized: "Confirm the PIN before choosing a new one."),
                onCancel: { pinFlow = nil },
                onSubmit: { pin, done in
                    guard let profile = liveProfile else { pinFlow = nil; return }
                    if remove {
                        model.clearPin(profileIndex: profile.profileIndex, currentPin: pin) { result in
                            if result?.unlocked == true {
                                pinFlow = nil
                            } else {
                                done(pinErrorMessage(result))
                            }
                        }
                    } else {
                        model.verifyPin(profile, pin: pin) { result in
                            if result?.unlocked == true {
                                pinFlow = .enterNew(current: pin)
                            } else {
                                done(pinErrorMessage(result))
                            }
                        }
                    }
                }
            )
        case .enterNew(let current):
            PinEntryView(
                title: String(localized: "Choose a 4-digit PIN"),
                subtitle: String(localized: "This profile will require the PIN to open."),
                onCancel: { pinFlow = nil },
                onSubmit: { pin, done in
                    guard let profile = liveProfile else { pinFlow = nil; return }
                    model.setPin(profileIndex: profile.profileIndex, pin: pin, currentPin: current) { result in
                        if result?.unlocked == true {
                            pinFlow = nil
                        } else {
                            done(pinErrorMessage(result))
                        }
                    }
                }
            )
        }
    }

    // MARK: - Save

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? String(localized: "Profile") : trimmed

        // Catalog avatar → store BOTH id and resolved URL (cross-device renderable without a
        // catalog lookup). Color tile → clear both. Untouched custom URL → preserve it.
        let finalAvatarUrl: String?
        if let item = selectedCatalogItem {
            finalAvatarUrl = ProfileModelsKt.avatarStorageUrl(storagePath: item.storagePath)
        } else {
            finalAvatarUrl = originalCustomAvatarUrl
        }

        if let profile = target.profile {
            model.updateProfile(
                profile,
                name: finalName,
                colorHex: colorHex,
                avatarId: avatarId,
                avatarUrl: finalAvatarUrl
            ) { dismiss() }
        } else {
            model.createProfile(
                name: finalName,
                colorHex: colorHex,
                avatarId: avatarId,
                avatarUrl: finalAvatarUrl
            ) { dismiss() }
        }
    }
}

/// Focus visuals for the circular avatar/color tiles in the profile editor: the system
/// `.borderless` lift carries the focus read (HIG revamp — no accent ring, no custom scale).
/// Selection keeps its separate white ring.
private struct FocusRingCircle: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
