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
    private static let promoKey = "entitlement.pro.promoUnlocked"

    /// The in-app promo code that unlocks Pro without a purchase,
    /// checked locally so it works offline and forever.
    static let localPromoCode = "CLEANCOMEDY"

    /// True when BleepKit Pro (full-length export) is unlocked, by
    /// purchase or by promo code.
    private(set) var isPro: Bool

    init() {
        isPro = UserDefaults.standard.bool(forKey: Self.cacheKey)
            || UserDefaults.standard.bool(forKey: Self.promoKey)
    }

    /// Records a fresh verification answer from StoreKit. A promo
    /// unlock survives regardless of what StoreKit reports.
    func update(isPro storeKitPro: Bool) {
        UserDefaults.standard.set(storeKitPro, forKey: Self.cacheKey)
        isPro = storeKitPro || UserDefaults.standard.bool(forKey: Self.promoKey)
    }

    /// Redeems an in-app promo code; returns whether it matched.
    func redeemLocalCode(_ code: String) -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized == Self.localPromoCode else { return false }
        UserDefaults.standard.set(true, forKey: Self.promoKey)
        isPro = true
        return true
    }
}
