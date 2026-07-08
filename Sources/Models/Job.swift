import Foundation

/// A delivery or collection job, matching the API shape returned by
/// `GET /api/jobs` and `GET /api/jobs/:id`. Optional everywhere the column can be
/// null or (for budget_price) stripped for non-admin users.
struct Job: Codable, Identifiable, Hashable {
    let id: Int
    let crmsId: Int?
    let date: String?
    let timeStart: String?
    let timeEnd: String?
    let eventName: String?
    let destination: String?
    let destinationPostcode: String?
    let furnitureItemsRaw: String?
    let transportItemsRaw: String?
    let jobTypeRaw: String?
    let selfArrangedRaw: Int?
    let deliverDate: String?
    let collectDate: String?
    let contactName: String?
    let contactPhone: String?
    let syncedAt: String?
    let deliverWeatherSummary: String?
    let collectWeatherSummary: String?
    let haulierId: Int?
    let origin: String?
    let originPostcode: String?
    let mileage: Double?
    let mileageOverrideRaw: Int?
    let budgetPrice: Double?
    let notes: String?
    let statusRaw: String?
    let haulierName: String?
    /// `1` when this is an archived (completed-in-CRMS) job — read-only history.
    /// Absent on live jobs (defaults to not-closed).
    let closedRaw: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case crmsId = "crms_id"
        case date
        case timeStart = "time_start"
        case timeEnd = "time_end"
        case eventName = "event_name"
        case destination
        case destinationPostcode = "destination_postcode"
        case furnitureItemsRaw = "furniture_items"
        case transportItemsRaw = "transport_items"
        case jobTypeRaw = "job_type"
        case selfArrangedRaw = "self_arranged"
        case deliverDate = "deliver_date"
        case collectDate = "collect_date"
        case contactName = "contact_name"
        case contactPhone = "contact_phone"
        case syncedAt = "synced_at"
        case deliverWeatherSummary = "deliver_weather_summary"
        case collectWeatherSummary = "collect_weather_summary"
        case haulierId = "haulier_id"
        case origin
        case originPostcode = "origin_postcode"
        case mileage
        case mileageOverrideRaw = "mileage_override"
        case budgetPrice = "budget_price"
        case notes
        case statusRaw = "status"
        case haulierName = "haulier_name"
        case closedRaw = "closed"
    }

    // MARK: Derived

    var status: JobStatus { JobStatus(apiValue: statusRaw) }
    var type: JobType { JobType(apiValue: jobTypeRaw) }
    var isSelfArranged: Bool { (selfArrangedRaw ?? 0) != 0 }
    /// Archived (completed-in-CRMS) job — shown read-only.
    var isClosed: Bool { (closedRaw ?? 0) != 0 }
    var title: String { (eventName?.isEmpty == false ? eventName! : "Untitled job") }

    var furniture: [LineItem] { LineItem.parse(furnitureItemsRaw) }
    var transport: [LineItem] { LineItem.parse(transportItemsRaw) }

    /// The date that matters for *this* side of the job.
    var relevantDateString: String? {
        switch type {
        case .delivery:   return deliverDate ?? date
        case .collection: return collectDate ?? date
        }
    }

    var weatherSummary: String? {
        type == .delivery ? deliverWeatherSummary : collectWeatherSummary
    }

    var hasHaulier: Bool { haulierId != nil && (haulierName?.isEmpty == false) }

    var totalFurnitureCount: Int { furniture.reduce(0) { $0 + $1.quantity } }

    /// A short one-line transport summary, e.g. "1× LGV 7.5T".
    var transportSummary: String? {
        guard !transport.isEmpty else { return nil }
        return transport.map { "\($0.quantity)× \($0.name)" }.joined(separator: ", ")
    }

    var contactPhoneDigits: String? { contactPhone?.phoneDigits }

    /// Start–end time, blank when absent (shared by card + detail).
    var timeLabel: String? {
        guard let start = timeStart?.nilIfBlank else { return nil }
        if let end = timeEnd?.nilIfBlank, end != start { return "\(start)–\(end)" }
        return start
    }

    /// Destination + postcode joined, nil when both blank (shared by card + detail).
    var destinationLabel: String? {
        let parts = [destination?.nilIfBlank, destinationPostcode?.nilIfBlank].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Returns a copy with the editable fields changed. Used for optimistic
    /// updates and the offline demo (the server returns the same shape).
    func withLocalEdits(status: JobStatus, notes: String, haulierId: Int?, haulierName: String?) -> Job {
        Job(
            id: id, crmsId: crmsId, date: date, timeStart: timeStart, timeEnd: timeEnd,
            eventName: eventName, destination: destination, destinationPostcode: destinationPostcode,
            furnitureItemsRaw: furnitureItemsRaw, transportItemsRaw: transportItemsRaw,
            jobTypeRaw: jobTypeRaw, selfArrangedRaw: selfArrangedRaw,
            deliverDate: deliverDate, collectDate: collectDate,
            contactName: contactName, contactPhone: contactPhone, syncedAt: syncedAt,
            deliverWeatherSummary: deliverWeatherSummary, collectWeatherSummary: collectWeatherSummary,
            haulierId: haulierId, origin: origin, originPostcode: originPostcode,
            mileage: mileage, mileageOverrideRaw: mileageOverrideRaw, budgetPrice: budgetPrice,
            notes: notes.isEmpty ? nil : notes, statusRaw: status.rawValue, haulierName: haulierName,
            closedRaw: closedRaw
        )
    }
}

/// Envelope returned by `GET /api/jobs`. With `include_movements=true` the
/// server also returns `movementAssignments`, keyed by job id (as a string).
struct JobsResponse: Codable {
    let jobs: [Job]
    let movementAssignments: [String: [MovementAssignment]]?
}
