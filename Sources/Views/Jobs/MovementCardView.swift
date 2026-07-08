import SwiftUI

/// One load (movement) rendered as a grouped-list row for the Schedule. Mirrors
/// the job card's language, scoped to a single load: its own status dot, its
/// haulier, and a quiet meta line carrying the load position + transport.
struct MovementCardView: View {
    let movement: Movement
    /// Resolved by the parent from the Session cache (haulier colour/name).
    var haulier: Haulier? = nil
    var showsTime: Bool = true

    private var job: Job { movement.job }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TypeLabel(type: job.type)
                if job.isClosed { ArchivedTag() }
                Spacer(minLength: 8)
                StatusDot(status: movement.status)
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

            haulierLine
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var haulierLine: some View {
        if let haulier {
            HaulierSummaryLine(summary: HaulierSummary(
                chips: [.init(name: haulier.name, colorHex: haulier.color)],
                assignedLoads: 1, totalLoads: 1))
        } else {
            HaulierSummaryLine(summary: .none, selfArranged: job.isSelfArranged)
        }
    }

    private var metaText: String? {
        var parts: [String] = []
        if showsTime, let time = job.timeLabel { parts.append(time) }
        if movement.hasTransport {
            if movement.totalMovements > 1 {
                parts.append("Load \(movement.loadPosition)/\(movement.totalMovements)")
            }
            parts.append(movement.transportLabel)
        } else if job.totalFurnitureCount > 0 {
            parts.append("\(job.totalFurnitureCount) items")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}
