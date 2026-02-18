import Foundation

enum LimitbarError: LocalizedError {
    case missingSecret(String)
    case invalidConfig(String)
    case invalidResponse(String)
    case httpStatus(Int, String)
    case parsing(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .missingSecret(let message),
                .invalidConfig(let message),
                .invalidResponse(let message),
                .parsing(let message),
                .unsupported(let message):
            return message
        case .httpStatus(let code, let body):
            if body.isEmpty {
                return "HTTP status \(code)"
            }
            return "HTTP status \(code): \(body)"
        }
    }
}
