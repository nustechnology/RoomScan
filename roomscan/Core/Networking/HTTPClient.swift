//
//  HTTPClient.swift
//  roomscan
//

import Foundation

struct APIRevision: Decodable, Sendable, Equatable {
    static let initial = "1"
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            guard let intValue = Int(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid revision"
                )
            }
            value = intValue
        } else {
            value = try container.decode(Int.self)
        }
    }
}

actor APIRevisionStore {
    static let shared = APIRevisionStore()
    private static let storageKey = "api.revisions"
    private var revisions: [String: String]

    init() {
        revisions = UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }

    private func persist() {
        UserDefaults.standard.set(revisions, forKey: Self.storageKey)
    }

    func currentRevision(for resourceID: String) -> String {
        revisions[resourceID] ?? APIRevision.initial
    }

    func advance(for resourceID: String) {
        let nextValue = (Int(revisions[resourceID] ?? APIRevision.initial) ?? 1) + 1
        revisions[resourceID] = String(nextValue)
        persist()
    }

    func update(_ revision: String?, for resourceID: String) {
        guard let revision, let incoming = Int(revision) else { return }
        if let current = revisions[resourceID].flatMap(Int.init), current >= incoming {
            return
        }
        revisions[resourceID] = String(incoming)
        persist()
    }
}

// MARK: - HTTP Method

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

// MARK: - Endpoint

struct APIEndpoint: Sendable {
    let path: String
    let method: HTTPMethod
    let headers: [String: String]
    let body: Data?
    let queryItems: [URLQueryItem]

    init(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        queryItems: [URLQueryItem] = [],
        idempotencyKey: String? = nil,
        revision: String? = nil
    ) {
        self.path = path
        self.method = method
        var requestHeaders = headers
        if method == .post, let idempotencyKey {
            requestHeaders["Idempotency-Key"] = idempotencyKey
        }
        if method == .patch || method == .delete, let revision {
            requestHeaders["If-Match"] = Self.ifMatchValue(for: revision)
        }
        self.headers = requestHeaders
        self.body = body
        self.queryItems = queryItems
    }

    private static func ifMatchValue(for revision: String) -> String {
        if revision == "*" || (revision.hasPrefix("\"") && revision.hasSuffix("\"")) {
            return revision
        }
        return "\"\(revision)\""
    }

    func urlRequest(baseURL: URL) -> URLRequest {
        let url: URL
        if path.hasPrefix("/") {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            components.path = path
            if !queryItems.isEmpty {
                components.queryItems = queryItems
            }
            url = components.url ?? baseURL
        } else {
            var components = URLComponents(
                url: baseURL.appendingPathComponent(path),
                resolvingAgainstBaseURL: false
            )!
            if !queryItems.isEmpty {
                components.queryItems = queryItems
            }
            url = components.url ?? baseURL.appendingPathComponent(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if body != nil, request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}

// MARK: - Errors

enum HTTPClientError: Error, Equatable, Sendable {
    case invalidURL
    case networkError
    case serverError(statusCode: Int, apiError: APIErrorResponse?)
    case decodingError(underlying: String, bodyPreview: String)
}

// MARK: - API Error Response

struct APIErrorResponse: Decodable, Sendable, Equatable {
    let error: APIErrorBody
    let requestId: String
}

struct APIErrorBody: Decodable, Sendable, Equatable {
    let code: String
    let message: String
    let details: String?
}

/// Decodable placeholder for endpoints that return an empty body (e.g. HTTP 204).
struct EmptyAPIResponse: Decodable, Sendable, Equatable {}

// MARK: - Helpers

extension APIEndpoint {
    func addingHeader(key: String, value: String) -> APIEndpoint {
        var mergedHeaders = headers
        mergedHeaders[key] = value
        return APIEndpoint(
            path: path,
            method: method,
            headers: mergedHeaders,
            body: body,
            queryItems: queryItems
        )
    }
}

// MARK: - Client Protocol

protocol HTTPClient: Sendable {
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T
}

// MARK: - Live Implementation

struct LiveHTTPClient: HTTPClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(
        baseURL: URL = URL(string: "https://roomscan.nustechnology.com")!,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = LiveHTTPClient.makeAPIDecoder()
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.decoder = decoder
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let request = endpoint.urlRequest(baseURL: baseURL)

        let (data, httpResponse) = try await perform(request, endpoint: endpoint)

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? decoder.decode(APIErrorResponse.self, from: data)
            #if DEBUG
            print(
                """
                [HTTP] server error method=\(endpoint.method.rawValue) path=\(endpoint.path) \
                status=\(httpResponse.statusCode) apiError=\(String(describing: apiError))
                """
            )
            #endif
            throw HTTPClientError.serverError(
                statusCode: httpResponse.statusCode,
                apiError: apiError
            )
        }

        do {
            let decodeData = data.isEmpty ? Data("{}".utf8) : data
            return try decoder.decode(T.self, from: decodeData)
        } catch {
            let bodyPreview = Self.bodyPreview(from: data)
            let underlying = String(describing: error)
            #if DEBUG
            print(
                """
                [HTTP] decode failed method=\(endpoint.method.rawValue) path=\(endpoint.path) \
                status=\(httpResponse.statusCode) error=\(underlying)
                """
            )
            #endif
            throw HTTPClientError.decodingError(underlying: underlying, bodyPreview: bodyPreview)
        }
    }

    private func perform(
        _ request: URLRequest,
        endpoint: APIEndpoint
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                #if DEBUG
                print("[HTTP] request cancelled method=\(endpoint.method.rawValue) path=\(endpoint.path)")
                #endif
                throw CancellationError()
            }
            #if DEBUG
            print(
                """
                [HTTP] request failed method=\(endpoint.method.rawValue) path=\(endpoint.path) \
                error=\(error.localizedDescription)
                """
            )
            #endif
            throw HTTPClientError.networkError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.networkError
        }

        return (data, httpResponse)
    }

    private static func bodyPreview(from data: Data, limit: Int = 2_048) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        guard raw.count > limit else { return raw }
        return String(raw.prefix(limit)) + "…(\(raw.count - limit) more)"
    }

    static func makeAPIDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let withFractionalSeconds = ISO8601DateFormatter()
            withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractionalSeconds.date(from: value) {
                return date
            }

            let withoutFractionalSeconds = ISO8601DateFormatter()
            withoutFractionalSeconds.formatOptions = [.withInternetDateTime]
            if let date = withoutFractionalSeconds.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }
}
