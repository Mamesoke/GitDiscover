import Foundation

protocol TimeProvider: Sendable {
    func now() async -> Date
}

struct SystemTimeProvider: TimeProvider {
    func now() async -> Date { Date() }
}