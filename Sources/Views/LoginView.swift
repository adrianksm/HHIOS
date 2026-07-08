import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session

    @State private var username = ""
    @State private var password = ""
    @State private var serverURL = ""
    @State private var showServerField = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case username, password, server }

    var body: some View {
        ZStack {
            Color(hex: "#121316", fallback: .black).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    card
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { serverURL = session.baseURLString }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text("Hire Haulage")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
            Text("Delivery & collection planner")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 40)
    }

    private var card: some View {
        VStack(spacing: 16) {
            field(icon: "person", placeholder: "Username", text: $username, field: .username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .submitLabel(.next)
                .onSubmit { focus = .password }

            secureField

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                HStack {
                    if isSubmitting { ProgressView().tint(.white) }
                    Text(isSubmitting ? "Signing in…" : "Sign In")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .disabled(!canSubmit || isSubmitting)
            .opacity(canSubmit ? 1 : 0.5)

            serverDisclosure

            Divider().overlay(.white.opacity(0.1))

            Button {
                session.enterDemo()
            } label: {
                Label("Explore with sample data", systemImage: "play.circle")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(20)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var secureField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock").foregroundStyle(.white.opacity(0.5)).frame(width: 20)
            SecureField("", text: $password, prompt: Text("Password").foregroundColor(.white.opacity(0.4)))
                .foregroundStyle(.white)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func field(icon: String, placeholder: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.white.opacity(0.5)).frame(width: 20)
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.4)))
                .foregroundStyle(.white)
                .focused($focus, equals: field)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var serverDisclosure: some View {
        Button {
            withAnimation { showServerField.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                Text(showServerField ? "Hide server" : "Server settings")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.5))
        }

        if showServerField {
            field(icon: "globe", placeholder: "https://…", text: $serverURL, field: .server)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit, !isSubmitting else { return }
        focus = nil
        let trimmedServer = serverURL.trimmingCharacters(in: .whitespaces)
        if !trimmedServer.isEmpty, trimmedServer != session.baseURLString {
            session.baseURLString = trimmedServer
        }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await session.signIn(
                    username: username.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

#Preview {
    LoginView().environment(Session())
}
