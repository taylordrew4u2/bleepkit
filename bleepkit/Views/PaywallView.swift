//
//  PaywallView.swift
//  BleepKit
//

import StoreKit
import SwiftUI

/// The BleepKit Pro paywall — one non-consumable unlocking full-length
/// export. Shown only at the Export tap, after the user has seen a
/// correct preview: never at launch, never before transcription.
///
/// The free path stays visible ("export the first 15 seconds"), and
/// Restore Purchases is a visible control, as App Review requires.
struct PaywallView: View {
    enum Outcome {
        /// Pro verified — export the full length.
        case unlocked
        /// Continue on the free tier's capped export.
        case freeExport
    }

    /// Called with the user's choice; the host starts the export.
    let onContinue: (Outcome) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var product: Product?
    @State private var productUnavailable = false
    @State private var isWorking = false
    @State private var noticeMessage: String?
    @State private var showsCodeRedemption = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.roomy) {
                header
                featureList
                Spacer(minLength: Spacing.compact)
                purchaseButton
                Button {
                    onContinue(.freeExport)
                } label: {
                    Text("Export the first \(Int(FreeTier.exportLimitSeconds)) seconds free")
                        .font(.bleepControlLabel)
                        .frame(maxWidth: .infinity, minHeight: TapTarget.minimum)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                HStack(spacing: Spacing.roomy) {
                    Button("Restore Purchases") {
                        Task { await restore() }
                    }
                    Button("Redeem a Code") {
                        showsCodeRedemption = true
                    }
                }
                .font(.bleepControlLabel)
                .disabled(isWorking)
            }
            .padding(.horizontal)
            .padding(.bottom, Spacing.medium)
            .navigationTitle("BleepKit Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .alert(
            "App Store",
            isPresented: Binding(
                get: { noticeMessage != nil },
                set: { if !$0 { noticeMessage = nil } }
            )
        ) {
            Button("OK") { noticeMessage = nil }
        } message: {
            Text(noticeMessage ?? "")
        }
        // The system sheet for App Store offer codes (Connect can issue
        // them free or discounted for the Pro non-consumable). A custom
        // code-entry UI isn't permitted — only this sheet.
        .offerCodeRedemption(isPresented: $showsCodeRedemption) { result in
            Task { await handleRedemption(result) }
        }
        .task { await loadProduct() }
    }

    /// A redeemed code arrives like any purchase: confirm the entitlement
    /// from StoreKit, then continue into the unlocked export. The launch
    /// `Transaction.updates` listener covers codes redeemed in the App
    /// Store app as well.
    private func handleRedemption(_ result: Result<Void, any Error>) async {
        switch result {
        case .success:
            let isPro = await StoreService.hasVerifiedEntitlement()
            environment.entitlement.update(isPro: isPro)
            if isPro {
                onContinue(.unlocked)
            }
        case .failure(let error):
            noticeMessage = error.localizedDescription
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.compact) {
            Image(systemName: "waveform.badge.checkmark")
                .font(.bleepTransportGlyph)
                .foregroundStyle(Color.bleepAccent)
                .padding(.top, Spacing.medium)
            Text("Unlock full-length export")
                .font(.bleepMasthead)
            Text("You've seen the preview — this is the whole edit, saved to Photos, ready to post.")
                .font(.bleepDetail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            featureRow("Export any length — no caps")
            featureRow("One-time purchase, no subscription")
            featureRow("Family Sharing included")
            featureRow("Everything still happens on this iPhone")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.standard)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.card))
    }

    private func featureRow(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.bleepDetail)
        } icon: {
            Image(systemName: "checkmark")
                .foregroundStyle(Color.bleepAccent)
        }
    }

    @ViewBuilder
    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            Group {
                if isWorking {
                    ProgressView()
                } else if let product {
                    Text("Unlock for \(product.displayPrice)")
                } else if productUnavailable {
                    Text("Try Loading Price Again")
                } else {
                    ProgressView()
                }
            }
            .font(.bleepEmphasis)
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimum)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .foregroundStyle(Color.bleepOnAccent)
        .disabled(isWorking)
    }

    // MARK: Store actions

    private func loadProduct() async {
        do {
            product = try await environment.storeService.product()
            productUnavailable = false
        } catch {
            // Offline is fine — the free path stays available; the price
            // button becomes a retry.
            productUnavailable = true
        }
    }

    private func purchase() async {
        guard product != nil else {
            await loadProduct()
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await environment.storeService.purchase() {
            case .unlocked:
                environment.entitlement.update(isPro: true)
                onContinue(.unlocked)
            case .pending:
                noticeMessage = "Your purchase is awaiting approval. Full export unlocks automatically once it's approved."
            case .cancelled:
                break
            }
        } catch {
            noticeMessage = error.localizedDescription
        }
    }

    private func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await environment.storeService.restore()
            let isPro = await StoreService.hasVerifiedEntitlement()
            environment.entitlement.update(isPro: isPro)
            if isPro {
                onContinue(.unlocked)
            } else {
                noticeMessage = "No previous purchase was found for this Apple Account."
            }
        } catch {
            noticeMessage = error.localizedDescription
        }
    }
}
