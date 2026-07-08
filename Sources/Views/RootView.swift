import SwiftUI

/// Switches between launch, login, and the main app based on auth state.
struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        switch session.phase {
        case .launching:
            LaunchView()
        case .signedOut:
            LoginView()
                .transition(.opacity)
        case .signedIn:
            MainTabView()
                .transition(.opacity)
        }
    }
}

/// Branded splash shown while we validate any existing session.
struct LaunchView: View {
    var body: some View {
        ZStack {
            Color(hex: "#121316", fallback: .black).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.accent)
                Text("Hire Haulage")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(.white)
                    .padding(.top, 4)
            }
        }
    }
}

#Preview { LaunchView() }
