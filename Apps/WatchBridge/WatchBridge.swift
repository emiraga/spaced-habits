import Foundation
import HabitStore
import HabitUI
import os
import WatchConnectivity

/// Carries truth between the phone and the watch (DESIGN.md §7). Every local write goes to the other
/// device as `TruthChange`s: by message while it's reachable (immediate), else queued with
/// `transferUserInfo`, which is also the fallback when a message fails. What arrives is merged into the
/// model, so a change delivered twice is harmless. A watch with an empty store asks for everything.
/// Compiled into the iOS app and the watch app.
@MainActor
final class WatchBridge: NSObject {
    /// What travels, as a WatchConnectivity dictionary.
    private enum Payload: Sendable {
        case changes(Data)
        case requestAll

        private static let changesKey = "truthChanges"
        private static let requestAllKey = "requestAll"

        var dictionary: [String: Any] {
            switch self {
            case let .changes(data): [Self.changesKey: data]
            case .requestAll: [Self.requestAllKey: true]
            }
        }

        init?(_ dictionary: [String: Any]) {
            if let data = dictionary[Self.changesKey] as? Data {
                self = .changes(data)
            } else if dictionary[Self.requestAllKey] as? Bool == true {
                self = .requestAll
            } else {
                return nil
            }
        }
    }

    /// Changes per message: a message must stay well under WatchConnectivity's ~64 KB limit.
    private static let changesPerMessage = 50

    private let store: TruthStore
    /// Set right after the model is created on `store`. The bridge exists first so that the writes the
    /// model makes while initializing (its first session's questions) are sent too.
    var model: AppModel?
    private let errors: ErrorPresenter
    private let session: WCSession?
    private var activated = false
    /// Written before activation finished; sent once it has.
    private var pending: [TruthChange] = []
    private let encoder = JSONEncoder()
    private nonisolated static let logger = Logger(subsystem: "ga.emira.spacedhabits", category: "watch-bridge")

    /// Starts sending `store`'s writes.
    init(store: TruthStore, errors: ErrorPresenter) {
        self.store = store
        self.errors = errors
        session = WCSession.isSupported() ? .default : nil
        super.init()
        store.onChange = { [weak self] in self?.send([$0]) }
        session?.delegate = self
        session?.activate()
    }

    private func send(_ changes: [TruthChange]) {
        pending += changes
        flush()
    }

    private func flush() {
        guard activated, let session, !pending.isEmpty else { return }
        guard Self.counterpartInstalled(session) else {
            // A watch app installed later asks for everything, so nothing needs keeping.
            pending = []
            return
        }
        let changes = pending
        pending = []
        errors.attempt { try post(changes) }
    }

    private func post(_ changes: [TruthChange]) throws {
        for start in stride(from: 0, to: changes.count, by: Self.changesPerMessage) {
            let chunk = changes[start ..< min(start + Self.changesPerMessage, changes.count)]
            try post(.changes(encoder.encode(Array(chunk))))
        }
    }

    private func post(_ payload: Payload) {
        guard let session else { return }
        guard session.isReachable else {
            session.transferUserInfo(payload.dictionary)
            return
        }
        session.sendMessage(payload.dictionary, replyHandler: nil) { error in
            Self.logger.info("Message failed, queueing it: \(String(describing: error), privacy: .public)")
            WCSession.default.transferUserInfo(payload.dictionary)
        }
    }

    private static func counterpartInstalled(_ session: WCSession) -> Bool {
        #if os(iOS)
            session.isPaired && session.isWatchAppInstalled
        #else
            session.isCompanionAppInstalled
        #endif
    }

    /// On the watch: ask for everything while the store is empty (first launch, or the phone was away).
    private func requestAllIfEmpty() {
        #if os(watchOS)
            if activated, model?.truth.habits.isEmpty == true {
                post(.requestAll)
            }
        #endif
    }

    private func received(_ payload: Payload) {
        switch payload {
        case let .changes(data):
            guard let model else {
                Self.logger.error("Changes arrived before the model existed; CloudKit will deliver them")
                return
            }
            errors.attempt { try model.merge(JSONDecoder().decode([TruthChange].self, from: data)) }
        case .requestAll:
            sendAll()
        }
    }

    /// The phone's answer to `requestAll`: by messages while the watch is reachable, else as a file (too
    /// large for a user-info transfer).
    private func sendAll() {
        guard let session else { return }
        errors.attempt {
            let changes = try store.allChanges()
            if session.isReachable {
                try post(changes)
                return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("truth-\(UUID().uuidString).json")
            try encoder.encode(changes).write(to: url)
            session.transferFile(url, metadata: nil)
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(
        _: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: (any Error)?
    ) {
        let failure = error.map(String.init(describing:))
        Task { @MainActor in
            if let failure {
                Self.logger.error("WatchConnectivity activation failed: \(failure, privacy: .public)")
            } else if state == .activated {
                activated = true
                flush()
                requestAllIfEmpty()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in requestAllIfEmpty() }
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        let payload = Payload(message)
        Task { @MainActor in payload.map(received) }
    }

    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = Payload(userInfo)
        Task { @MainActor in payload.map(received) }
    }

    /// The file is deleted when this returns, so it's read here.
    nonisolated func session(_: WCSession, didReceive file: WCSessionFile) {
        let contents = Result { try Data(contentsOf: file.fileURL) }
        Task { @MainActor in
            switch contents {
            case let .success(data): received(.changes(data))
            case let .failure(error): errors.attempt { throw error }
            }
        }
    }

    /// Sent or failed, the temporary file is no longer needed; the watch asks again while it's empty.
    nonisolated func session(_: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        if let error {
            Self.logger.error("Sending all truth failed: \(String(describing: error), privacy: .public)")
        }
        do {
            try FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        } catch {
            Self.logger.error("Removing the sent file failed: \(String(describing: error), privacy: .public)")
        }
    }

    #if os(iOS)
        nonisolated func sessionDidBecomeInactive(_: WCSession) {}

        /// After switching watches: activate again for the new one.
        nonisolated func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }
    #endif
}
