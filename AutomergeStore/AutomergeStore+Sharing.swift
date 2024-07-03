import CoreData
import CloudKit

protocol RenderableUserIdentity {
    var nameComponents: PersonNameComponents? { get }
    var contactIdentifiers: [String] { get }
}

protocol RenderableShareParticipant {
    var renderableUserIdentity: RenderableUserIdentity { get }
    var role: CKShare.ParticipantRole { get }
    var permission: CKShare.ParticipantPermission { get }
    var acceptanceStatus: CKShare.ParticipantAcceptanceStatus { get }
}

protocol RenderableShare {
    var renderableParticipants: [RenderableShareParticipant] { get }
}

extension CKUserIdentity: RenderableUserIdentity {}

extension CKShare.Participant: RenderableShareParticipant {
    var renderableUserIdentity: RenderableUserIdentity {
        return userIdentity
    }
}

extension CKShare: RenderableShare {
    var renderableParticipants: [RenderableShareParticipant] {
        return participants
    }
}

extension AutomergeStore {
        
    public func isShared(workspaceId: WorkspaceId) -> Bool {
        guard
            let workspaceMO = viewContext.fetchWorkspace(id: workspaceId),
            let persistentStore = workspaceMO.objectID.persistentStore
        else {
            return false
        }
        
        if persistentStore == sharedPersistentStore {
            return true
        } else {
            let container = persistentContainer
            do {
                let shares = try container.fetchShares(matching: [workspaceMO.objectID])
                if nil != shares.first {
                    return true
                }
            } catch let error {
                print("Failed to fetch share for \(workspaceMO): \(error)")
            }
        }
        return false
    }
    
    func persistentStoreForShare(with shareRecordID: CKRecord.ID) -> NSPersistentStore? {
        if let shares = try? persistentContainer.fetchShares(in: privatePersistentStore) {
            let zoneIDs = shares.map { $0.recordID.zoneID }
            if zoneIDs.contains(shareRecordID.zoneID) {
                return privatePersistentStore
            }
        }
        if let shares = try? persistentContainer.fetchShares(in: sharedPersistentStore) {
            let zoneIDs = shares.map { $0.recordID.zoneID }
            if zoneIDs.contains(shareRecordID.zoneID) {
                return sharedPersistentStore
            }
        }
        return nil
    }
    
    func persistentStoreForShare(_ share: CKShare) -> NSPersistentStore? {
        return persistentStoreForShare(with: share.recordID)
    }

    public func shareWorkspace(
        _ id: WorkspaceId,
        to existingShare: CKShare?
    ) async throws -> (share: CKShare, container: CKContainer) {
        guard let workspaceMO = viewContext.fetchWorkspace(id: id) else {
            throw Error(msg: "Workspace not found \(id)")
        }
        let (_ ,share, ckContainer) = try await persistentContainer.share([workspaceMO], to: existingShare)
        return (share, ckContainer)
    }

    public func createShare() async throws -> CKShare {
        let (_ ,share, _) = try await persistentContainer.share([], to: nil)
        return share
    }
    
    public func deleteShare(_ share: CKShare, keepingContent: Bool = true) {
        guard let store = persistentStoreForShare(with: share.recordID) else {
            print("\(#function): Failed to find the persistent store for share. \(share))")
            return
        }
        
        if keepingContent {
            
        }
        
        persistentContainer.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: store) { (zoneID, error) in
            if let error = error {
                print("\(#function): Failed to purge objects and records: \(error)")
            }
        }
    }
    
    public func participants(for workspaceId: WorkspaceId) -> [CKShare.Participant] {
        guard let workspaceMO = viewContext.fetchWorkspace(id: workspaceId) else {
            return []
        }
        var participants = [CKShare.Participant]()
        do {
            let container = persistentContainer
            let shares = try container.fetchShares(matching: [workspaceMO.objectID])
            if let share = shares[workspaceMO.objectID] {
                participants = share.participants
            }
        } catch let error {
            print("Failed to fetch share for \(workspaceMO): \(error)")
        }
        return participants
    }
        
    public func shares(matching workspaceIds: [WorkspaceId]) throws -> [NSManagedObjectID: CKShare] {
        try persistentContainer.fetchShares(matching: workspaceIds.compactMap {
            viewContext.fetchWorkspace(id: $0)?.objectID
        })
    }
    
    public func canEdit(workspaceId: WorkspaceId) -> Bool {
        guard let workspaceMO = viewContext.fetchWorkspace(id: workspaceId) else {
            return false
        }
        return persistentContainer.canUpdateRecord(forManagedObjectWith: workspaceMO.objectID)
    }
        
    public func canDelete(workspaceId: WorkspaceId) -> Bool {
        guard let workspaceMO = viewContext.fetchWorkspace(id: workspaceId) else {
            return false
        }
        return persistentContainer.canDeleteRecord(forManagedObjectWith: workspaceMO.objectID)
    }
        
    class func string(for permission: CKShare.ParticipantPermission) -> String {
        switch permission {
        case .unknown:
            return "Unknown"
        case .none:
            return "None"
        case .readOnly:
            return "Read-Only"
        case .readWrite:
            return "Read-Write"
        @unknown default:
            return "\(permission)"
        }
    }
    
    class func string(for role: CKShare.ParticipantRole) -> String {
        switch role {
        case .owner:
            return "Owner"
        case .privateUser:
            return "Private User"
        case .publicUser:
            return "Public User"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "\(role)"
        }
    }
    
    class func string(for acceptanceStatus: CKShare.ParticipantAcceptanceStatus) -> String {
        switch acceptanceStatus {
        case .accepted:
            return "Accepted"
        case .removed:
            return "Removed"
        case .pending:
            return "Invited"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "\(acceptanceStatus)"
        }
    }
    
}

#if os(macOS)
import AppKit

extension AutomergeStore {
    
    func presentCloudSharingController(share: CKShare) {
        guard
            let cloudKitContainer,
            let sharingService = NSSharingService(named: .cloudSharing)
        else {
            print("\(#function): Failed to create an NSSharingService instance for cloud sharing.")
            return
        }
        
        let itemProvider = NSItemProvider()
        itemProvider.registerCloudKitShare(share, container: cloudKitContainer)
        if sharingService.canPerform(withItems: [itemProvider]) {
            sharingService.perform(withItems: [itemProvider])
        } else {
            print("\(#function): Sharing service can't perform with \([itemProvider]).")
        }
    }
    
}
#endif

#if os(iOS)
import UIKit

extension AutomergeStore {
    
    func presentCloudSharingController(share: CKShare) {
        guard let cloudKitContainer else {
            return
        }
        let sharingController = UICloudSharingController(share: share, container: cloudKitContainer)
        if let viewController = rootViewController {
            sharingController.modalPresentationStyle = .formSheet
            viewController.present(sharingController, animated: true)
        }
    }
    
    private var rootViewController: UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            if scene.activationState == .foregroundActive,
               let sceneDeleate = (scene as? UIWindowScene)?.delegate as? UIWindowSceneDelegate,
               let window = sceneDeleate.window {
                return window?.rootViewController
            }
        }
        print("\(#function): Failed to retrieve the window's root view controller.")
        return nil
    }
    
}
#endif
