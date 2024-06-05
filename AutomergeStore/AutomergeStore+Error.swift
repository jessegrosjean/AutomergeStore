import Foundation

extension AutomergeStore {

    public struct Error: Sendable, LocalizedError {
        public var msg: String
        public var errorDescription: String? { "AutomergeStoreError: \(msg)" }

        public init(msg: String) {
            self.msg = msg
        }
    }

}
