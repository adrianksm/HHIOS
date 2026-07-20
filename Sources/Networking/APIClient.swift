import Foundation

/// Thin async wrapper over the Hire Haulage REST API.
///
/// Auth is cookie/session based: `login` performs `POST /api/auth/login`, the
/// server returns a session cookie, and `URLSession`'s shared cookie storage
/// sends it automatically on every subsequent request. (CORS does not apply to
/// native clients, and the httpOnly flag only affects JavaScript, not URLSession.)
struct APIClient {
    let baseURL: URL

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = .shared
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    init?(baseURLString: String) {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespaces)),
              url.scheme != nil, url.host != nil else { return nil }
        self.baseURL = url
    }

    // MARK: - Auth

    func login(username: String, password: String) async throws -> AuthUser {
        try await request(
            "/api/auth/login",
            method: "POST",
            body: ["username": username, "password": password]
        )
    }

    func me() async throws -> AuthUser {
        try await request("/api/auth/me")
    }

    func logout() async throws {
        _ = try await requestData("/api/auth/logout", method: "POST", body: [:])
    }

    // MARK: - Config & hauliers

    func config() async throws -> AppConfig {
        try await request("/api/config")
    }

    func hauliers() async throws -> [Haulier] {
        try await request("/api/hauliers")
    }

    // MARK: - Jobs

    func jobs(query: JobQuery) async throws -> JobsResponse {
        try await request("/api/jobs", queryItems: query.queryItems)
    }

    func job(id: Int) async throws -> Job {
        try await request("/api/jobs/\(id)")
    }

    func relatedJob(id: Int) async throws -> [Job] {
        try await request("/api/jobs/\(id)/related")
    }

    func movements(jobId: Int) async throws -> [MovementAssignment] {
        try await request("/api/jobs/\(jobId)/movements")
    }

    /// Per-movement furniture override rows. Empty means the loads auto-allocate.
    func movementFurniture(jobId: Int) async throws -> [MovementFurnitureRow] {
        try await request("/api/jobs/\(jobId)/movement-furniture")
    }

    /// A status/notes PATCH response: the updated job, plus the server's
    /// "every movement of this job is now completed" flag that drives the
    /// Current-RMS completion flow (`CrmsCompletionFlow`).
    struct JobUpdateResult {
        let job: Job
        let allMovementsCompleted: Bool
    }

    /// Update job-level fields. Pass only the keys you want to change.
    /// `haulierId` uses `.set(nil)` to unassign vs `.unchanged` to leave alone.
    func updateJob(id: Int, status: JobStatus? = nil, notes: String? = nil,
                   haulier: HaulierChange = .unchanged) async throws -> JobUpdateResult {
        var body: [String: Any] = [:]
        if let status { body["status"] = status.rawValue }
        if let notes { body["notes"] = notes }
        switch haulier {
        case .unchanged: break
        case .set(let value): body["haulier_id"] = value ?? NSNull()
        }
        let data = try await requestData("/api/jobs/\(id)", method: "PATCH", body: body)
        return try Self.decodeJobUpdate(data)
    }

    enum HaulierChange {
        case unchanged
        case set(Int?)
    }

    enum DateChange {
        case unchanged
        case set(String?)   // "YYYY-MM-DD" or nil to clear the override
    }

    /// Update a single movement (status/notes for all; haulier/date for admins) in
    /// one atomic `PATCH /jobs/:id` with a movement payload. Returns the updated job.
    func updateMovement(
        jobId: Int, transportName: String, movementIndex: Int,
        status: JobStatus, notes: String,
        haulier: HaulierChange = .unchanged, date: DateChange = .unchanged,
        isAdmin: Bool
    ) async throws -> JobUpdateResult {
        var movement: [String: Any] = [
            "transport_name": transportName,
            "movement_index": movementIndex,
            "notes": notes
        ]
        if isAdmin {
            if case .set(let value) = haulier { movement["haulier_id"] = value ?? NSNull() }
            if case .set(let value) = date { movement["date"] = value ?? NSNull() }
        }
        let body: [String: Any] = ["status": status.rawValue, "movement": movement]
        let data = try await requestData("/api/jobs/\(jobId)", method: "PATCH", body: body)
        return try Self.decodeJobUpdate(data)
    }

    /// The PATCH response is the job object with `allMovementsCompleted` merged
    /// in at the top level (see the web repo's `src/routes/api/jobs.js`) — the
    /// `Job` decoder skips unknown keys, so pull the flag out separately.
    /// Missing flag decodes as `false`, which can never over-trigger the flow.
    private static func decodeJobUpdate(_ data: Data) throws -> JobUpdateResult {
        struct Flag: Decodable { let allMovementsCompleted: Bool? }
        do {
            let job = try JSONDecoder().decode(Job.self, from: data)
            let flag = (try? JSONDecoder().decode(Flag.self, from: data))?.allMovementsCompleted ?? false
            return JobUpdateResult(job: job, allMovementsCompleted: flag)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    // MARK: - Current-RMS completion flow

    /// The opportunity's line items (`opportunity.opportunity_items`).
    func opportunityItems(opportunityId: Int) async throws -> CrmsOpportunityItemsResponse {
        try await request("/api/crms/opportunities/\(opportunityId)/items")
    }

    /// One item's `item_assets` — the ids book-out/check-in/close-order need.
    func opportunityItemAssets(opportunityId: Int, itemId: Int) async throws -> CrmsItemAssetsResponse {
        try await request("/api/crms/opportunities/\(opportunityId)/items/\(itemId)/assets")
    }

    /// Book out items in Current RMS (delivery completed).
    func bookOut(opportunityId: Int, itemAssetIds: [Int]) async throws {
        _ = try await requestData(
            "/api/crms/opportunities/\(opportunityId)/book-out",
            method: "POST", body: ["item_asset_ids": itemAssetIds]
        )
    }

    /// Check in items in Current RMS (collection completed).
    func checkIn(opportunityId: Int, itemAssetIds: [Int]) async throws {
        _ = try await requestData(
            "/api/crms/opportunities/\(opportunityId)/check-in",
            method: "POST", body: ["item_asset_ids": itemAssetIds]
        )
    }

    /// Close the order in Current RMS: finalise items + services, mark the
    /// opportunity Completed. Always answers 200 with per-step results.
    func closeOrder(opportunityId: Int, itemAssetIds: [Int], serviceAssetIds: [Int]) async throws -> CrmsCloseOrderResponse {
        try await request(
            "/api/crms/opportunities/\(opportunityId)/close-order",
            method: "POST",
            body: ["item_asset_ids": itemAssetIds, "service_asset_ids": serviceAssetIds]
        )
    }

    /// Update the opportunity's delivery & collection dates (admin). Pushes to
    /// Current-RMS server-side; both the delivery and collection jobs are updated.
    func updateDates(jobId: Int, deliverDate: String, collectDate: String) async throws {
        _ = try await requestData(
            "/api/jobs/\(jobId)/dates",
            method: "PATCH",
            body: ["deliver_date": deliverDate, "collect_date": collectDate]
        )
    }

    /// Trigger a Current-RMS sync (admin).
    func sync() async throws -> SyncResult {
        try await request("/api/sync", method: "POST", body: [:])
    }

    // MARK: - Core

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: [String: Any]? = nil
    ) async throws -> T {
        let data = try await requestData(path, method: method, queryItems: queryItems, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    @discardableResult
    private func requestData(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: [String: Any]? = nil
    ) async throws -> Data {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.badURL }
        if let queryItems, !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw APIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("No HTTP response.")
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        default:
            throw APIError.server(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["error"] as? String ?? obj["message"] as? String
    }
}

/// Filters for `GET /api/jobs`. Kept to the parameters the app actually uses;
/// the server supports more (type/status/haulier/date_to/include_closed) — add
/// them here when a screen needs them.
struct JobQuery {
    var limit: Int = 100
    var dateFrom: String? = nil
    var includeMovements: Bool = false
    /// Include completed-in-CRMS (archived) jobs as read-only history.
    var includeClosed: Bool = false

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let dateFrom { items.append(URLQueryItem(name: "date_from", value: dateFrom)) }
        if includeMovements { items.append(URLQueryItem(name: "include_movements", value: "true")) }
        if includeClosed { items.append(URLQueryItem(name: "include_closed", value: "true")) }
        return items
    }
}
