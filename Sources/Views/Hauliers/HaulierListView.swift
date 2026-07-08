import SwiftUI

struct HaulierListView: View {
    @Environment(Session.self) private var session
    @Environment(JobStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if session.hauliers.isEmpty {
                    ContentUnavailableView("No hauliers", systemImage: "person.2.slash",
                                           description: Text("Hauliers added in the web app appear here."))
                } else {
                    List {
                        ForEach(session.hauliers) { haulier in
                            NavigationLink(value: haulier.id) {
                                HaulierRow(haulier: haulier, jobCount: jobCount(for: haulier.id))
                            }
                            .listRowBackground(Theme.card)
                            .listRowSeparatorTint(Theme.rowDivider)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Theme.canvas)
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Hauliers")
            .refreshable { await session.loadReferenceData() }
            .navigationDestination(for: Int.self) { id in
                if let haulier = session.haulier(id: id) {
                    HaulierDetailView(haulier: haulier)
                }
            }
        }
    }

    private func jobCount(for id: Int) -> Int {
        store.jobs.filter { $0.haulierId == id }.count
    }
}

private struct HaulierRow: View {
    let haulier: Haulier
    let jobCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: haulier.color, fallback: .gray))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(haulier.name).font(.dc(16, .medium)).foregroundStyle(Theme.ink)
                if let phone = haulier.phone?.nilIfBlank {
                    Text(phone).font(.dc(13)).foregroundStyle(Theme.tertiary)
                }
            }
            Spacer()
            if jobCount > 0 {
                Text("\(jobCount)")
                    .font(.dc(13.5, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A haulier's assigned jobs, drawn from the shared store.
struct HaulierDetailView: View {
    @Environment(JobStore.self) private var store
    let haulier: Haulier

    private var jobs: [Job] {
        store.jobs.filter { $0.haulierId == haulier.id }
    }

    var body: some View {
        Group {
            if jobs.isEmpty {
                ContentUnavailableView("No assigned jobs", systemImage: "tray",
                                       description: Text("\(haulier.name) has no jobs in the current window."))
            } else {
                List {
                    if let phone = haulier.phoneDigits, let url = URL(string: "tel://\(phone)") {
                        Section {
                            Link(destination: url) {
                                LabeledContent(haulier.phone ?? phone) {
                                    Text("Call").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .listRowBackground(Theme.card)
                    }
                    Section("Assigned jobs") {
                        ForEach(jobs) { JobRow(job: $0) }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.canvas)
            }
        }
        .background(Theme.canvas)
        .navigationTitle(haulier.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Int.self) { JobDetailView(jobId: $0) }
    }
}
