//
//  ScriptedHTTPClient.swift
//  roomscanTests
//

import Foundation
@testable import roomscan

/// Shared HTTP stub that returns scripted success/failure results in order.
final class ScriptedHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Data, HTTPClientError>]
    private(set) var requestCount = 0
    private(set) var recordedEndpoints: [APIEndpoint] = []

    init(results: [Result<Data, HTTPClientError>]) {
        self.results = results
    }

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let next = lock.withLock { () -> Result<Data, HTTPClientError> in
            requestCount += 1
            recordedEndpoints.append(endpoint)
            return results.removeFirst()
        }
        switch next {
        case .success(let data):
            return try LiveHTTPClient.makeAPIDecoder().decode(T.self, from: data)
        case .failure(let error):
            throw error
        }
    }
}
