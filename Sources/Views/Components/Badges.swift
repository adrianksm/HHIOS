import SwiftUI

// MARK: - Status

/// Status as a 7pt coloured dot + label — never a filled capsule.
/// `compact` renders the dot alone (used in tight rows).
struct StatusDot: View {
    let status: JobStatus
    var compact: Bool = false

    var body: some View {
        let color = Theme.statusColor(status)
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            if !compact {
                Text(status.label)
                    .font(.dc(12.5, .semibold))
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - Type

/// Delivery / Collection as a small uppercase, letter-spaced micro-label.
/// No pill, no icon.
struct TypeLabel: View {
    let type: JobType

    var body: some View {
        Text(type.label.uppercased())
            .font(.dc(10.5, .bold))
            .kerning(1)
            .foregroundStyle(Theme.typeColor(type))
    }
}

// MARK: - Archived

/// A quiet marker for archived (completed-in-CRMS) jobs, shown read-only.
struct ArchivedTag: View {
    var body: some View {
        Text("ARCHIVED")
            .font(.dc(10.5, .bold))
            .kerning(1)
            .foregroundStyle(Theme.tertiary)
    }
}

// MARK: - Haulier

/// A single haulier dot with a 2pt ring in the surface colour, so overlapping
/// dots read as separate discs.
private struct HaulierDot: View {
    let colorHex: String?
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex, fallback: .gray))
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Theme.card, lineWidth: 2))
    }
}

/// The job-card haulier row: bare overlapping dots + a name, or an unassigned /
/// self-arranged marker. No capsule.
struct HaulierSummaryLine: View {
    let summary: HaulierSummary
    var selfArranged: Bool = false

    var body: some View {
        if summary.isEmpty {
            if selfArranged {
                marker(dashed: false, dotted: true, text: "Self-arranged · customer collecting")
            } else {
                marker(dashed: true, dotted: false, text: "Unassigned · needs a haulier")
            }
        } else {
            HStack(spacing: 6) {
                HStack(spacing: -3) {
                    ForEach(Array(summary.chips.prefix(3).enumerated()), id: \.offset) { _, chip in
                        HaulierDot(colorHex: chip.colorHex)
                    }
                }
                Text(nameText)
                    .font(.dc(13, .medium))
                    .foregroundStyle(Theme.haulierName)
                    .lineLimit(1)
                if summary.isPartial {
                    Text("\(summary.assignedLoads)/\(summary.totalLoads)")
                        .font(.dc(12, .medium))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }

    private var nameText: String {
        switch summary.chips.count {
        case 1:  return summary.chips[0].name
        case 2:  return "\(summary.chips[0].name) + \(summary.chips[1].name)"
        default: return "\(summary.chips.count) hauliers"
        }
    }

    /// The unassigned (dashed ring) / self-arranged (ringed dot) marker.
    @ViewBuilder
    private func marker(dashed: Bool, dotted: Bool, text: String) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .strokeBorder(Theme.tertiary,
                                  style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [2.5] : []))
                    .frame(width: 10, height: 10)
                if dotted {
                    Circle().fill(Theme.tertiary).frame(width: 3, height: 3)
                }
            }
            Text(text)
                .font(.dc(13, .medium))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
        }
    }
}

/// A single haulier dot + name for detail rows, or a muted dashed "Unassigned".
struct HaulierTag: View {
    let name: String?
    let colorHex: String?

    var body: some View {
        HStack(spacing: 7) {
            if let name, !name.isEmpty {
                HaulierDot(colorHex: colorHex, size: 9)
                Text(name)
                    .font(.dc(13, .medium))
                    .foregroundStyle(Theme.haulierName)
            } else {
                Circle()
                    .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [2.5]))
                    .frame(width: 9, height: 9)
                Text("Unassigned")
                    .font(.dc(13, .medium))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }
}

#Preview("Badges") {
    VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 14) { StatusDot(status: .pending); StatusDot(status: .booked); StatusDot(status: .completed) }
        HStack(spacing: 14) { TypeLabel(type: .delivery); TypeLabel(type: .collection) }
        HaulierSummaryLine(summary: HaulierSummary(chips: [.init(name: "Glencourt", colorHex: "#e32400")], assignedLoads: 1, totalLoads: 1))
        HaulierSummaryLine(summary: HaulierSummary(chips: [.init(name: "Glencourt", colorHex: "#e32400"), .init(name: "Essex Hay", colorHex: "#371a94")], assignedLoads: 2, totalLoads: 2))
        HaulierSummaryLine(summary: .none)
        HaulierSummaryLine(summary: .none, selfArranged: true)
        HaulierTag(name: "Exmor Hay", colorHex: "#77bb41")
    }
    .padding()
    .background(Theme.canvas)
}
