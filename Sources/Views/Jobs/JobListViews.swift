import SwiftUI

// MARK: - Shared rows

/// A tappable job row that resolves the haulier roll-up from the store and
/// navigates to the job detail. The enclosing `.insetGrouped` List draws the
/// rounded group + hairline dividers.
struct JobRow: View {
    @Environment(Session.self) private var session
    @Environment(JobStore.self) private var store
    let job: Job
    var showsDate: Bool = true

    var body: some View {
        NavigationLink(value: job.id) {
            JobCardView(job: job, haulierSummary: summary, showsTime: showsDate)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Theme.card)
        .listRowSeparatorTint(Theme.rowDivider)
    }

    private var summary: HaulierSummary {
        HaulierSummary.make(job: job,
                            assignments: store.assignments(for: job.id),
                            resolve: { session.haulier(id: $0) })
    }
}

/// A tappable row for one load on the Schedule.
struct MovementScheduleRow: View {
    @Environment(Session.self) private var session
    let movement: Movement
    var showsTime: Bool = true

    var body: some View {
        NavigationLink(value: movement.job.id) {
            MovementCardView(movement: movement, haulier: resolvedHaulier, showsTime: showsTime)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Theme.card)
        .listRowSeparatorTint(Theme.rowDivider)
    }

    private var resolvedHaulier: Haulier? {
        let id = movement.haulierId ?? (movement.hasTransport ? nil : movement.job.haulierId)
        return session.haulier(id: id)
    }
}

// MARK: - Section header style

/// The tertiary, uppercase, letter-spaced section label used across the app.
private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.dc(13, .semibold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(Theme.tertiary)
    }
}

// MARK: - Today

struct TodayView: View {
    @Environment(Session.self) private var session
    @Environment(JobStore.self) private var store
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch store.phase {
                case .loading where store.jobs.isEmpty:
                    LoadingState()
                case .failed(let message) where store.jobs.isEmpty:
                    ErrorState(message: message) { Task { await store.load() } }
                default:
                    content
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Int.self) { JobDetailView(jobId: $0) }
        }
        .onAppear {
            // `-startJob <id>` launch arg deep-links to a detail (screenshots).
            let j = UserDefaults.standard.integer(forKey: "startJob")
            if j > 0, path.isEmpty { path.append(j) }
        }
    }

    @ViewBuilder
    private var content: some View {
        let movements = store.todaysMovements
        if movements.isEmpty {
            ScrollView {
                ContentUnavailableView {
                    Label("Nothing scheduled today", systemImage: "checkmark.circle")
                } description: {
                    Text(DateUtil.fullLabel(from: DateUtil.todayString()))
                }
                .padding(.top, 80)
            }
            .background(Theme.canvas)
            .refreshable { await store.load() }
        } else {
            List {
                Section {
                    ForEach(movements) { MovementScheduleRow(movement: $0) }
                } header: {
                    SectionLabel(DateUtil.fullLabel(from: DateUtil.todayString()))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .refreshable { await store.load() }
        }
    }
}

// MARK: - Schedule

struct ScheduleView: View {
    @Environment(JobStore.self) private var store
    /// Bumped by the "Today" toolbar button to scroll back to today's section.
    @State private var jumpToToday = 0

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                switch store.phase {
                case .loading where store.jobs.isEmpty:
                    LoadingState()
                case .failed(let message) where store.jobs.isEmpty:
                    ErrorState(message: message) { Task { await store.load() } }
                default:
                    content
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu(store: store) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") { jumpToToday += 1 }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(for: Int.self) { JobDetailView(jobId: $0) }
        }
    }

    @ViewBuilder
    private var content: some View {
        let sections = store.movementSchedule
        if sections.isEmpty {
            ScrollView {
                ContentUnavailableView {
                    Label("No loads", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text(store.hasActiveFilters ? "No loads match the current filters." : "Nothing upcoming.")
                } actions: {
                    if store.hasActiveFilters {
                        Button("Clear filters") { store.clearFilters() }
                    }
                }
                .padding(.top, 80)
            }
            .background(Theme.canvas)
            .refreshable { await store.load() }
        } else {
            ScrollViewReader { proxy in
                List {
                    Section { loadEarlierButton }
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.movements) { MovementScheduleRow(movement: $0) }
                        } header: {
                            sectionHeader(section)
                        }
                        .id(section.dateString)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.canvas)
                .refreshable { await store.load() }
                // Land on today (past dates sit above — scroll up for history).
                .onAppear { scrollToToday(proxy, sections, animated: false) }
                .onChange(of: jumpToToday) { scrollToToday(proxy, sections, animated: true) }
            }
        }
    }

    /// Today's section if present, else the first upcoming one, else the last.
    private func scrollToToday(_ proxy: ScrollViewProxy,
                               _ sections: [JobStore.MovementDateSection],
                               animated: Bool) {
        let todayStr = DateUtil.todayString()
        let target: String? = {
            if sections.contains(where: { $0.dateString == todayStr }) { return todayStr }
            if let today = DateUtil.date(from: todayStr),
               let upcoming = sections.first(where: { ($0.dateString.isEmpty ? nil : DateUtil.date(from: $0.dateString)).map { $0 >= today } ?? false }) {
                return upcoming.dateString
            }
            return sections.last?.dateString
        }()
        guard let target else { return }
        DispatchQueue.main.async {
            if animated { withAnimation { proxy.scrollTo(target, anchor: .top) } }
            else { proxy.scrollTo(target, anchor: .top) }
        }
    }

    /// Tap to fetch another 2 weeks of history (sits above today — scroll up to it).
    @ViewBuilder
    private var loadEarlierButton: some View {
        Button { Task { await store.loadEarlier() } } label: {
            HStack(spacing: 8) {
                if store.isLoadingMore {
                    ProgressView().tint(Theme.accent)
                } else {
                    Image(systemName: "arrow.up").font(.dc(13, .semibold))
                }
                Text(store.isLoadingMore ? "Loading earlier jobs…" : "Load earlier 2 weeks")
                    .font(.dc(14, .medium))
                Spacer()
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isLoadingMore)
        .listRowBackground(Theme.card)
    }

    /// Relative label + date + plain count; today's label in accent.
    private func sectionHeader(_ section: JobStore.MovementDateSection) -> some View {
        let isToday = DateUtil.isToday(section.dateString)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(DateUtil.relativeLabel(from: section.dateString))
                .font(.dc(15, .bold))
                .tracking(-0.1)
                .foregroundStyle(isToday ? Theme.accent : Theme.ink)
            Text(DateUtil.weekdayDayLabel(from: section.dateString))
                .font(.dc(12.5))
                .foregroundStyle(Theme.tertiary)
            Spacer(minLength: 4)
            Text("\(section.movements.count)")
                .font(.dc(12.5, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.tertiary)
        }
        .textCase(nil)
    }

    private func filterMenu(store: JobStore) -> some View {
        @Bindable var store = store
        return Menu {
            Picker("Type", selection: Binding(
                get: { store.typeFilter },
                set: { store.typeFilter = $0 }
            )) {
                Text("All types").tag(JobType?.none)
                ForEach(JobType.allCases) { Text($0.label).tag(JobType?.some($0)) }
            }

            Section("Status") {
                ForEach(JobStatus.allCases) { status in
                    Button {
                        if store.statusFilter.contains(status) { store.statusFilter.remove(status) }
                        else { store.statusFilter.insert(status) }
                    } label: {
                        Label(status.label, systemImage: store.statusFilter.contains(status) ? "checkmark" : "")
                    }
                }
            }

            if store.hasActiveFilters {
                Button("Clear filters", role: .destructive) { store.clearFilters() }
            }
        } label: {
            Image(systemName: store.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Shared states

struct RefreshButton: View {
    let store: JobStore
    var body: some View {
        Button { Task { await store.load() } } label: {
            if store.isLoading {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(store.isLoading)
    }
}

struct LoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading jobs…").font(.footnote).foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}

struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load jobs", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry).buttonStyle(.borderedProminent)
        }
    }
}
