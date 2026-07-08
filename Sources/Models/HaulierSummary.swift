import Foundation

/// A rolled-up view of who is assigned to a job's loads, for the summary cards.
///
/// Hauliers are assigned **per load** (movement). A card therefore summarises:
/// the distinct hauliers across all loads, and how many loads are assigned.
struct HaulierSummary: Equatable {
    struct Chip: Equatable, Hashable {
        let name: String
        let colorHex: String?
    }

    var chips: [Chip]      // distinct assigned hauliers, in load order
    var assignedLoads: Int
    var totalLoads: Int

    static let none = HaulierSummary(chips: [], assignedLoads: 0, totalLoads: 0)

    var isEmpty: Bool { chips.isEmpty }
    var isPartial: Bool { !chips.isEmpty && assignedLoads < totalLoads }

    /// Build a summary from a job + its per-load assignments, resolving names and
    /// colours from the haulier cache (falling back to the joined fields on the
    /// assignment, then to the job-level haulier for transport-less jobs).
    static func make(job: Job, assignments: [MovementAssignment], resolve: (Int) -> Haulier?) -> HaulierSummary {
        let movements = Movement.expand(job: job, assignments: assignments)
        let total = movements.count

        var chips: [Chip] = []
        var seen = Set<Int>()
        var assigned = 0
        for movement in movements {
            guard let hid = movement.assignment?.haulierId else { continue }
            assigned += 1
            if seen.insert(hid).inserted {
                let name = movement.assignment?.haulierName ?? resolve(hid)?.name ?? "Assigned"
                let color = movement.assignment?.haulierColor ?? resolve(hid)?.color
                chips.append(Chip(name: name, colorHex: color))
            }
        }

        // Fall back to the job-level haulier ONLY for transport-less jobs (those
        // are assigned at the job level). Transport jobs are assigned per load, so
        // empty chips genuinely means "unassigned" — never borrow a stale
        // job_details.haulier_id and mislabel the loads as fully assigned.
        if chips.isEmpty, job.transport.isEmpty, let jid = job.haulierId {
            let name = job.haulierName ?? resolve(jid)?.name ?? "Assigned"
            let color = resolve(jid)?.color
            return HaulierSummary(chips: [Chip(name: name, colorHex: color)],
                                  assignedLoads: total, totalLoads: total)
        }

        return HaulierSummary(chips: chips, assignedLoads: assigned, totalLoads: total)
    }
}
