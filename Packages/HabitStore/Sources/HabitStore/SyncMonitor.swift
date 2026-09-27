import CloudKit
import CoreData
import Foundation
import Observation
import os

/// CloudKit sync state for Settings → Sync status, and the hook that re-reads truth when another device's
/// changes have been merged (DESIGN.md §10). SwiftData syncs through `NSPersistentCloudKitContainer`, which
/// reports each setup, import and export as an `eventChangedNotification`.
@MainActor
@Observable
public final class SyncMonitor {
    public enum Account: Equatable, Sendable {
        case checking, available, noAccount, restricted, temporarilyUnavailable
        case failed(String)

        public var label: String {
            switch self {
            case .checking: "Checking…"
            case .available: "iCloud"
            case .noAccount: "Not signed in to iCloud"
            case .restricted: "iCloud restricted"
            case .temporarilyUnavailable: "iCloud temporarily unavailable"
            case let .failed(reason): "iCloud error: \(reason)"
            }
        }
    }

    public private(set) var account = Account.checking
    /// When the last import of other devices' changes finished.
    public private(set) var lastMerge: Date?
    /// The last failed setup, import or export; cleared by the next success.
    public private(set) var lastError: String?

    /// Called after each successful import (§10: re-project, reload widgets).
    @ObservationIgnored public var onMerge: (@MainActor () -> Void)?
    /// Never removed: one monitor lives as long as the app, and the closures hold it weakly.
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private let logger = Logger(subsystem: "ga.emira.spacedhabits", category: "sync")

    public init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event, let endDate = event.endDate
            else { return }
            let finished = FinishedEvent(
                isImport: event.type == .import, endDate: endDate,
                error: event.error.map(\.localizedDescription)
            )
            MainActor.assumeIsolated { self?.handle(finished) }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccount() }
        })
        refreshAccount()
    }

    public func refreshAccount() {
        Task {
            do {
                let status = try await CKContainer(identifier: StoreContainer.cloudKitContainerID).accountStatus()
                account = Self.account(status)
            } catch {
                account = .failed(error.localizedDescription)
            }
        }
    }

    /// The parts of an `NSPersistentCloudKitContainer.Event` that matter here, extracted before leaving
    /// the notification's closure (the event isn't `Sendable`).
    private struct FinishedEvent {
        let isImport: Bool
        let endDate: Date
        let error: String?
    }

    private func handle(_ event: FinishedEvent) {
        if let error = event.error {
            logger.error("CloudKit sync failed: \(error, privacy: .public)")
            lastError = error
            return
        }
        lastError = nil
        if event.isImport {
            lastMerge = event.endDate
            onMerge?()
        }
    }

    private static func account(_ status: CKAccountStatus) -> Account {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .failed("could not determine the account")
        @unknown default: .failed("unknown account status \(status.rawValue)")
        }
    }
}
