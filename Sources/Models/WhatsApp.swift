import Foundation

/// Builds the driver WhatsApp message + deep link, matching the web app's
/// `sendWhatsAppForMovement` / `formatUKPhoneForWhatsApp`.
enum WhatsApp {

    /// Normalise a UK number to WhatsApp's international digits (no '+').
    /// Returns nil if the result is too short to be a real number.
    static func formatUKPhone(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var phone = raw.filter(\.isNumber)
        if phone.hasPrefix("07"), phone.count == 11 {
            phone = "44" + phone.dropFirst()
        } else if phone.hasPrefix("0044") {
            phone = "44" + phone.dropFirst(4)
        } else if phone.hasPrefix("440") {
            phone = "44" + phone.dropFirst(3)
        }
        return phone.count >= 10 ? phone : nil
    }

    /// The formatted message body sent to the driver.
    static func message(
        jobType: JobType,
        eventName: String?,
        dateString: String?,
        transportName: String?,
        loadPosition: Int,
        totalMovements: Int,
        contactName: String?,
        contactPhone: String?,
        destination: String?,
        postcode: String?,
        items: [LineItem],
        notes: String?
    ) -> String {
        let typeEmoji = jobType == .collection ? "📦" : "🚚"
        var lines: [String] = [
            "\(typeEmoji) *\(jobType.label.uppercased())* \(typeEmoji)",
            "",
            "*Event:* " + (eventName?.nilIfBlank ?? "N/A"),
            "*Date:* " + DateUtil.whatsAppDate(from: dateString)
        ]

        if let transportName, transportName.nilIfBlank != nil {
            if totalMovements > 1 {
                lines.append("*Load:* \(transportName) (\(loadPosition)/\(totalMovements))")
            } else {
                lines.append("*Transport:* \(transportName)")
            }
        }

        lines.append("")
        lines.append("*Contact Info*")
        lines.append("Name: " + (contactName?.nilIfBlank ?? "N/A"))
        lines.append("Phone: " + (contactPhone?.nilIfBlank ?? "N/A"))
        lines.append("")
        lines.append("*Location*")
        lines.append("Address: " + (destination?.nilIfBlank ?? "N/A"))
        lines.append("Postcode: " + (postcode?.nilIfBlank ?? "N/A"))

        if !items.isEmpty {
            lines.append("")
            lines.append("*Items*")
            for item in items { lines.append("\(item.quantity) x \(item.name)") }
        }

        if let note = notes?.nilIfBlank {
            lines.append("")
            lines.append("*Notes*")
            lines.append(note)
        }

        return lines.joined(separator: "\n")
    }

    /// The wa.me deep link (opens WhatsApp with the message prefilled).
    static func url(phoneDigits: String, message: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/" + phoneDigits
        components.queryItems = [URLQueryItem(name: "text", value: message)]
        return components.url
    }
}
