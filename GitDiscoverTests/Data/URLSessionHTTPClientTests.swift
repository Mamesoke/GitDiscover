import Foundation
import Testing
@testable import GitDiscover

struct URLSessionHTTPClientTests {
    @Test(.timeLimit(.minutes(1)))
    func cancellingRequestStopsUnderlyingURLLoading() async throws {
        let url = try #require(URL(string: "https://urlsession-cancellation.invalid/\(UUID().uuidString)"))
        let events = AsyncStream<LoadingEvent>.makeStream()
        let center = NotificationCenter.default
        let started = center.addObserver(forName: CancellationURLProtocol.started, object: nil, queue: nil) { notification in
            guard notification.object as? URL == url else { return }
            events.continuation.yield(.started)
        }
        let stopped = center.addObserver(forName: CancellationURLProtocol.stopped, object: nil, queue: nil) { notification in
            guard notification.object as? URL == url else { return }
            events.continuation.yield(.stopped)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CancellationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            center.removeObserver(started)
            center.removeObserver(stopped)
            events.continuation.finish()
        }
        let client = URLSessionHTTPClient(session: session)
        let task = Task { try await client.data(for: URLRequest(url: url)) }
        defer { task.cancel() }
        var iterator = events.stream.makeAsyncIterator()

        #expect(await iterator.next() == .started)
        task.cancel()

        #expect(await iterator.next() == .stopped)
        await #expect {
            try await task.value
        } throws: { error in
            (error as? URLError)?.code == .cancelled
        }
    }
}

private enum LoadingEvent: Sendable {
    case started
    case stopped
}

// URLProtocol requires unchecked Sendable; this subclass has no mutable state.
private final class CancellationURLProtocol: URLProtocol, @unchecked Sendable {
    static let started = Notification.Name("GitDiscoverTests.URLLoadingStarted")
    static let stopped = Notification.Name("GitDiscoverTests.URLLoadingStopped")

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "urlsession-cancellation.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        NotificationCenter.default.post(name: Self.started, object: request.url)
    }

    override func stopLoading() {
        NotificationCenter.default.post(name: Self.stopped, object: request.url)
    }
}
