import os.log

extension Logger {
    static let loggingSubsystem: String = "com.hogbaysoftware.AutomergeStore"
    static let automergeStore = Logger(subsystem: Self.loggingSubsystem, category: "CoreData")
    static let automergeCloudKit = Logger(subsystem: Self.loggingSubsystem, category: "CloudKit")
}
