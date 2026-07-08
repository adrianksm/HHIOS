import Foundation
import Observation

/// App-wide auth + configuration state. Owns the API client, the signed-in user,
/// the base URL (persisted), and a cached haulier lookup used for badges.
@MainActor
@Observable
final class Session {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn
    }

    static let defaultBaseURL = "https://hirehaulage.spudbox.com"
    private static let baseURLKey = "HH_baseURL"

    private(set) var phase: Phase = .launching
    private(set) var user: AuthUser?
    private(set) var config: AppConfig = .empty
    private(set) var hauliers: [Haulier] = []

    /// When true the app runs entirely on bundled sample data (no network).
    private(set) var isDemo = false

    /// Non-fatal banner errors (e.g. background refresh failures).
    var lastErrorMessage: String?

    var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: Self.baseURLKey)
            rebuildClient()
        }
    }

    private(set) var client: APIClient?

    var isAdmin: Bool { user?.role.isAdmin ?? false }

    private var hauliersByID: [Int: Haulier] = [:]

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.baseURLKey)
        self.baseURLString = stored ?? Self.defaultBaseURL
        rebuildClient()
    }

    private func rebuildClient() {
        client = APIClient(baseURLString: baseURLString)
    }

    func haulier(id: Int?) -> Haulier? {
        guard let id else { return nil }
        return hauliersByID[id]
    }

    // MARK: - Lifecycle

    /// Called on launch: validate any existing session cookie.
    func restore() async {
        guard let client else { phase = .signedOut; return }
        do {
            let me = try await client.me()
            user = me
            phase = .signedIn
            await loadReferenceData()
        } catch {
            phase = .signedOut
        }
    }

    func signIn(username: String, password: String) async throws {
        guard let client else { throw APIError.badURL }
        let me = try await client.login(username: username, password: password)
        user = me
        phase = .signedIn
        await loadReferenceData()
    }

    func signOut() async {
        if !isDemo, let client { try? await client.logout() }
        user = nil
        hauliers = []
        hauliersByID = [:]
        isDemo = false
        phase = .signedOut
    }

    /// Enter an offline demo populated with bundled sample data.
    func enterDemo() {
        isDemo = true
        user = AuthUser(id: 0, username: "demo", roleRaw: "admin", haulierId: nil)
        config = SampleData.config
        hauliers = SampleData.hauliers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        hauliersByID = Dictionary(uniqueKeysWithValues: SampleData.hauliers.map { ($0.id, $0) })
        phase = .signedIn
    }

    /// Pull config + hauliers used across the app. Failures are non-fatal.
    func loadReferenceData() async {
        guard let client else { return }
        async let cfg = try? client.config()
        async let haul = try? client.hauliers()
        if let cfg = await cfg { config = cfg }
        if let haul = await haul {
            hauliers = haul.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            hauliersByID = Dictionary(uniqueKeysWithValues: haul.map { ($0.id, $0) })
        }
    }
}
