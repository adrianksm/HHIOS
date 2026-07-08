import Foundation

/// Computes what furniture sits on each load of a job — a faithful port of the
/// web app's `allocateFurniture` (utils.js).
///
/// Model: each load = 1.0 of capacity. A unit of furniture `f` on transport `t`
/// consumes `1 / capacity[t][f]` of the load; a load is full at 1.0. Loads with
/// a manual override are "pinned" (fixed); the rest auto-fill from the remaining
/// pool, heaviest-per-unit first. Furniture with no defined capacity is taken
/// whole onto the first load that sees it (consuming no fraction).
enum FurnitureAllocator {

    /// Capacity key = first whitespace-delimited word of the transport, uppercased
    /// ("HGV Delivery" → "HGV", "LGV Collection 7.5T" → "LGV").
    static func normalizeKey(_ name: String?) -> String {
        guard let first = name?.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).first else { return "" }
        return first.uppercased()
    }

    static func capacity(_ capacities: [String: [String: Double]]?,
                         transport: String?, furniture: String) -> Double? {
        guard let capacities else { return nil }
        guard let row = capacities[normalizeKey(transport)] else { return nil }
        guard let v = row[furniture], v.isFinite, v > 0 else { return nil }
        return v
    }

    /// Returns each movement's allocated items, keyed by the movement's id
    /// (`Movement.id`). Overrides pin a load; everything else auto-fills.
    static func allocate(job: Job,
                         movements: [Movement],
                         capacities: [String: [String: Double]]?,
                         overrides: [MovementFurnitureRow]) -> [String: [LineItem]] {
        // Match overrides to movements by (transport_name, movement_index).
        func key(_ transport: String?, _ index: Int) -> String { "\(transport ?? "")|\(index)" }
        let validKeys = Set(movements.map { key($0.transportName, $0.movementIndex) })

        var result: [String: [LineItem]] = [:]              // movement.id -> items
        var pinnedKeys = Set<String>()
        var pinnedTotals: [String: Int] = [:]

        // movement.id is keyed the same way (transport|index), so map override key → movement.id.
        let movementByKey = Dictionary(uniqueKeysWithValues:
            movements.map { (key($0.transportName, $0.movementIndex), $0.id) })

        for row in overrides where validKeys.contains(key(row.transportName, row.movementIndex)) {
            let k = key(row.transportName, row.movementIndex)
            guard let movId = movementByKey[k] else { continue }
            pinnedKeys.insert(k)
            result[movId, default: []].append(LineItem(name: row.furnitureName, quantity: row.quantity))
            pinnedTotals[row.furnitureName, default: 0] += max(0, row.quantity)
        }

        // Remaining pool = job furniture minus what pins already carry.
        var pool: [(name: String, quantity: Int)] = job.furniture.map {
            (name: $0.name, quantity: max(0, $0.quantity - (pinnedTotals[$0.name] ?? 0)))
        }.filter { $0.quantity > 0 }

        for movement in movements {
            let k = key(movement.transportName, movement.movementIndex)
            if pinnedKeys.contains(k) { continue }

            var remaining = 1.0
            var onThisLoad: [LineItem] = []

            // Heaviest-per-unit first so big items aren't stranded.
            let order = pool.filter { $0.quantity > 0 }
                .map { (name: $0.name, cost: capacity(capacities, transport: movement.transportName, furniture: $0.name).map { 1 / $0 } ?? 0) }
                .sorted { $0.cost > $1.cost }
                .map { $0.name }

            for name in order {
                guard let idx = pool.firstIndex(where: { $0.name == name }), pool[idx].quantity > 0 else { continue }
                let cap = capacity(capacities, transport: movement.transportName, furniture: name)
                let placeable: Int
                if let cap {
                    if remaining <= 0 { break }
                    let costPerUnit = 1 / cap
                    placeable = min(pool[idx].quantity, Int((remaining / costPerUnit) + 1e-9))
                    if placeable <= 0 { continue }
                    remaining -= Double(placeable) * costPerUnit
                } else {
                    placeable = pool[idx].quantity   // no capacity defined: take it all
                }
                onThisLoad.append(LineItem(name: name, quantity: placeable))
                pool[idx].quantity -= placeable
            }

            result[movement.id] = onThisLoad
        }

        return result
    }
}
