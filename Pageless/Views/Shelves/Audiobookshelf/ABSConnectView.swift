//
//  ABSConnectView.swift
//  Pageless
//
//  "Bring your own shelf." — connect an Audiobookshelf server with a username/password or an
//  API key. Errors render inline under the field they concern; never as alerts. The one alert is
//  the plain-http-to-a-public-host confirmation, shown before any credential leaves the device.
//

import SwiftUI

struct ABSConnectView: View {
    var account: ABSAccount = .shared
    /// Called after a connection is stored, before the sheet dismisses itself.
    var onConnected: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: ABSConnectViewModel
    @FocusState private var focus: ABSConnectViewModel.Field?

    init(account: ABSAccount? = nil, initialServer: String = "", onConnected: @escaping () -> Void = {}) {
        self.account = account ?? .shared
        self.onConnected = onConnected
        _viewModel = State(initialValue: ABSConnectViewModel(serverText: initialServer))
    }

    var body: some View {
        @Bindable var vm = viewModel
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, 32)

                    field(
                        label: "Server",
                        field: .server,
                        text: $vm.serverText,
                        prompt: "https://abs.example.com",
                        keyboard: .URL,
                        contentType: .URL,
                        submitLabel: .next,
                        identifier: "abs.connect.server"
                    )
                    .padding(.bottom, 26)

                    modePicker
                        .padding(.bottom, 22)

                    Group {
                        if viewModel.mode == .signIn {
                            VStack(alignment: .leading, spacing: 18) {
                                field(label: "Username", field: .username, text: $vm.username,
                                      prompt: "Your Audiobookshelf username", contentType: .username,
                                      submitLabel: .next, identifier: "abs.connect.username")
                                field(label: "Password", field: .password, text: $vm.password,
                                      prompt: "Password", isSecure: true, contentType: .password,
                                      submitLabel: .go, identifier: "abs.connect.password")
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                field(label: "API key", field: .apiKey, text: $vm.apiKey,
                                      prompt: "Paste your API key", isSecure: true,
                                      submitLabel: .go, identifier: "abs.connect.apiKey")
                                Text("Create one in Audiobookshelf under Settings → API Keys.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .transition(.opacity)
                    .padding(.bottom, 32)

                    connectButton
                        .padding(.bottom, 16)

                    Label {
                        Text("Your login stays on this iPhone, in the Keychain.")
                    } icon: {
                        Image(systemName: "lock")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: 460, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isConnecting)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.cream.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("abs.connect.cancel")
                }
            }
            .animation(reduceMotion ? nil : AppMotion.stateChange, value: viewModel.mode)
            .animation(reduceMotion ? nil : AppMotion.stateChange, value: viewModel.error)
            .alert(
                ABSConnectViewModel.insecureServerTitle,
                isPresented: Binding(
                    get: { viewModel.insecureServerWarning != nil },
                    set: { if !$0 { viewModel.cancelInsecureServer() } }
                ),
                presenting: viewModel.insecureServerWarning
            ) { _ in
                Button("Continue") {
                    viewModel.confirmInsecureServer()
                    Task { await submit() }
                }
                .accessibilityIdentifier("abs.connect.insecure.continue")
                Button("Cancel", role: .cancel) { viewModel.cancelInsecureServer() }
                    .accessibilityIdentifier("abs.connect.insecure.cancel")
            } message: { warning in
                Text("\(warning.host) uses plain http://. \(warning.message)")
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ABSEyebrow(text: "Audiobookshelf")
            Text("Bring your own shelf.")
                .font(ABSType.display())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Connect your Audiobookshelf server to browse and stream your library in Unpaged.")
                .font(.system(.body, design: .serif))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 22) {
            ForEach(ABSConnectViewModel.Mode.allCases) { mode in
                let isSelected = viewModel.mode == mode
                Button {
                    viewModel.mode = mode
                    viewModel.clearErrors()
                } label: {
                    VStack(spacing: 6) {
                        Text(mode.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                        Rectangle()
                            .fill(isSelected ? Color.primary : Color.clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("abs.connect.mode.\(mode.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(ABSType.hairline).frame(height: 0.5)
        }
    }

    private var connectButton: some View {
        Button {
            focus = nil
            Task { await submit() }
        } label: {
            HStack(spacing: 10) {
                if viewModel.isConnecting {
                    ProgressView().tint(.white)
                }
                Text(viewModel.isConnecting ? "Connecting…" : "Connect")
            }
        }
        .buttonStyle(ABSPrimaryButtonStyle())
        .disabled(!viewModel.canSubmit)
        .accessibilityIdentifier("abs.connect.submit")
    }

    @ViewBuilder
    private func field(
        label: String,
        field: ABSConnectViewModel.Field,
        text: Binding<String>,
        prompt: String,
        isSecure: Bool = false,
        keyboard: UIKeyboardType = .default,
        contentType: UITextContentType? = nil,
        submitLabel: SubmitLabel,
        identifier: String
    ) -> some View {
        let error = viewModel.message(for: field)
        VStack(alignment: .leading, spacing: 8) {
            ABSEyebrow(text: label)
            Group {
                if isSecure {
                    SecureField("", text: text, prompt: Text(prompt).foregroundStyle(.tertiary))
                } else {
                    TextField("", text: text, prompt: Text(prompt).foregroundStyle(.tertiary))
                        .keyboardType(keyboard)
                }
            }
            .font(.body)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(submitLabel)
            .focused($focus, equals: field)
            .onSubmit { advance(from: field) }
            .onChange(of: text.wrappedValue) { _, _ in viewModel.clearError(for: field) }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(Color.cardWhite, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(error == nil ? ABSType.hairline : Color.red.opacity(0.7),
                                  lineWidth: error == nil ? 0.5 : 1)
            )
            .accessibilityLabel(label)
            .accessibilityHint(error ?? "")
            .accessibilityIdentifier(identifier)

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityIdentifier("\(identifier).error")
            }
        }
    }

    // MARK: - Actions

    private func advance(from field: ABSConnectViewModel.Field) {
        switch field {
        case .server: focus = viewModel.mode == .signIn ? .username : .apiKey
        case .username: focus = .password
        case .password, .apiKey:
            focus = nil
            Task { await submit() }
        }
    }

    private func submit() async {
        guard viewModel.canSubmit else { return }
        if await viewModel.connect(account: account) {
            ABSCoverStore.shared.removeAll()
            onConnected()
            dismiss()
        } else if let field = viewModel.error?.field {
            UIAccessibility.post(notification: .announcement, argument: viewModel.message(for: field))
        }
    }
}
