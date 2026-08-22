//
//  Entitlement.swift
//  BleepKit
//

import Foundation
import Observation

/// What the free tier allows. Everything else — import, transcription,
/// detection, styling, preview — is free and never gated: verifying the
/// word timing on your own footage is the purchase decision.
enum FreeTier {
    /// Free exports render only the first this-many seconds.
    static let exportLimitSeconds: Double = 15
}

/// The Pro unlock state, readable anywhere in the UI.
///
/// StoreKit is the source of truth — `StoreService` refreshes this from
/// `Transaction.currentEntitlements` on every launch and on every
/// transaction update. The cached flag exists only so a launch that
/// begins offline fails open when a prior verification succeeded; it is
/// never trusted past the next StoreKit answer.
@MainActor
@Observable
final class Entitlement {
    private static let cacheKey = "entitlement.pro.lastVerified"

    /// True when BleepKit Pro (full-length export) is unlocked.
    private(set) var isPro: Bool

    init() {
        isPro = UserDefaults.standard.bool(forKey: Self.cacheKey)
    }

    /// Records a fresh verification answer from StoreKit.
    func update(isPro: Bool) {
        self.isPro = isPro
        UserDefaults.standard.set(isPro, forKey: Self.cacheKey)
    }
}
