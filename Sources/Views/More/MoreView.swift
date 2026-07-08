import SwiftUI

struct MoreView: View {
    @Environment(Session.self) private var session
    @Environment(JobStore.self) private var store
    @State private var showSignOutConfirm = false
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var showSyncResult = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                if session.isAdmin { syncSection }
                operationsSection
                serverSection
                aboutSection
                signOutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("More")
            .alert("Current-RMS sync", isPresented: $showSyncResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncMessage ?? "")
            }
        }
    }

    private var syncSection: some View {
        Section {
            Button {
                Task { await runSync() }
            } label: {
                HStack {
                    Label("Sync from Current-RMS", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if isSyncing { ProgressView() }
                }
            }
            .disabled(isSyncing)
        } footer: {
            Text("Pulls the latest confirmed orders from Current-RMS.")
        }
        .listRowBackground(Theme.card)
    }

    private func runSync() async {
        isSyncing = true
        defer { isSyncing = false }
        if session.isDemo {
            syncMessage = "Sync isn't available in demo mode."
            showSyncResult = true
            return
        }
        guard let client = session.client else { return }
        do {
            let result = try await client.sync()
            await store.load()
            syncMessage = result.displayMessage
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            syncMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        showSyncResult = true
    }

    private var accountSection: some View {
        Section("Account") {
            if let user = session.user {
                LabeledContent("Signed in as", value: user.username)
                LabeledContent("Role") {
                    Text(user.role.rawValue.capitalized)
                        .font(.dc(14, .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .listRowBackground(Theme.card)
    }

    @ViewBuilder
    private var operationsSection: some View {
        if session.config.defaultDepot != nil || session.config.pricing != nil {
            Section("Operation") {
                if let depot = session.config.defaultDepot {
                    LabeledContent("Depot", value: [depot.name?.nilIfBlank, depot.postcode?.nilIfBlank]
                        .compactMap { $0 }.joined(separator: " · ").nilIfBlank ?? "—")
                }
                if let pricing = session.config.pricing, let base = pricing.base, let perMile = pricing.perMile {
                    LabeledContent("Pricing",
                                   value: "\(base.formatted(.currency(code: "GBP"))) + \(perMile.formatted(.currency(code: "GBP")))/mi")
                }
                if let sub = session.config.crms?.subdomain?.nilIfBlank {
                    LabeledContent("Current-RMS", value: sub)
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    private var serverSection: some View {
        Section("Connection") {
            NavigationLink {
                ServerSettingsView()
            } label: {
                LabeledContent("Server") {
                    Text(session.baseURLString)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .listRowBackground(Theme.card)
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
        } footer: {
            Text("Hire Haulage — delivery & collection planner.")
        }
        .listRowBackground(Theme.card)
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .confirmationDialog("Sign out of Hire Haulage?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
                Button("Cancel", role: .cancel) {}
            }
        }
        .listRowBackground(Theme.card)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

struct ServerSettingsView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                TextField("https://…", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Server address")
            } footer: {
                Text("The base URL of your Hire Haulage server. Changing this signs you out.")
            }
            .listRowBackground(Theme.card)

            Section {
                Button("Reset to default") { draft = Session.defaultBaseURL }
                    .disabled(draft == Session.defaultBaseURL)
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await saveAndSignOut() } }
                    .fontWeight(.semibold)
                    .disabled(!isValid || draft == session.baseURLString)
            }
        }
        .onAppear { draft = session.baseURLString }
    }

    private var isValid: Bool {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: t) else { return false }
        return url.scheme != nil && url.host != nil
    }

    private func saveAndSignOut() async {
        session.baseURLString = draft.trimmingCharacters(in: .whitespaces)
        await session.signOut()
        dismiss()
    }
}
