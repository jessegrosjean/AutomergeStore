import Foundation
import CloudKit
import CoreData

extension AutomergeStore {

    public enum SyncStatus {
        case noNetwork
        case noAccount
        case error
        case notSyncing
        case notStarted
        case inProgress
        case succeeded
        case unknown

        public var symbolName: String {
            switch self {
            case .noNetwork:
                return "bolt.horizontal.icloud"
            case .noAccount:
                return "lock.icloud"
            case .error:
                return "exclamationmark.icloud"
            case .notSyncing:
                return "xmark.icloud"
            case .notStarted:
                return "bolt.horizontal.icloud"
            case .inProgress:
                return "arrow.clockwise.icloud"
            case .succeeded:
                return "icloud"
            case .unknown:
                return "icloud.slash"
            }
        }
        
        public var description: String {
            switch self {
            case .noNetwork:
                return String(localized: "No network available")
            case .noAccount:
                return String(localized: "No iCloud account")
            case .error:
                return String(localized: "Error")
            case .notSyncing:
                return String(localized: "Not syncing to iCloud")
            case .notStarted:
                return String(localized: "Sync not started")
            case .inProgress:
                return String(localized: "Syncing...")
            case .succeeded:
                return String(localized: "Synced with iCloud")
            case .unknown:
                return String(localized: "Error")
            }
        }

        public var isBroken: Bool {
            switch self {
            case .noNetwork:
                return false
            case .noAccount:
                return false
            case .error:
                return true
            case .notSyncing:
                return true
            case .notStarted:
                return false
            case .inProgress:
                return false
            case .succeeded:
                return false
            case .unknown:
                return true
            }
        }

        public var inProgress: Bool {
            if case .inProgress = self {
                return true
            }
            return false
        }
    }
    
    func initSyncStatus() {
        cloudKitSyncMonitor
            .objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else {
                    return
                }
                let summary = self.cloudKitSyncMonitor.syncStateSummary
                switch summary {
                case .noNetwork:
                    self.syncStatus = .noNetwork
                case .accountNotAvailable:
                    self.syncStatus = .noAccount
                case .error:
                    self.syncStatus = .error
                case .notSyncing:
                    self.syncStatus = .notSyncing
                case .notStarted:
                    self.syncStatus = .notStarted
                case .inProgress:
                    self.syncStatus = .inProgress
                case .succeeded:
                    self.syncStatus = .succeeded
                case .unknown:
                    self.syncStatus = .unknown
                }
            }.store(in: &cancellables)
    }

}
