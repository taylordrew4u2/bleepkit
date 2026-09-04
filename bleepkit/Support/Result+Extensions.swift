//
//  Result+Extensions.swift
//  BleepKit
//

import Foundation

nonisolated extension Result {
    /// True when the operation was intentionally cancelled by the user.
    var isUserCancellation: Bool {
        guard case .failure(let error) = self else { return false }
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    /// The failure's human-readable message, or nil on success. Used by UI
    /// completion handlers that only need to surface an error.
    var failureMessage: String? {
        guard case .failure(let error) = self else { return nil }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
