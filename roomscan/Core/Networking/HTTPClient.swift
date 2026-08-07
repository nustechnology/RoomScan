//
//  HTTPClient.swift
//  roomscan
//

import Foundation

// MARK: - HTTP Method

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

// MARK: - Endpoint

struct APIEndpoint: Sendable {
    let path: String
    let method: HTTPMethod
    let headers: [String: String]
    let body: Data?

    init(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.headers = headers
        self.body = body
    }

    func urlRequest(baseURL: URL) -> URLRequest {
        let url: URL
        if path.hasPrefix("/") {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            components.path = path
            url = components.url ?? baseURL
        } else {
            url = baseURL.appendingPathComponent(path)
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
    case decodingError
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

// MARK: - Helpers

extension APIEndpoint {
    func addingHeader(key: String, value: String) -> APIEndpoint {
        var mergedHeaders = headers
        mergedHeaders[key] = value
        return APIEndpoint(path: path, method: method, headers: mergedHeaders, body: body)
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

    init(
        baseURL: URL = URL(string: "https://roomscan-be.onrender.com")!,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let request = endpoint.urlRequest(baseURL: baseURL)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw HTTPClientError.networkError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.networkError
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw HTTPClientError.serverError(
                statusCode: httpResponse.statusCode,
                apiError: apiError
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HTTPClientError.decodingError
        }
    }
}
