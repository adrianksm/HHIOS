import SwiftUI

/// A single job rendered as a grouped-list row. No status spine, no tinted
/// chips: a type micro-label + status dot, the title, the destination, one quiet
/// meta line, and the haulier row. The enclosing `List` (.insetGrouped) draws the
/// rounded group + hairline dividers, so the row carries no background of its own.
struct JobCardView: View {
    let job: Job
    /// Rolled up by the parent from the job's per-load assignments (hauliers are
    /// assigned per movement, not at the job level).
    var haulierSummary: HaulierSummary = .none
    /// Today hides the time (it's all today and leads with the item count);
    /// other surfaces keep it at the head of the meta line.
    var showsTime: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TypeLabel(type: job.type)
                if job.isClosed { ArchivedTag() }
                Spacer(minLength: 8)
                StatusDot(status: job.status)
            }

            Text(job.title)
                .font(.dc(17.5, .semibold))
                .tracking(-0.2)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            if let dest = job.destinationLabel {
                Text(dest)
                    .font(.dc(14))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .padding(.top, 3)
            }

            if let meta = metaText {
                Text(meta)
                    .font(.dc(13.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .padding(.top, 10)
            }

            HaulierSummaryLine(summary: haulierSummary, selfArranged: job.isSelfArranged)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .contentShape(Rectangle())
    }

    /// One quiet line: time (optional) · item count · transport.
    private var metaText: String? {
        var parts: [String] = []
        if showsTime, let time = job.timeLabel { parts.append(time) }
        if job.totalFurnitureCount > 0 { parts.append("\(job.totalFurnitureCount) items") }
        if let transport = job.transportSummary { parts.append(transport) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}

#Preview("Cards") {
    let lookup = { (id: Int) in SampleData.hauliers.first { $0.id == id } }
    return List {
        Section {
            ForEach(SampleData.jobs) { job in
                JobCardView(job: job,
                            haulierSummary: .make(job: job,
                                                  assignments: SampleData.assignmentsByJob[job.id] ?? [],
                                                  resolve: lookup))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Theme.card)
            }
        }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Theme.canvas)
}
