import Foundation

/// Response shapes for the Current-RMS completion endpoints (`/api/crms/…`),
/// matching what the web app's `public/js/crms.js` reads. Deliberately minimal
/// and tolerant: only the fields the completion flow uses are decoded, and
/// everything CRMS might omit or null out is optional.

/// `GET /api/crms/opportunities/:id/items`
struct CrmsOpportunityItemsResponse: Decodable {
    struct Opportunity: Decodable {
        let opportunityItems: [Item]?
        enum CodingKeys: String, CodingKey { case opportunityItems = "opportunity_items" }
    }

    struct Item: Decodable {
        let id: Int
        let item: Nested?
        let itemTypeName: String?
        let itemType: FlexibleString?

        struct Nested: Decodable {
            let itemTypeName: String?
            enum CodingKeys: String, CodingKey { case itemTypeName = "item_type_name" }
        }

        enum CodingKeys: String, CodingKey {
            case id, item
            case itemTypeName = "item_type_name"
            case itemType = "item_type"
        }

        /// The item type surfaces in different places (and sometimes as a
        /// number) depending on the CRMS response variant — same three-way
        /// fallback as the web's `getOpportunityServiceItemAssets`.
        var isService: Bool {
            let raw = item?.itemTypeName ?? itemTypeName ?? itemType?.value ?? ""
            return raw.lowercased().contains("service")
        }
    }

    let opportunity: Opportunity?
    var items: [Item] { opportunity?.opportunityItems ?? [] }
}

/// A JSON value that arrives as either a string or a number.
struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { value = s }
        else if let i = try? container.decode(Int.self) { value = String(i) }
        else if let d = try? container.decode(Double.self) { value = String(d) }
        else { value = "" }
    }
}

/// `GET /api/crms/opportunities/:oppId/items/:itemId/assets`
struct CrmsItemAssetsResponse: Decodable {
    struct OpportunityItem: Decodable {
        let itemAssets: [Asset]?
        enum CodingKeys: String, CodingKey { case itemAssets = "item_assets" }
    }
    struct Asset: Decodable { let id: Int }

    let opportunityItem: OpportunityItem?
    enum CodingKeys: String, CodingKey { case opportunityItem = "opportunity_item" }

    var assetIds: [Int] { (opportunityItem?.itemAssets ?? []).map(\.id) }
}

/// `POST /api/crms/opportunities/:id/close-order`. The server always answers
/// 200 with per-step outcomes: `errors` are hard failures, `warnings` soft ones
/// (e.g. items still booked out — finalise manually later).
struct CrmsCloseOrderResponse: Decodable {
    struct StepError: Decodable {
        let step: String?
        let error: String?
    }
    struct StepWarning: Decodable {
        let message: String?
    }

    /// The three steps arrive as arbitrary CRMS payloads or null — only their
    /// presence matters for the summary, so decode each as "did it run".
    struct Results: Decodable {
        let finaliseItems: Bool
        let finaliseServices: Bool
        let markCompleted: Bool

        enum CodingKeys: String, CodingKey {
            case finaliseItems = "finalise_items"
            case finaliseServices = "finalise_services"
            case markCompleted = "mark_completed"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func ran(_ key: CodingKeys) -> Bool {
                c.contains(key) && (try? c.decodeNil(forKey: key)) == false
            }
            finaliseItems = ran(.finaliseItems)
            finaliseServices = ran(.finaliseServices)
            markCompleted = ran(.markCompleted)
        }
    }

    let success: Bool?
    let results: Results?
    let errors: [StepError]?
    let warnings: [StepWarning]?
}
