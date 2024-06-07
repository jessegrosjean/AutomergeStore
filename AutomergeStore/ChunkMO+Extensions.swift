import Foundation
import Automerge
import CoreData
import CloudKit
import os.log

extension ChunkMO {
    
    enum CKRecordState: UInt16 {
        case needsSend
        case needsFetch
    }
    
    public convenience init(
        context: NSManagedObjectContext,
        documentId: UUID,
        isSnapshot: Bool,
        data: Data
    ) {
        self.init(context: context)
        self.id = .init()
        self.documentId = documentId
        self.isSnapshot = isSnapshot
        self.data = data
        self.size = Int64(data.count)
    }

    public convenience init(
        context: NSManagedObjectContext,
        record: CKRecord
    ) throws {
        self.init(context: context)

        guard let id = UUID(uuidString: record.recordID.recordName) else {
            throw AutomergeCloudKitStore.Error(msg: "Invalid name \(record)")
        }
        
        guard let documentId = record.encryptedValues[.documentId].map({ UUID(uuidString: $0) }) ?? nil else {
            throw AutomergeCloudKitStore.Error(msg: "Invalid documentId \(record)")
        }
        
        guard let isSnapshot = record.encryptedValues[.isSnapshot] as? Bool else {
            throw AutomergeCloudKitStore.Error(msg: "Invalid isSnapshot \(record)")
        }

        self.id = id
        self.documentId = documentId
        self.isSnapshot = isSnapshot

        if let data = record.encryptedValues[.data] as? Data {
            self.data = data
        } else if let asset = record.encryptedValues[.asset] as? CKAsset {
            guard let fileURL = asset.fileURL else {
                throw AutomergeCloudKitStore.Error(msg: "Asset mising fileURL \(record)")
            }
            self.data = try Data(contentsOf: fileURL)
        } else {
            throw AutomergeCloudKitStore.Error(msg: "Found no data or asset fields \(record)")
        }
    }
    
    var recordID: CKRecord.ID {
        .init(recordName: id!.uuidString, zoneID: workspace!.zoneID)
    }
    
    func preparedRecord(id: CKRecord.ID) -> CKRecord {
        let record = lastKnownRecord ?? .init(recordType: .chunkRecordType, recordID: id)
        let documentId = documentId!.uuidString

        Logger.automergeCloudKit.info("􀇂 prepare chunk CKRecord \(documentId)-\(id)")

        record.encryptedValues[.documentId] = documentId
        record.encryptedValues[.isSnapshot] = isSnapshot

        let data = data!

        if data.count > (1024 * 1024) {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(component: UUID().uuidString + ".data")
            try! data.write(to: url, options: [.atomic])
            let asset = CKAsset(fileURL: url)
            record.encryptedValues[.asset] = asset
        } else {
            record.encryptedValues[.data] = data
        }
        
        return record
    }
    
    var lastKnownRecord: CKRecord? {
        get {
            lastRecord.map {
                do {
                    let unarchiver = try NSKeyedUnarchiver(forReadingFrom: $0)
                    unarchiver.requiresSecureCoding = true
                    return CKRecord(coder: unarchiver)
                } catch {
                    Logger.automergeCloudKit.fault("􀇂 Failed to decode local system fields record: \(error)")
                    return nil
                }
            } ?? nil
        }
        
        set {
            lastRecord = newValue.map {
                let archiver = NSKeyedArchiver(requiringSecureCoding: true)
                $0.encodeSystemFields(with: archiver)
                return archiver.encodedData
            }
        }
    }

}

