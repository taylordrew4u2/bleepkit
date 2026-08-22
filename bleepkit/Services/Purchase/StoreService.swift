//
//  StoreService.swift
//  BleepKit
//

import Foundation
import OSLog
import StoreKit

/// Wraps StoreKit 2 for the single BleepKit Pro non-consumable.
///
/// This is the app's one deliberate exception to the offline rule —
/// StoreKit needs the network to load the product and run a purchase,
/// but entitlement *checks* never block offline: `currentEntitlements`
/// reads the device's local transaction cache, and `Entitlement` fails
/// open from its last verified state.
actor StoreService {
    /// The one product: non-consumable, unlocks full-length export.
    /// Must match the product ID configured in App Store Connect.
    static let proProductID = "comedy.bleepkit.pro"

    enum PurchaseOutcome {
        /// Verified and finished — Pro is unlocked.
        case unlocked
        /// Deferred (for example, Ask to Buy); unlocks later through
        /// `Transaction.updates` if approved.
        case pending
        case cancelled
    }

    enum StoreError: LocalizedError {
        case productUnavailable
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .productUnavailable:
                return "The App Store product couldn't be loaded. Check your connection and try again."
            case .verificationFailed:
                return "The App Store receipt couldn't be verified. Try Restore Purchases."
            }
        }
    }

    private var cachedProduct: Product?

    /// The Pro product, loaded on demand and memoized for the session.
    func product() async throws -> Product {
        if let cachedProduct { return cachedProduct }
        guard let product = try await Product.products(for: [Self.proProductID]).first else {
            throw StoreError.productUnavailable
        }
        cachedProduct = product
        return product
    }

    /// Runs the purchase flow. Returns `.unlocked` only for a transaction
    /// that passed StoreKit's verification — never trust an unverified one.
    func purchase() async throws -> PurchaseOutcome {
        let result = try await product().purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                Logger.storage.error("Purchase returned an unverified transaction")
                throw StoreError.verificationFailed
            }
            await transaction.finish()
            return .unlocked
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Syncs with the App Store — the user-visible Restore Purchases
    /// control App Review requires for non-consumables.
    func restore() async throws {
        try await AppStore.sync()
    }

    /// True when a verified, unrevoked Pro entitlement exists. Reads the
    /// local transaction cache, so it also answers offline.
    static func hasVerifiedEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == proProductID,
                  transaction.revocationDate == nil
            else { continue }
            return true
        }
        return false
    }
}
