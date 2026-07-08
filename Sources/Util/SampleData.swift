import Foundation

/// Realistic sample data (shaped exactly like the API) for SwiftUI previews and
/// an offline demo. Decoding these also smoke-tests the Codable models.
enum SampleData {
    static let hauliers: [Haulier] = decode("""
    [
      {"id":1,"name":"Glencourt","color":"#e32400","active":1,"phone":"07971647808"},
      {"id":2,"name":"Essex Hay","color":"#371a94","active":1,"phone":"07831474198"},
      {"id":3,"name":"Exmor Hay","color":"#77bb41","active":1,"phone":"07557308957"},
      {"id":4,"name":"Adrian / Ray","color":"#6b7280","active":1,"phone":"07917164249"},
      {"id":5,"name":"Ellis","color":"#669c35","active":1,"phone":"07939835705"}
    ]
    """)

    static let jobs: [Job] = decode(jobsJSON)

    /// Per-load assignments for the demo (matches the API include_movements shape).
    /// The "County Show" job has two HGV loads on different hauliers.
    static let assignmentsByJob: [Int: [MovementAssignment]] = [
        44560: decode("""
        [
          {"id":1001,"job_id":44560,"transport_name":"HGV Delivery","movement_index":1,"haulier_id":1,"notes":"","status":"booked","date":null,"haulier_name":"Glencourt","haulier_color":"#e32400","haulier_phone":"07971647808"},
          {"id":1002,"job_id":44560,"transport_name":"HGV Delivery","movement_index":2,"haulier_id":2,"notes":"","status":"pending","date":null,"haulier_name":"Essex Hay","haulier_color":"#371a94","haulier_phone":"07831474198"}
        ]
        """)
    ]

    static let config = AppConfig(
        defaultDepot: .init(name: "Depot", postcode: "TA1 1AA"),
        pricing: .init(base: 100, perMile: 3.6),
        crms: .init(subdomain: "hirehaulage"),
        furnitureCapacities: [
            "HGV": ["6 Seat Picnic Table": 84],
            "LGV": ["6 Seat Picnic Table": 70],
            "VAN": ["6 Seat Picnic Table": 12]
        ]
    )

    private static func decode<T: Decodable>(_ json: String) -> T {
        let data = Data(json.utf8)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { fatalError("SampleData decode failed: \(error)") }
    }

    private static let todayStr = DateUtil.todayString()
    private static func plus(_ n: Int) -> String { DateUtil.addingDays(n, to: todayStr) ?? todayStr }

    private static let jobsJSON = """
    [
      {
        "id": 44531, "crms_id": 44531, "date": "\(todayStr)", "time_start": "08:00", "time_end": "10:00",
        "event_name": "Glastonbury Village Fete", "destination": "Worthy Farm, Pilton, Shepton Mallet",
        "destination_postcode": "BA4 4BY",
        "furniture_items": "[{\\"name\\":\\"6 Seat Picnic Table\\",\\"quantity\\":40},{\\"name\\":\\"Bench\\",\\"quantity\\":12}]",
        "transport_items": "[{\\"name\\":\\"HGV Delivery\\",\\"quantity\\":1}]",
        "job_type": "delivery", "self_arranged": 0, "deliver_date": "\(todayStr)", "collect_date": "\(plus(3))",
        "contact_name": "John", "contact_phone": "07967322848", "synced_at": "2026-05-21 10:07:46",
        "deliver_weather_summary": "Sunny 21°C", "collect_weather_summary": null,
        "haulier_id": 1, "origin": "Depot", "origin_postcode": "TA1 1AA", "mileage": 28.4,
        "mileage_override": 0, "budget_price": 202.24, "notes": "Call 1 hour before arrival.",
        "status": "booked", "haulier_name": "Glencourt"
      },
      {
        "id": 44540, "crms_id": 44540, "date": "\(todayStr)", "time_start": "13:30", "time_end": "15:00",
        "event_name": "Riverside Wedding", "destination": "The Boathouse, Bath Road, Bradford-on-Avon",
        "destination_postcode": "BA15 1WD",
        "furniture_items": "[{\\"name\\":\\"6 Seat Picnic Table\\",\\"quantity\\":15}]",
        "transport_items": "[{\\"name\\":\\"Van Delivery\\",\\"quantity\\":1}]",
        "job_type": "delivery", "self_arranged": 0, "deliver_date": "\(todayStr)", "collect_date": "\(plus(2))",
        "contact_name": "Priya", "contact_phone": "07700900123", "synced_at": "2026-05-21 10:07:46",
        "deliver_weather_summary": "Cloudy 17°C", "collect_weather_summary": null,
        "haulier_id": null, "origin": null, "origin_postcode": null, "mileage": null,
        "mileage_override": 0, "budget_price": null, "notes": null,
        "status": "pending", "haulier_name": null
      },
      {
        "id": 4672, "crms_id": 4672, "date": "\(plus(3))", "time_start": "08:00", "time_end": "08:00",
        "event_name": "Clubland on the Beach 2026", "destination": "Marine Parade, The Seafront, Weston-super-Mare",
        "destination_postcode": "BS23 1AL",
        "furniture_items": "[{\\"name\\":\\"6 Seat Picnic Table\\",\\"quantity\\":50}]",
        "transport_items": "[{\\"name\\":\\"LGV Collection 7.5T\\",\\"quantity\\":1}]",
        "job_type": "collection", "self_arranged": 0, "deliver_date": "\(todayStr)", "collect_date": "\(plus(3))",
        "contact_name": "Barry", "contact_phone": "", "synced_at": "2026-05-21 10:07:46",
        "deliver_weather_summary": null, "collect_weather_summary": "Showers 15°C",
        "haulier_id": 3, "origin": "Depot", "origin_postcode": "TA1 1AA", "mileage": 41.0,
        "mileage_override": 0, "budget_price": 247.6, "notes": null,
        "status": "completed", "haulier_name": "Exmor Hay"
      },
      {
        "id": 44560, "crms_id": 44560, "date": "\(todayStr)", "time_start": "07:00", "time_end": "09:00",
        "event_name": "County Show", "destination": "Bath & West Showground, Shepton Mallet",
        "destination_postcode": "BA4 6QN",
        "furniture_items": "[{\\"name\\":\\"6 Seat Picnic Table\\",\\"quantity\\":120}]",
        "transport_items": "[{\\"name\\":\\"HGV Delivery\\",\\"quantity\\":2}]",
        "job_type": "delivery", "self_arranged": 0, "deliver_date": "\(todayStr)", "collect_date": "\(plus(4))",
        "contact_name": "Sue", "contact_phone": "07700900789", "synced_at": "2026-05-21 10:07:46",
        "deliver_weather_summary": "Sunny 22°C", "collect_weather_summary": null,
        "haulier_id": null, "origin": "Depot", "origin_postcode": "TA1 1AA", "mileage": 22.0,
        "mileage_override": 0, "budget_price": 179.2, "notes": "Two HGV loads.",
        "status": "pending", "haulier_name": null
      },
      {
        "id": 44550, "crms_id": 44550, "date": "\(plus(5))", "time_start": "09:00", "time_end": "11:00",
        "event_name": "Corporate Family Day", "destination": "Ashton Court Estate, Long Ashton, Bristol",
        "destination_postcode": "BS41 9JN",
        "furniture_items": "[{\\"name\\":\\"6 Seat Picnic Table\\",\\"quantity\\":30}]",
        "transport_items": "[]",
        "job_type": "delivery", "self_arranged": 1, "deliver_date": "\(plus(5))", "collect_date": "\(plus(6))",
        "contact_name": "Dan", "contact_phone": "07700900456", "synced_at": "2026-05-21 10:07:46",
        "deliver_weather_summary": null, "collect_weather_summary": null,
        "haulier_id": null, "origin": null, "origin_postcode": null, "mileage": null,
        "mileage_override": 0, "budget_price": null, "notes": "Customer collecting themselves.",
        "status": "pending", "haulier_name": null
      },
      {
        "id": 44510, "crms_id": 445101, "date": "\(todayStr)", "time_start": "06:00", "time_end": "08:00",
        "event_name": "Harbour Festival", "destination": "The Quay, Bristol",
        "destination_postcode": "BS1 4RN",
        "furniture_items": "[{\\"name\\":\\"6 Seat Picnic Table\\",\\"quantity\\":24}]",
        "transport_items": "[]",
        "job_type": "delivery", "self_arranged": 0, "deliver_date": "\(todayStr)", "collect_date": "\(plus(2))",
        "contact_name": "Mo", "contact_phone": "07700900222", "synced_at": "2026-05-21 10:07:46",
        "deliver_weather_summary": "Sunny 20°C", "collect_weather_summary": null,
        "haulier_id": 1, "origin": "Depot", "origin_postcode": "TA1 1AA", "mileage": 18.0,
        "mileage_override": 0, "budget_price": 164.8, "notes": "Invoiced and completed.",
        "status": "completed", "haulier_name": "Glencourt", "closed": 1
      }
    ]
    """
}
