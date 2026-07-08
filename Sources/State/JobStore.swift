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
        if case .idle = phase { await load() }
    }

    func load() async {
        if session?.isDemo == true {
            jobs = Self.visible(SampleData.jobs).sorted(by: Self.chronological)
            assignmentsByJob = SampleData.assignmentsByJob
            phase = .loaded
            return
        }
        guard let client = session?.client else {
            phase = .failed("No server configured.")
            return
        }
        phase = .loading
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
            phase = .loaded
        } catch {
            phase = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
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
        assignmentsByJob[jobId] = assignments
    }

    /// Replace a single job in place after an edit, keeping sort order.
    func replace(_ job: Job) {
        if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[idx] = job
        } else {
            jobs.append(job)
        }
        jobs.sort(by: Self.chronological)
    }

    // MARK: Derived collections

    var todaysJobs: [Job] {
        jobs.filter { DateUtil.isToday($0.relevantDateString) }
    }

    /// Today at **movement (load) granularity**: every load whose effective date is
    /// today (so a multi-load job shows each load, and a load with a date override
    /// onto today appears here even if its job sits on another day).
    var todaysMovements: [Movement] {
        var all: [Movement] = []
        for job in jobs {
            for movement in Movement.expand(job: job, assignments: assignmentsByJob[job.id] ?? []) {
                if DateUtil.isToday(movement.effectiveDate) { all.append(movement) }
            }
        }
        return all.sorted(by: Self.movementOrder)
    }

    /// The Schedule, at **movement (load) granularity**: every job's loads
    /// expanded and grouped by each load's effective date (a per-load date
    /// override moves that load to its own day). Honours the active filters —
    /// type on the job, status on the movement.
    var movementSchedule: [MovementDateSection] {
        var all: [Movement] = []
        for job in jobs {
            if let typeFilter, job.type != typeFilter { continue }
            for movement in Movement.expand(job: job, assignments: assignmentsByJob[job.id] ?? []) {
                if !statusFilter.isEmpty, !statusFilter.contains(movement.status) { continue }
                all.append(movement)
            }
        }
        let grouped = Dictionary(grouping: all) { $0.effectiveDate ?? "" }
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
