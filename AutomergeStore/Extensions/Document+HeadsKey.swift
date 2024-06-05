import Automerge

extension Set<ChangeHash> {
    var stringHash: String {
        debugDescription.data(using: .utf8)!.sha256()
    }
}
