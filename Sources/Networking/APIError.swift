import Foundation

enum APIError: LocalizedError, Equatable {
    case badURL
    case unauthorized
    case forbidden
    case notFound
    case server(status: Int, message: String?)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "The server address is invalid. Check it in the More tab."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .forbidden:
            return "You don't have permission to do that."
        case .notFound:
            return "Not found."
        case .server(let status, let message):
            return message ?? "Server error (\(status))."
        case .decoding(let detail):
            return "Couldn't read the server response. \(detail)"
        case .transport(let detail):
            return "Network error. \(detail)"
        }
    }
}
