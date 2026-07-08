import SwiftUI

struct JobDetailView: View {
    @Environment(Session.self) private var session
    @Environment(JobStore.self) private var store
    @Environment(\.openURL) private var openURL
    let jobId: Int

    @State private var job: Job?
    @State private var related: [Job] = []
    @State private var assignments: [MovementAssignment] = []
    @State private var furnitureOverrides: [MovementFurnitureRow] = []
    @State private var loadError: String?

    /// Loads expanded from the job's transport, with assignments overlaid, and
    /// what furniture sits on each (auto-allocated, overrides honoured), keyed by
    /// `Movement.id`. Cached rather than computed, so a keystroke in the notes
    /// field or an `isSaving` toggle doesn't re-expand/re-allocate on every body
    /// pass — recomputed by `recomputeDerived()` whenever `job`, `assignments`,
    /// or `furnitureOverrides` changes.
    @State private var movements: [Movement] = []
    @State private var allocation: [String: [LineItem]] = [:]

    // Job-level edit state (used for transport-less jobs)
    @State private var status: JobStatus = .pending
    @State private var notes: String = ""
    @State private var haulierId: Int?
    /// Guards only the brief synchronous window between a tap and the optimistic
    /// apply landing — the background PATCH itself never blocks this (a second
    /// edit while a save is in flight is allowed; last-write-wins).
    @State private var isSaving = false
    @State private var savedTick = false

    /// Surfaces every background-save failure (movement, job-level, dates) via
    /// one alert, since all three saves' network calls now run detached from
    /// any sheet/form that could otherwise show an inline error.
    @State private var backgroundSaveError: String?

    // Sheets
    @State private var editingMovement: Movement?
    @State private var showDateEditor = false
    @State private var didAutoOpen = false

    /// True when the job has real transport loads (so we edit per movement).
    private var hasTransportLoads: Bool { job.map { !$0.transport.isEmpty } ?? false }

    var body: some View {
        Form {
            if let job {
                summarySection(job)
                if job.isClosed { archivedNote }
                infoGroup(job)
                mapSection(job)
                if hasTransportLoads {
                    loadsSection
                } else if job.isClosed {
                    closedStatusSection(job)
                } else {
                    editSection(job)
                }
                detailsSection(job)
                contactSection(job)
                relatedSection
            } else if let loadError {
                Section {
                    ErrorState(message: loadError) { Task { await reload() } }
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Theme.card)
            } else {
                Section { LoadingState().frame(height: 160) }
                    .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle(job?.type.label ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !hasTransportLoads, isDirty, !(job?.isClosed ?? false) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                } else if savedTick {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.statusColor(.completed))
                }
            }
        }
        .sheet(item: $editingMovement) { movement in
            // The sheet can only change status/notes/haulier/date, never furniture
            // overrides, so skip the movement-furniture re-fetch on save.
            MovementEditSheet(movement: movement, load: allocation[movement.id] ?? []) { edit in
                saveMovement(movement, edit)
            }
        }
        .sheet(isPresented: $showDateEditor) {
            if let job {
                DateEditSheet(job: job) { deliverDate, collectDate in
                    saveDates(deliverDate: deliverDate, collectDate: collectDate)
                }
            }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { backgroundSaveError != nil },
            set: { if !$0 { backgroundSaveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backgroundSaveError ?? "")
        }
        .task { await reload() }
    }

    // MARK: Loads (per-movement)

    private var loadsSection: some View {
        let closed = job?.isClosed ?? false
        return Section {
            ForEach(movements) { movement in
                if closed {
                    MovementRow(movement: movement,
                                haulier: session.haulier(id: movement.haulierId),
                                load: allocation[movement.id] ?? [],
                                isInteractive: false)
                } else {
                    Button { editingMovement = movement } label: {
                        MovementRow(movement: movement,
                                    haulier: session.haulier(id: movement.haulierId),
                                    load: allocation[movement.id] ?? [])
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        if let haulier = session.haulier(id: movement.haulierId),
                           let digits = WhatsApp.formatUKPhone(haulier.phone) {
                            Button {
                                sendLoadWhatsApp(movement: movement, phoneDigits: digits)
                            } label: {
                                Label("WhatsApp", systemImage: "message.fill")
                            }
                            .tint(Theme.whatsApp)
                        }
                    }
                }
            }
            .listRowBackground(Theme.card)
        } header: {
            Text(movements.count > 1 ? "Loads · \(movements.count)" : "Load")
        } footer: {
            Text(closed
                 ? "Completed in Current-RMS — read-only."
                 : (session.isAdmin
                    ? "Tap a load to set status, haulier, date and notes."
                    : "Tap a load to update status and notes."))
        }
    }

    /// Read-only banner for archived (completed-in-CRMS) jobs.
    private var archivedNote: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.tertiary)
                Text("Completed in Current-RMS · read-only history")
                    .font(.dc(13))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .listRowBackground(Theme.card)
    }

    /// Read-only status / haulier / notes for a closed transport-less job.
    @ViewBuilder
    private func closedStatusSection(_ job: Job) -> some View {
        Section("Status") {
            LabeledContent("Status") { StatusDot(status: job.status) }
            if job.hasHaulier {
                LabeledContent("Haulier") {
                    HaulierTag(name: job.haulierName, colorHex: session.haulier(id: job.haulierId)?.color)
                }
            }
            if let notes = job.notes?.nilIfBlank {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes").font(.dc(12)).foregroundStyle(Theme.tertiary)
                    Text(notes).foregroundStyle(Theme.ink)
                }
            }
        }
        .listRowBackground(Theme.card)
    }

    // MARK: Sections

    private func summarySection(_ job: Job) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                TypeLabel(type: job.type)
                Text(job.title)
                    .font(.dc(25, .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
                HStack(spacing: 7) {
                    StatusDot(status: job.status)
                    Text("·").foregroundStyle(Theme.tertiary)
                    Text(summaryDate(job))
                        .font(.dc(14))
                        .foregroundStyle(Theme.secondary)
                    if job.isSelfArranged {
                        Text("·").foregroundStyle(Theme.tertiary)
                        Text("Self-arranged")
                            .font(.dc(14))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                .padding(.top, 9)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Theme.card)
    }

    /// The plain Time / Where / Weather group — no per-row SF Symbols.
    @ViewBuilder
    private func infoGroup(_ job: Job) -> some View {
        let weather = job.weatherSummary?.nilIfBlank
        if job.timeLabel != nil || job.destinationLabel != nil || weather != nil {
            Section {
                if let time = job.timeLabel {
                    LabeledContent("Time") { Text(time).foregroundStyle(Theme.ink) }
                }
                if let dest = job.destinationLabel {
                    LabeledContent("Where") {
                        Text(dest).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
                    }
                }
                if let weather {
                    LabeledContent("Weather") { Text(weather).foregroundStyle(Theme.ink) }
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    @ViewBuilder
    private func mapSection(_ job: Job) -> some View {
        if job.destination?.nilIfBlank != nil || job.destinationPostcode?.nilIfBlank != nil {
            Section {
                DestinationMap(
                    address: job.destination,
                    postcode: job.destinationPostcode,
                    title: job.title
                )
                .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Theme.card)
        }
    }

    private func editSection(_ job: Job) -> some View {
        Section("Status") {
            Picker("Status", selection: $status) {
                ForEach(JobStatus.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if session.isAdmin {
                Picker("Haulier", selection: $haulierId) {
                    Text("Unassigned").tag(Int?.none)
                    ForEach(session.hauliers) { h in
                        HStack {
                            Circle().fill(Color(hex: h.color, fallback: .gray)).frame(width: 10, height: 10)
                            Text(h.name)
                        }
                        .tag(Int?.some(h.id))
                    }
                }
            } else if job.hasHaulier {
                LabeledContent("Haulier") {
                    HaulierTag(name: job.haulierName, colorHex: session.haulier(id: job.haulierId)?.color)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.dc(12)).foregroundStyle(Theme.tertiary)
                TextField("Add a note…", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .listRowBackground(Theme.card)
    }

    private func detailsSection(_ job: Job) -> some View {
        Section("Details") {
            if !job.furniture.isEmpty {
                DisclosureRow(
                    title: "Furniture",
                    summary: "\(job.totalFurnitureCount) items",
                    items: job.furniture
                )
            }
            if !job.transport.isEmpty {
                DisclosureRow(
                    title: "Transport",
                    summary: job.transportSummary ?? "",
                    items: job.transport
                )
            }
            if let mileage = job.mileage {
                LabeledContent("Mileage", value: "\(mileage.formatted(.number.precision(.fractionLength(0...1)))) mi")
            }
            if session.isAdmin, let price = job.budgetPrice {
                LabeledContent("Budget price", value: price.formatted(.currency(code: "GBP")))
            }
            if let deliver = job.deliverDate, let collect = job.collectDate {
                let window = "\(DateUtil.weekdayDayLabel(from: deliver)) → \(DateUtil.weekdayDayLabel(from: collect))"
                if session.isAdmin {
                    Button { showDateEditor = true } label: {
                        LabeledContent("Hire window") {
                            HStack(spacing: 6) {
                                Text(window)
                                Image(systemName: "pencil")
                            }
                            .foregroundStyle(Theme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    LabeledContent("Hire window") {
                        Text(window).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
        .listRowBackground(Theme.card)
    }

    @ViewBuilder
    private func contactSection(_ job: Job) -> some View {
        if job.contactName?.nilIfBlank != nil || job.contactPhoneDigits != nil {
            Section("Site contact") {
                if let name = job.contactName?.nilIfBlank {
                    LabeledContent("Name", value: name)
                }
                if let digits = job.contactPhoneDigits, let url = URL(string: "tel://\(digits)") {
                    Link(destination: url) {
                        LabeledContent(job.contactPhone ?? digits) {
                            Text("Call").foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        if let sibling = related.first {
            Section("Linked job") {
                NavigationLink(value: sibling.id) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            TypeLabel(type: sibling.type)
                            Text(DateUtil.relativeLabel(from: sibling.relevantDateString))
                                .font(.dc(14))
                                .foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        StatusDot(status: sibling.status)
                    }
                }
            }
            .listRowBackground(Theme.card)
        }
    }

    // MARK: Logic

    private func summaryDate(_ job: Job) -> String {
        let rel = DateUtil.relativeLabel(from: job.relevantDateString)
        let weekday = DateUtil.weekdayDayLabel(from: job.relevantDateString)
        return rel == weekday ? rel : "\(rel) · \(weekday)"
    }

    private var isDirty: Bool {
        guard let job else { return false }
        if status != job.status { return true }
        if notes != (job.notes ?? "") { return true }
        if session.isAdmin, haulierId != job.haulierId { return true }
        return false
    }

    private func apply(_ job: Job) {
        self.job = job
        status = job.status
        notes = job.notes ?? ""
        haulierId = job.haulierId
        recomputeDerived()
    }

    /// Rebuilds `movements`/`allocation` from the current `job`/`assignments`/
    /// `furnitureOverrides`. Call after any of those three change.
    private func recomputeDerived() {
        guard let job else {
            movements = []
            allocation = [:]
            return
        }
        let expanded = Movement.expand(job: job, assignments: assignments)
        movements = expanded
        allocation = FurnitureAllocator.allocate(
            job: job, movements: expanded,
            capacities: session.config.furnitureCapacities,
            overrides: furnitureOverrides
        )
    }

    private func reload(force: Bool = false) async {
        // Freshness-window fast path: a recent cached detail (job + related +
        // assignments + furniture overrides) means zero network — reopening a
        // job just viewed is instant. Bypassed by `force` and by demo mode
        // (demo never reads/writes this cache).
        if !force, !session.isDemo,
           let cached = store.detail(for: jobId),
           Date().timeIntervalSince(cached.fetchedAt) < JobStore.detailCacheWindow {
            related = cached.related
            assignments = cached.assignments
            furnitureOverrides = cached.furnitureOverrides
            apply(cached.job)
            loadError = nil
            autoOpenSheetIfRequested()
            return
        }

        // Instant render from cache, then refresh from the server.
        if job == nil, let cached = store.jobs.first(where: { $0.id == jobId }) {
            apply(cached)
        }
        // Seed loads from the list's cached assignments (covers archived/closed jobs,
        // whose live movement endpoints 404 — the list already merged their history).
        if assignments.isEmpty {
            assignments = store.assignments(for: jobId)
            recomputeDerived()
        }
        if session.isDemo {
            assignments = store.assignments(for: jobId)
            furnitureOverrides = []
            recomputeDerived()
            autoOpenSheetIfRequested()
            return
        }
        guard let client = session.client else { return }

        // All four reads are keyed only by jobId and independent of each other,
        // so fire them concurrently rather than paying four serial round-trips.
        async let jobResult = client.job(id: jobId)
        async let relatedResult = client.relatedJob(id: jobId)
        async let movementsResult = client.movements(jobId: jobId)
        async let furnitureResult = client.movementFurniture(jobId: jobId)

        var jobFetchSucceeded = false
        do {
            let fresh = try await jobResult
            if force || !isDirty || job == nil { apply(fresh) } else { self.job = fresh; recomputeDerived() }
            loadError = nil
            jobFetchSucceeded = true
        } catch {
            if job == nil { loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription }
        }
        related = (try? await relatedResult) ?? []
        if let fresh = try? await movementsResult {
            assignments = fresh
            store.setAssignments(fresh, for: jobId)
            recomputeDerived()
        }
        if let furn = try? await furnitureResult {
            furnitureOverrides = furn
            recomputeDerived()
        }
        // Only cache when the job itself genuinely refreshed — never write a
        // stale seeded/list-cache job back out with a fresh timestamp.
        if jobFetchSucceeded, let job {
            store.setDetail(
                JobStore.JobDetail(job: job, related: related, assignments: assignments,
                                    furnitureOverrides: furnitureOverrides, fetchedAt: Date()),
                for: jobId
            )
        }
        autoOpenSheetIfRequested()
    }

    /// After a date save, only this job's dates and its related job's dates
    /// changed (assignments/furniture overrides are untouched — see
    /// `APIClient.updateDates`), so refresh just those two GETs instead of the
    /// full 4-GET `reload(force:)`.
    private func refreshDates() async {
        if session.isDemo {
            // Demo's DateEditSheet doesn't mutate sample data; mirror reload()'s
            // existing demo no-op path exactly.
            await reload(force: true)
            return
        }
        guard let client = session.client else { return }
        async let jobResult = client.job(id: jobId)
        async let relatedResult = client.relatedJob(id: jobId)
        if let fresh = try? await jobResult {
            apply(fresh)
            store.replace(fresh)
        }
        // Matches reload()'s existing behaviour: `related` is local display state
        // only — reload() doesn't push related jobs into the store either.
        related = (try? await relatedResult) ?? []
    }

    /// `-openSheet movement|dates` launch arg auto-presents a sheet (screenshots).
    private func autoOpenSheetIfRequested() {
        guard !didAutoOpen else { return }
        didAutoOpen = true
        switch UserDefaults.standard.string(forKey: "openSheet") {
        case "movement": editingMovement = movements.first { $0.hasTransport }
        case "dates": showDateEditor = true
        default: break
        }
    }

    /// Refreshes assignments (and, by default, movement-furniture overrides).
    /// Pass `includeFurniture: false` when the caller knows furniture can't have
    /// changed (e.g. a movement save, which only ever touches status/notes/
    /// haulier/date) to skip that GET.
    private func loadMovements(includeFurniture: Bool = true) async {
        guard hasTransportLoads else {
            assignments = []
            furnitureOverrides = []
            recomputeDerived()
            return
        }
        if session.isDemo {
            assignments = store.assignments(for: jobId)
            furnitureOverrides = []
            recomputeDerived()
            return
        }
        guard let client = session.client else { return }
        if let fresh = try? await client.movements(jobId: jobId) {
            assignments = fresh
            // Keep the list cards' haulier roll-up in sync with this job's loads.
            store.setAssignments(fresh, for: jobId)
            recomputeDerived()
        }
        guard includeFurniture else { return }
        if let furn = try? await client.movementFurniture(jobId: jobId) {
            furnitureOverrides = furn
            recomputeDerived()
        }
    }

    private func applyUpdated(_ updated: Job) {
        apply(updated)
        store.replace(updated)
    }

    /// Resolves an `APIClient.HaulierChange` to the concrete value to store
    /// locally: the new id when `.set`, otherwise whatever was already there.
    private func resolvedHaulierId(_ change: APIClient.HaulierChange, current: Int?) -> Int? {
        if case .set(let value) = change { return value }
        return current
    }

    /// Resolves an `APIClient.DateChange` to the concrete date string to store
    /// locally: the new value when `.set` (including clearing to nil), otherwise
    /// whatever was already there.
    private func resolvedDate(_ change: APIClient.DateChange, current: String?) -> String? {
        if case .set(let value) = change { return value }
        return current
    }

    /// Quick-send this load's details to its assigned driver on WhatsApp.
    private func sendLoadWhatsApp(movement: Movement, phoneDigits: String) {
        guard let job else { return }
        let message = WhatsApp.message(
            jobType: job.type,
            eventName: job.eventName,
            dateString: movement.effectiveDate,
            transportName: movement.transportName,
            loadPosition: movement.loadPosition,
            totalMovements: movement.totalMovements,
            contactName: job.contactName,
            contactPhone: job.contactPhone,
            destination: job.destination,
            postcode: job.destinationPostcode,
            items: allocation[movement.id] ?? [],
            notes: movement.notes
        )
        if let url = WhatsApp.url(phoneDigits: phoneDigits, message: message) {
            openURL(url)
        }
    }

    /// Job-level save for transport-less jobs. Optimistic: applies the edit and
    /// dismisses the toolbar's Save button instantly via `Job.withLocalEdits`;
    /// the PATCH runs in a detached background `Task` and rolls back to the
    /// snapshotted job on failure.
    private func save() async {
        guard isDirty, !isSaving, let current = job else { return }
        isSaving = true
        // A post-save reopen should see the change, not a stale cached detail.
        store.invalidateDetail(for: jobId)

        // Demo mode: apply the edit locally, no network.
        if session.isDemo {
            let updated = current.withLocalEdits(
                status: status, notes: notes,
                haulierId: haulierId, haulierName: session.haulier(id: haulierId)?.name
            )
            apply(updated)
            store.replace(updated)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSaving = false
            withAnimation { savedTick = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { savedTick = false }
            return
        }

        guard let client = session.client else { isSaving = false; return }

        // Snapshot for rollback, then apply optimistically.
        let previousJob = current
        let newStatus = status
        let newNotes = notes
        let newHaulierId = haulierId
        let haulierChange: APIClient.HaulierChange = session.isAdmin ? .set(newHaulierId) : .unchanged

        let optimistic = current.withLocalEdits(
            status: newStatus, notes: newNotes,
            haulierId: newHaulierId, haulierName: session.haulier(id: newHaulierId)?.name
        )
        apply(optimistic)
        store.replace(optimistic)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        isSaving = false

        Task {
            do {
                let updated = try await client.updateJob(
                    id: jobId, status: newStatus, notes: newNotes, haulier: haulierChange
                )
                applyUpdated(updated)
            } catch {
                apply(previousJob)
                store.replace(previousJob)
                backgroundSaveError = ((error as? APIError)?.errorDescription ?? error.localizedDescription)
                    + " Your change was undone."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }

        withAnimation { savedTick = true }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { savedTick = false }
    }

    /// Applies a `MovementEditSheet` save. Optimistic outside demo mode: upserts
    /// the local `MovementAssignment` row for (transportName, movementIndex) so
    /// the load's status/notes/haulier/date reflect instantly, then PATCHes in a
    /// detached background `Task`. On success, converges to server truth via
    /// `loadMovements`; on failure, rolls back to the snapshot taken here.
    private func saveMovement(_ movement: Movement, _ edit: MovementEdit) {
        guard let transportName = movement.transportName else { return }
        // A post-save reopen should see the change, not a stale cached detail.
        store.invalidateDetail(for: jobId)

        // Demo: apply as a job-level edit, exactly mirroring the sheet's former
        // demo branch (demo sample jobs are treated as single-movement, so a
        // movement edit maps onto the job itself) — no assignment upsert, no
        // network.
        if session.isDemo {
            let demoHaulierId = resolvedHaulierId(edit.haulier, current: movement.haulierId)
            let updated = movement.job.withLocalEdits(
                status: edit.status, notes: edit.notes,
                haulierId: demoHaulierId, haulierName: session.haulier(id: demoHaulierId)?.name
            )
            applyUpdated(updated)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }

        guard let client = session.client, let job else { return }

        // Snapshot for rollback.
        let previousJob = job
        let previousAssignments = assignments
        let previousStoreAssignments = store.assignments(for: jobId)

        // Optimistic upsert: update the matching row, or synthesize a placeholder
        // (server-owned fields get sensible nil/derived values — the follow-up
        // GET on success replaces this row with server truth either way).
        let existing = assignments.first {
            $0.transportName == transportName && $0.movementIndex == movement.movementIndex
        }
        let haulierId = resolvedHaulierId(edit.haulier, current: existing?.haulierId)
        let dateValue = resolvedDate(edit.date, current: existing?.date)
        let haulierName = haulierId == nil ? nil : (session.haulier(id: haulierId)?.name ?? existing?.haulierName)
        let haulierColor = haulierId == nil ? nil : (session.haulier(id: haulierId)?.color ?? existing?.haulierColor)
        let optimisticRow = MovementAssignment(
            id: existing?.id ?? 0,
            jobId: jobId,
            transportName: transportName,
            movementIndex: movement.movementIndex,
            haulierId: haulierId,
            notes: edit.notes,
            statusRaw: edit.status.rawValue,
            date: dateValue,
            haulierName: haulierName,
            haulierColor: haulierColor
        )
        if let idx = assignments.firstIndex(where: {
            $0.transportName == transportName && $0.movementIndex == movement.movementIndex
        }) {
            assignments[idx] = optimisticRow
        } else {
            assignments.append(optimisticRow)
        }
        store.setAssignments(assignments, for: jobId)
        recomputeDerived()

        Task {
            do {
                let updatedJob = try await client.updateMovement(
                    jobId: jobId, transportName: transportName, movementIndex: movement.movementIndex,
                    status: edit.status, notes: edit.notes,
                    haulier: edit.haulier, date: edit.date,
                    isAdmin: session.isAdmin
                )
                applyUpdated(updatedJob)
                await loadMovements(includeFurniture: false)
            } catch {
                assignments = previousAssignments
                store.setAssignments(previousStoreAssignments, for: jobId)
                apply(previousJob)
                store.replace(previousJob)
                recomputeDerived()
                backgroundSaveError = ((error as? APIError)?.errorDescription ?? error.localizedDescription)
                    + " Your change was undone."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    /// Applies a `DateEditSheet` save. Not optimistic — `Job` has no local-edit
    /// helper for dates (they're admin-rare) — so the UI keeps showing the old
    /// dates until the PATCH lands and `refreshDates()` pulls server truth.
    private func saveDates(deliverDate: String, collectDate: String) {
        // A post-save reopen should see the change, not a stale cached detail.
        store.invalidateDetail(for: jobId)
        if session.isDemo {
            // Demo's DateEditSheet doesn't mutate sample data; mirror
            // refreshDates()'s existing demo no-op path.
            Task { await refreshDates() }
            return
        }
        guard let client = session.client else { return }
        Task {
            do {
                try await client.updateDates(jobId: jobId, deliverDate: deliverDate, collectDate: collectDate)
                await refreshDates()
            } catch {
                backgroundSaveError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

/// One load row inside the job detail's Loads section.
private struct MovementRow: View {
    let movement: Movement
    let haulier: Haulier?
    let load: [LineItem]
    var isInteractive: Bool = true

    var body: some View {
        HStack(spacing: 13) {
            Text("\(movement.loadPosition)")
                .font(.dc(17, .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.tertiary)
                .frame(width: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(movement.transportLabel)
                    .font(.dc(15, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                loadContents
                HStack(spacing: 12) {
                    StatusDot(status: movement.status)
                    HaulierTag(name: haulier?.name, colorHex: haulier?.color)
                    if let override = movement.dateOverride {
                        Text(DateUtil.weekdayDayLabel(from: override))
                            .font(.dc(12.5, .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            Spacer(minLength: 0)
            if isInteractive {
                Image(systemName: "chevron.right")
                    .font(.dc(13, .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var loadContents: some View {
        if load.isEmpty {
            Text("Empty load")
                .font(.dc(12.5))
                .foregroundStyle(Theme.tertiary)
        } else {
            Text(load.map { "\($0.quantity)× \($0.name)" }.joined(separator: ", "))
                .font(.dc(12.5))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(2)
        }
    }
}

/// Collapsible list of line items (furniture or transport). Plain rows, no icon.
private struct DisclosureRow: View {
    let title: String
    let summary: String
    let items: [LineItem]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(items) { item in
                HStack {
                    Text(item.name).font(.dc(14.5)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("× \(item.quantity)").font(.dc(14, .semibold)).foregroundStyle(Theme.tertiary)
                }
            }
        } label: {
            HStack {
                Text(title).foregroundStyle(Theme.ink)
                Spacer()
                Text(summary).foregroundStyle(Theme.tertiary).font(.dc(14))
            }
        }
    }
}
