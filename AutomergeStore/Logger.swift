import os.log

extension Logger {
    static let loggingSubsystem: String = "com.hogbaysoftware.AutomergeStore"
    nonisolated(unsafe) static let automergeStore = Logger(subsystem: Self.loggingSubsystem, category: "CoreData")
    nonisolated(unsafe) static let automergeCloudKit = Logger(subsystem: Self.loggingSubsystem, category: "CloudKit")
}

#if swift(>=6.0)
    #warning("Reevaluate whether this decoration is necessary.")
#endif
