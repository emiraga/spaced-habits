import Foundation
import Observation
import os
import SwiftUI

/// Runs throwing UI actions and shows their errors in an alert, instead of each screen swallowing them.
@MainActor
@Observable
public final class ErrorPresenter {
    public var error: (any Error)?

    @ObservationIgnored private let logger = Logger(subsystem: "ga.emira.spacedhabits", category: "ui")

    public init() {}

    /// Returns whether `action` succeeded.
    @discardableResult
    public func attempt(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func report(_ error: any Error) {
        logger.error("Action failed: \(String(describing: error), privacy: .public)")
        self.error = error
    }

    /// `attempt` for async actions.
    @discardableResult
    public func attemptAsync(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            return true
        } catch {
            report(error)
            return false
        }
    }
}

public extension View {
    func errorAlert(_ presenter: ErrorPresenter) -> some View {
        alert(
            Text("Something went wrong", bundle: .module),
            isPresented: Binding(get: { presenter.error != nil }, set: {
                if !$0 {
                    presenter.error = nil
                }
            }),
            presenting: presenter.error
        ) { _ in
            Button(String(localized: "OK", bundle: .module), role: .cancel) {}
        } message: { error in
            Text((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    }
}
