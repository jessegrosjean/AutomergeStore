import CloudKit

extension CKRecord {
    
    public convenience init?(encodedSystemFields data: Data) {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else {
            return nil
        }
        unarchiver.requiresSecureCoding = true
        self.init(coder: unarchiver)
    }
    
    public var encodedSystemFieldsData: Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        encodeSystemFields(with: archiver)
        return archiver.encodedData
    }
    
}
