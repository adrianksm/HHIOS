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
    private static let sessionCacheKey = "HH_sessionCache"

    /// Cached identity + reference data, persisted in `UserDefaults` (small,
    /// infrequent writes — no need for a dedicated file) so the app can enter
    /// the signed-in UI immediately on next launch while `/api/auth/me` +
    /// `loadReferenceData()` validate/refresh in the background. Validated by
    /// `serverURL` on load. `AuthUser`/`AppConfig`/`Haulier` are already
    /// `Codable` (verified: every stored property is covered by their
    /// `CodingKeys`/synthesis, no custom `init(from:)`/`encode(to:)`) — no
    /// conformance needed to be added.
    private struct SessionCache: Codable {
        let serverURL: String
        let user: AuthUser
        let config: AppConfig
        let hauliers: [Haulier]
    }

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
    ///
    /// If a cached user for the current server exists, enter the signed-in UI
    /// immediately from that cache and validate/refresh in the background —
    /// no launch spinner waiting on the network. Otherwise fall back to the
    /// original blocking `/api/auth/me` check (unchanged behaviour when there's
    /// no cache yet).
    func restore() async {
        guard let client else { phase = .signedOut; return }
        if let cached = Self.loadCache(), cached.serverURL == baseURLString {
            user = cached.user
            config = cached.config
            hauliers = cached.hauliers
            hauliersByID = Dictionary(uniqueKeysWithValues: cached.hauliers.map { ($0.id, $0) })
            phase = .signedIn
            Task { await self.validateCachedSession(client: client) }
            return
        }
        do {
            let me = try await client.me()
            user = me
            phase = .signedIn
            await loadReferenceData()
        } catch {
            phase = .signedOut
        }
    }

    /// Confirms a cache-restored session is still valid, without blocking the
    /// UI (called from `restore()`'s fast path). A 401/unauthorized means the
    /// cookie is genuinely gone, so sign out to the login screen. Any other
    /// failure (offline, server hiccup) is non-fatal — the cookie may still be
    /// fine, so stay signed in with the cached data; the next real API call
    /// will surface a genuine auth problem.
    private func validateCachedSession(client: APIClient) async {
        do {
            let me = try await client.me()
            user = me
            await loadReferenceData()
        } catch APIError.unauthorized {
            await signOut()
        } catch {
            // Network/server error — keep showing the cached data.
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
        Self.clearCache()
        JobStore.deleteSnapshot()
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
    /// Writes the session cache on completion (called after every successful
    /// login/restore), so the next launch has fresh data to fast-path into.
    func loadReferenceData() async {
        guard let client else { return }
        async let cfg = try? client.config()
        async let haul = try? client.hauliers()
        if let cfg = await cfg { config = cfg }
        if let haul = await haul {
            hauliers = haul.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            hauliersByID = Dictionary(uniqueKeysWithValues: haul.map { ($0.id, $0) })
        }
        saveCache()
    }

    // MARK: - Session cache (instant launch)

    /// Writes the current user/config/hauliers to `UserDefaults`, keyed by the
    /// current server URL. No-op in demo mode (demo never touches the cache)
    /// or before a user is signed in.
    private func saveCache() {
        guard !isDemo, let user else { return }
        let cache = SessionCache(serverURL: baseURLString, user: user, config: config, hauliers: hauliers)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: Self.sessionCacheKey)
    }

    /// Tolerant load — a missing key, decode error, or schema drift just means
    /// no cache hit (`nil`), never a crash.
    private static func loadCache() -> SessionCache? {
        guard let data = UserDefaults.standard.data(forKey: sessionCacheKey) else { return nil }
        return try? JSONDecoder().decode(SessionCache.self, from: data)
    }

    private static func clearCache() {
        UserDefaults.standard.removeObject(forKey: sessionCacheKey)
    }
}
