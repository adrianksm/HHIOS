import Foundation

/// A single physical load derived from a job's `transport_items`, with any
/// per-movement assignment overlaid. Mirrors the web app's `expandJobsToMovements`:
///
/// - `movementIndex` is the **per-transport ordinal** (the Nth load of that
///   vehicle type) — the stable DB identity, used in API calls.
/// - `loadPosition` is the **global 1…N** position across all of the job's loads,
///   shown only as "load X / Y".
/// - A job with no transport items expands to a single movement
///   (`transportName == nil`, `movementIndex == 1`).
struct Movement: Identifiable, Hashable {
    let job: Job
    let transportName: String?
    let movementIndex: Int
    let totalMovements: Int
    let loadPosition: Int
    let assignment: MovementAssignment?

    var id: String { "\(job.id)|\(transportName ?? "")|\(movementIndex)" }

    /// Real transport load vs the synthetic single movement of a transport-less job.
    var hasTransport: Bool { transportName != nil }

    /// Effective status: per-movement override, else the job's status.
    var status: JobStatus { assignment?.status ?? job.status }

    /// Effective date: per-movement override, else the job's relevant date.
    var effectiveDate: String? { assignment?.date ?? job.relevantDateString }

    var dateOverride: String? { assignment?.date }
    var haulierId: Int? { assignment?.haulierId }
    var notes: String { assignment?.notes ?? "" }

    var loadLabel: String { "Load \(loadPosition) / \(totalMovements)" }
    var transportLabel: String { transportName ?? "No transport" }

    // MARK: Expansion

    /// Expand a job into its movements, overlaying the given assignment rows.
    static func expand(job: Job, assignments: [MovementAssignment]) -> [Movement] {
        func find(_ name: String?, _ index: Int) -> MovementAssignment? {
            assignments.first { $0.transportName == name && $0.movementIndex == index }
        }

        let items = job.transport
        guard !items.isEmpty else {
            return [Movement(job: job, transportName: nil, movementIndex: 1,
                             totalMovements: 1, loadPosition: 1, assignment: find(nil, 1))]
        }

        let total = items.reduce(0) { $0 + max($1.quantity, 1) }
        var ordinals: [String: Int] = [:]
        var loadPosition = 1
        var result: [Movement] = []
        for item in items {
            let qty = max(item.quantity, 1)
            for _ in 0..<qty {
                let index = (ordinals[item.name] ?? 0) + 1
                ordinals[item.name] = index
                result.append(Movement(
                    job: job, transportName: item.name, movementIndex: index,
                    totalMovements: total, loadPosition: loadPosition,
                    assignment: find(item.name, index)
                ))
                loadPosition += 1
            }
        }
        return result
    }
}
