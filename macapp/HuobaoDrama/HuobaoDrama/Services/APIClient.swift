import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(Int, String?)
    case decodingError(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效 URL"
        case .networkError(let e): return "网络错误: \(e.localizedDescription)"
        case .serverError(let code, let msg): return "服务器错误 \(code): \(msg ?? "未知")"
        case .decodingError(let e): return "解析错误: \(e.localizedDescription)"
        case .unknown: return "未知错误"
        }
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()
    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    private var baseURL: String { ConnectionSettingsStore.shared.apiBaseURL }

    private func makeRequest(_ path: String, method: String = "GET", body: (any Encodable)? = nil) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
        }
        return req
    }

    func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        let req = try makeRequest(path)
        return try await perform(req)
    }

    func post<T: Decodable & Sendable>(_ path: String, body: some Encodable) async throws -> T {
        let req = try makeRequest(path, method: "POST", body: body)
        return try await perform(req)
    }

    func put<T: Decodable & Sendable>(_ path: String, body: some Encodable) async throws -> T {
        let req = try makeRequest(path, method: "PUT", body: body)
        return try await perform(req)
    }

    func delete(_ path: String) async throws {
        let req = try makeRequest(path, method: "DELETE")
        let _: EmptyData = try await perform(req)
    }

    private func perform<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.serverError(http.statusCode, msg)
        }
        do {
            let wrapped = try decoder.decode(APIResponse<T>.self, from: data)
            if let d = wrapped.data { return d }
            // For EmptyData
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // SSE streaming for agent chat
    func streamSSE(path: String, body: some Encodable) -> AsyncThrowingStream<String, Error> {
        let req = try? makeRequest(path, method: "POST", body: body)
        return AsyncThrowingStream { continuation in
            Task {
                guard let req else {
                    continuation.finish(throwing: APIError.invalidURL)
                    return
                }
                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: req)
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            if payload == "[DONE]" { break }
                            continuation.yield(payload)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
