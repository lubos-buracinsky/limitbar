import Foundation

struct HTTPResult: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
}

struct URLSessionHTTPTransport: HTTPTransport, Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LimitbarError.invalidResponse("Non-HTTP response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LimitbarError.httpStatus(httpResponse.statusCode, body)
        }

        return HTTPResult(data: data, response: httpResponse)
    }
}

enum HTTPHelpers {
    static func jsonObject(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LimitbarError.parsing("Failed to parse JSON: \(error.localizedDescription)")
        }
    }

    static func stringHeader(_ response: HTTPURLResponse, key: String) -> String? {
        response.value(forHTTPHeaderField: key)
    }

    static func parseDouble(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    static func parseDate(_ value: Any?) -> Date? {
        if let unixString = value as? String, let timestamp = Double(unixString) {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let unix = value as? Double {
            return Date(timeIntervalSince1970: unix)
        }
        if let isoText = value as? String {
            let iso = ISO8601DateFormatter()
            if let date = iso.date(from: isoText) {
                return date
            }
        }
        return nil
    }

    static func parseRateResetHeader(_ raw: String?, now: Date) -> Date? {
        guard let raw, !raw.isEmpty else {
            return nil
        }

        if let seconds = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return now.addingTimeInterval(seconds)
        }

        if raw.hasSuffix("ms"), let value = Double(raw.dropLast(2)) {
            return now.addingTimeInterval(value / 1_000)
        }

        if raw.hasSuffix("s"), let value = Double(raw.dropLast(1)) {
            return now.addingTimeInterval(value)
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: raw) {
            return date
        }

        return nil
    }
}
