import Foundation
import Observation

/// Loads the live jobs once and exposes filtered/grouped views for the Today and
/// Schedule tabs. Both tabs read the same store so a single refresh updates both.
@MainActor
@Observable
final class JobStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var jobs: [Job] = []

    /// Per-load assignments keyed by job id, so cards can show real (per-movement)
    /// haulier assignments instead of the often-empty job-level haulier.
    private(set) var assignmentsByJob: [Int: [MovementAssignment]] = [:]

    /// Every job expanded into its movements (loads), rebuilt whenever `jobs` or
    /// `assignmentsByJob` changes. `todaysMovements`/`movementSchedule` filter/sort
    /// this instead of re-expanding (and re-decoding each job's furniture/transport
    /// JSON) on every SwiftUI body evaluation.
    private(set) var allMovements: [Movement] = []

    /// Everything `JobDetailView` needs for one job, cached in memory for
    /// `detailCacheWindow` after a successful fetch so reopening a just-viewed
    /// job is instant and fires no network. Never persisted — its lifetime is
    /// the store's own (the store is scoped to the signed-in session, see
    /// `MainTabView`, and is recreated fresh on the next sign-in), so one
    /// user's details never leak into the next.
    struct JobDetail {
        let job: Job
        let related: [Job]
        let assignments: [MovementAssignment]
        let furnitureOverrides: [MovementFurnitureRow]
        let fetchedAt: Date
    }

    /// How long a cached `JobDetail` stays fresh before `JobDetailView` should
    /// re-fetch instead of trusting the cache.
    static let detailCacheWindow: TimeInterval = 180

    private var detailCache: [Int: JobDetail] = [:]

    func detail(for jobId: Int) -> JobDetail? {
        detailCache[jobId]
    }

    func setDetail(_ detail: JobDetail, for jobId: Int) {
        detailCache[jobId] = detail
    }

    func invalidateDetail(for jobId: Int) {
        detailCache.removeValue(forKey: jobId)
    }

    // Filters (apply to the Schedule tab)
    var typeFilter: JobType? = nil
    var statusFilter: Set<JobStatus> = []

    /// How far back the Schedule fetches, in days. Starts at 2 weeks; the
    /// "Load earlier" control steps it back 2 weeks at a time. Persists across
    /// refreshes so the user doesn't lose the history they've pulled in.
    private(set) var historyDaysBack = 14
    /// True while a "load earlier" fetch is in flight (drives the button spinner).
    var isLoadingMore = false

    /// The earliest date currently being fetched (for the "Load earlier" label).
    var historyFromString: String {
        DateUtil.addingDays(-historyDaysBack, to: DateUtil.todayString()) ?? DateUtil.todayString()
    }

    private weak var session: Session?

    func configure(session: Session) {
        self.session = session
    }

    var isLoading: Bool { phase == .loading }

    func loadIfNeeded() async {
        guard case .idle = phase else { return }
        // Instant path: a matching on-disk snapshot lets us render before any
        // network call, then a background `load()` refreshes quietly (see
        // `restoreSnapshotIfMatching` and Part B's phase rules below).
        if let session, !session.isDemo, restoreSnapshotIfMatching(session: session) {
            phase = .loaded
            Task { await load() }
            return
        }
        await load()
    }

    func load() async {
        if session?.isDemo == true {
            jobs = Self.visible(SampleData.jobs).sorted(by: Self.chronological)
            assignmentsByJob = SampleData.assignmentsByJob
            rebuildMovements()
            phase = .loaded
            return
        }
        guard let client = session?.client else {
            if jobs.isEmpty { phase = .failed("No server configured.") }
            return
        }
        // With a snapshot (or prior load) already on screen, this is a silent
        // background refresh — don't blank the UI. Pull-to-refresh has its own
        // native spinner, and "Load earlier" reads `isLoading` to disable itself.
        if jobs.isEmpty { phase = .loading }
        // Window: `historyDaysBack` of history plus everything upcoming. Client-side
        // grouping handles Today vs Schedule, so one fetch feeds both tabs.
        // include_movements brings per-load assignments so cards show the real haulier(s).
        var query = JobQuery()
        query.limit = 1000
        query.includeMovements = true
        query.includeClosed = true   // surface completed-in-CRMS jobs as read-only history
        query.dateFrom = historyFromString
        do {
            let response = try await client.jobs(query: query)
            jobs = Self.visible(response.jobs).sorted(by: Self.chronological)
            assignmentsByJob = Self.indexAssignments(response.movementAssignments)
            rebuildMovements()
            phase = .loaded
            saveSnapshot()
        } catch {
            // A failed background refresh with data already on screen keeps that
            // data up and stays silent; only a first-ever load surfaces the error.
            if jobs.isEmpty {
                phase = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// Step the history window back another 2 weeks and re-fetch, so the Schedule
    /// reveals older jobs. No-op while a fetch is already running.
    func loadEarlier() async {
        guard !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        historyDaysBack += 14
        await load()
        isLoadingMore = false
    }

    // MARK: - Disk snapshot (instant launch)

    /// On-disk copy of the last successful non-demo `load()`, written to a
    /// single JSON file in Application Support so the next launch can render
    /// instantly and refresh in the background. `Job`/`MovementAssignment` are
    /// already `Codable` (verified: every stored property is listed in their
    /// `CodingKeys` and none has a custom `init(from:)`/`encode(to:)`, so both
    /// directions synthesize) — no changes were needed to make them round-trip.
    private struct Snapshot: Codable {
        var schemaVersion: Int
        var serverURL: String
        var username: String
        var savedAt: Date
        var historyDaysBack: Int
        var jobs: [Job]
        var assignmentsByJob: [Int: [MovementAssignment]]
    }

    private static let snapshotSchemaVersion = 1

    // `nonisolated` — these touch only `FileManager`, no actor-isolated state,
    // and must be reachable from the detached background task in `saveSnapshot()`.
    private nonisolated static var snapshotDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HHiOS", isDirectory: true)
    }

    private nonisolated static var snapshotURL: URL? {
        snapshotDirectory?.appendingPathComponent("job-snapshot.json")
    }

    /// Populates `jobs`/`assignmentsByJob`/`historyDaysBack` from the on-disk
    /// snapshot if one exists and matches the current server + signed-in user
    /// and schema version. Returns whether it did. Tolerant of every failure
    /// mode (missing file, schema drift, decode error, wrong identity) — a
    /// stale or unreadable snapshot is simply ignored and overwritten by the
    /// next successful `load()`.
    private func restoreSnapshotIfMatching(session: Session) -> Bool {
        guard let username = session.user?.username,
              let url = Self.snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.schemaVersion == Self.snapshotSchemaVersion,
              snapshot.serverURL == session.baseURLString,
              snapshot.username == username
        else { return false }
        jobs = snapshot.jobs
        assignmentsByJob = snapshot.assignmentsByJob
        historyDaysBack = snapshot.historyDaysBack
        rebuildMovements()
        return true
    }

    /// Persists the just-loaded jobs/assignments so the next launch can
    /// restore them via `restoreSnapshotIfMatching`. `Snapshot` is a plain
    /// value-type copy of the data at this moment, so it's safe to hand to a
    /// detached background task for the encode + write — the store itself
    /// (`@MainActor`) is never blocked. Tolerant of every failure (no
    /// Application Support directory, encode error, disk full): a cache write
    /// must never crash or block the app.
    private func saveSnapshot() {
        guard let session, !session.isDemo, let username = session.user?.username else { return }
        let snapshot = Snapshot(
            schemaVersion: Self.snapshotSchemaVersion,
            serverURL: session.baseURLString,
            username: username,
            savedAt: Date(),
            historyDaysBack: historyDaysBack,
            jobs: jobs,
            assignmentsByJob: assignmentsByJob
        )
        Task.detached(priority: .utility) {
            guard let dir = Self.snapshotDirectory, let url = Self.snapshotURL else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Deletes the on-disk snapshot. Called on sign-out (which also covers a
    /// server-URL change — `ServerSettingsView` always signs out when the
    /// address changes) so one user's cached jobs never sit around to leak
    /// into the next session. Safe to call even when no snapshot exists.
    static func deleteSnapshot() {
        guard let url = snapshotURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Drop archived jobs that aren't genuinely completed. The local archive
    /// (`closed_in_crms`) holds anything that left CRMS's active Orders window —
    /// not only completed/financialised jobs, but quotes & provisionals that never
    /// confirmed (status pending/booked). We only want real completed history, so
    /// a closed job is shown only when its status is `completed`. Live jobs (state-3
    /// Orders) are never filtered.
    private static func visible(_ jobs: [Job]) -> [Job] {
        jobs.filter { !$0.isClosed || $0.status == .completed }
    }

    /// Convert the API's string-keyed assignments map to Int-keyed.
    private static func indexAssignments(_ map: [String: [MovementAssignment]]?) -> [Int: [MovementAssignment]] {
        guard let map else { return [:] }
        var result: [Int: [MovementAssignment]] = [:]
        for (key, value) in map {
            if let id = Int(key) { result[id] = value }
        }
        return result
    }

    func assignments(for jobId: Int) -> [MovementAssignment] {
        assignmentsByJob[jobId] ?? []
    }

    /// Update the cached assignments for a job (after editing in the detail view),
    /// so the list cards reflect the change without a full reload.
    func setAssignments(_ assignments: [MovementAssignment], for jobId: Int) {
        // Post-save refreshes usually hand back exactly what the optimistic
        // update already applied — skip the full movement rebuild when so.
        guard assignmentsByJob[jobId] != assignments else { return }
        assignmentsByJob[jobId] = assignments
        rebuildMovements()
    }

    /// Replace a single job in place after an edit, keeping sort order.
    func replace(_ job: Job) {
        if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
            // The PATCH response often equals the optimistic edit already in
            // place — skip the re-sort and full movement rebuild when so.
            guard jobs[idx] != job else { return }
            jobs[idx] = job
        } else {
            jobs.append(job)
        }
        jobs.sort(by: Self.chronological)
        rebuildMovements()
    }

    /// Rebuild `allMovements` from `jobs`/`assignmentsByJob` — the one place that
    /// pays for `Movement.expand` (and, transitively, `LineItem.parse`). Call
    /// whenever either input changes; everything else reads the cache.
    private func rebuildMovements() {
        var all: [Movement] = []
        for job in jobs {
            all.append(contentsOf: Movement.expand(job: job, assignments: assignmentsByJob[job.id] ?? []))
        }
        allMovements = all
    }

    // MARK: Derived collections

    var todaysJobs: [Job] {
        jobs.filter { DateUtil.isToday($0.relevantDateString) }
    }

    /// Today at **movement (load) granularity**: every load whose effective date is
    /// today (so a multi-load job shows each load, and a load with a date override
    /// onto today appears here even if its job sits on another day). Filters
    /// `allMovements` at access time (not baked into the cache) so the "is today"
    /// check stays correct across a midnight rollover while the app is open.
    var todaysMovements: [Movement] {
        allMovements
            .filter { DateUtil.isToday($0.effectiveDate) }
            .sorted(by: Self.movementOrder)
    }

    /// The Schedule, at **movement (load) granularity**: every job's loads
    /// grouped by each load's effective date (a per-load date override moves
    /// that load to its own day). Honours the active filters — type on the job,
    /// status on the movement.
    var movementSchedule: [MovementDateSection] {
        let filtered = allMovements.filter { movement in
            if let typeFilter, movement.job.type != typeFilter { return false }
            if !statusFilter.isEmpty, !statusFilter.contains(movement.status) { return false }
            return true
        }
        let grouped = Dictionary(grouping: filtered) { $0.effectiveDate ?? "" }
        return grouped
            .map { MovementDateSection(dateString: $0.key, movements: $0.value.sorted(by: Self.movementOrder)) }
            .sorted { lhs, rhs in
                // Undated last; otherwise ascending by date.
                switch (DateUtil.date(from: lhs.dateString), DateUtil.date(from: rhs.dateString)) {
                case let (l?, r?): return l < r
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return lhs.dateString < rhs.dateString
                }
            }
    }

    var hasActiveFilters: Bool { typeFilter != nil || !statusFilter.isEmpty }

    func clearFilters() {
        typeFilter = nil
        statusFilter = []
    }

    // MARK: Helpers

    struct MovementDateSection: Identifiable {
        let dateString: String
        let movements: [Movement]
        var id: String { dateString }
    }

    /// Within a day: by job start time, then job title, then load position.
    private static func movementOrder(_ a: Movement, _ b: Movement) -> Bool {
        let ta = a.job.timeStart ?? ""
        let tb = b.job.timeStart ?? ""
        if ta != tb { return ta < tb }
        if a.job.id != b.job.id {
            return a.job.title.localizedCaseInsensitiveCompare(b.job.title) == .orderedAscending
        }
        return a.loadPosition < b.loadPosition
    }

    private static func chronological(_ a: Job, _ b: Job) -> Bool {
        let da = DateUtil.date(from: a.relevantDateString)
        let db = DateUtil.date(from: b.relevantDateString)
        switch (da, db) {
        case let (l?, r?):
            if l != r { return l < r }
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): break
        }
        // Same day: order by start time, then event name.
        let ta = a.timeStart ?? ""
        let tb = b.timeStart ?? ""
        if ta != tb { return ta < tb }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
}
