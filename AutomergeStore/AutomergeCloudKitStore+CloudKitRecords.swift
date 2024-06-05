import CoreData
import CloudKit

extension AutomergeCloudKitStore {
    
    class CloudKitRecords {
        
        let container: NSPersistentContainer
        var viewContext: NSManagedObjectContext { container.viewContext }
        
        public init(url: URL? = nil) throws {
            container = NSPersistentContainer(name: "CloudKitRecords")
            
            let storeDescription = container.persistentStoreDescriptions.first!
            
            if let url {
                storeDescription.url = url
            }
            
            container.loadPersistentStores(completionHandler: { (storeDescription, error) in
                if let error = error as NSError? {
                    /*
                     Typical reasons for an error here include:
                     * The parent directory does not exist, cannot be created, or disallows writing.
                     * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                     * The device is out of space.
                     * The store could not be migrated to the current model version.
                     Check the error message to determine what the actual problem was.
                     */
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
            })
            
            container.viewContext.automaticallyMergesChangesFromParent = true
            container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        }
    }
    
}

extension AutomergeCloudKitStore.CloudKitRecords {
    
    func prepareChunkRecordForSend(id: CKRecord.ID, automergeStore: AutomergeStore) -> CKRecord? {
        /*guard let chunkMO = try? fetchChunk(heads: id.recordName) else {
            return nil
        }
        return chunkMO.preparedRecord(id: id)
        */
        fatalError()
    }

}

extension ChunkMO {
    
    var recordID: CKRecord.ID {
        .init(recordName: uuid!.uuidString, zoneID: document!.workspace!.zoneID)
    }

    var lastKnownRecord: CKRecord? {
        nil
    }
    
    func preparedRecord(id: CKRecord.ID) -> CKRecord {
        let record = lastKnownRecord ?? .init(recordType: .chunkRecordType, recordID: id)
        record.encryptedValues[.document] = heads!
        record.encryptedValues[.heads] = heads!
        record.encryptedValues[.isDelta] = isDelta
        record.encryptedValues[.data] = data!
        return record
    }
    
}

extension WorkspaceMO {
    
    var zoneID: CKRecordZone.ID {
        .init(zoneName: uuid!.uuidString)
    }
    
}
