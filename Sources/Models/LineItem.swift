import Foundation

/// A furniture or transport line item, e.g. {"name":"6 Seat Picnic Table","quantity":50}.
/// In the API these arrive as a JSON *string* on the job; `LineItem.parse` decodes them.
struct LineItem: Codable, Identifiable, Hashable {
    let name: String
    let quantity: Int

    var id: String { "\(name)#\(quantity)" }

    private enum CodingKeys: String, CodingKey { case name, quantity }

    init(name: String, quantity: Int) {
        self.name = name
        self.quantity = quantity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Item"
        // Quantity may decode as Int, Double, or numeric string depending on source.
        if let i = try? c.decode(Int.self, forKey: .quantity) {
            quantity = i
        } else if let d = try? c.decode(Double.self, forKey: .quantity) {
            quantity = Int(d)
        } else if let s = try? c.decode(String.self, forKey: .quantity), let i = Int(s) {
            quantity = i
        } else {
            quantity = 1
        }
    }

    /// Content-keyed cache: `furniture`/`transport` re-parse the same JSON string
    /// on every access (list rows, JobStore's derived collections — hundreds of
    /// times per render pass). NSCache is thread-safe (parse can run off the main
    /// actor during decoding) and, since the key *is* the content, never needs
    /// invalidation.
    private static let parseCache = NSCache<NSString, NSArray>()

    /// Decode a JSON-string field (furniture_items / transport_items) into items.
    /// Tolerant: returns [] for nil, empty, or malformed input.
    static func parse(_ jsonString: String?) -> [LineItem] {
        guard let jsonString,
              !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8) else { return [] }
        let key = jsonString as NSString
        if let cached = parseCache.object(forKey: key) as? [LineItem] {
            return cached
        }
        let items = (try? JSONDecoder().decode([LineItem].self, from: data)) ?? []
        parseCache.setObject(items as NSArray, forKey: key)
        return items
    }
}
