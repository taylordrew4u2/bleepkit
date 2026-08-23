//
//  FAQView.swift
//  BleepKit
//

import SwiftUI

/// Frequently asked questions — static, on-device answers, matching
/// the app's one-job scope.
struct FAQView: View {
    /// One question and its answer.
    private struct Entry: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    private static let entries: [Entry] = [
        Entry(
            question: "Does my video leave my iPhone?",
            answer: "No. Importing, transcription, profanity detection, editing, and export all run on this device. The only network feature is the App Store purchase itself."
        ),
        Entry(
            question: "How are bad words found?",
            answer: "Your video's audio is transcribed on-device, and each word is checked against a built-in profanity list. You can adjust which severity tiers count in the Transcript screen's options."
        ),
        Entry(
            question: "Can I choose exactly which words get bleeped?",
            answer: "Yes. In the editor, open Censoring and tap words in the Words to Bleep grid, or use the Transcript screen to force any word to always or never be censored."
        ),
        Entry(
            question: "A word's bleep timing looks off. Can I fix it?",
            answer: "Timing comes from the on-device speech recognizer. Nudge the beep padding in Censoring → Timing to extend the censored span, or re-transcribe from the Transcript screen's options."
        ),
        Entry(
            question: "Why are captions and detection English-only?",
            answer: "The built-in profanity list is English. On devices set to another language, transcription still runs, but automatic detection may not flag words — you can still censor any word by hand."
        ),
        Entry(
            question: "What's free, and what does Pro unlock?",
            answer: "Everything is free — import, transcription, detection, captions, censoring, and preview. Free exports render the first 15 seconds; BleepKit Pro (one-time purchase, Family Sharing included) unlocks full-length export."
        ),
        Entry(
            question: "I already bought Pro. How do I get it back?",
            answer: "Tap Export, then Restore Purchases on the unlock screen. Purchases follow your Apple Account, so a new phone restores the same way."
        ),
        Entry(
            question: "Where do exported videos go?",
            answer: "Into a “BleepKit” album in your Photo Library, ready to upload. If Photos access is denied you can share the file directly instead."
        ),
        Entry(
            question: "What happens when I delete a project?",
            answer: "It moves to the Trash and keeps its video. Restore it any time, or empty the trash to delete projects and their videos permanently."
        ),
    ]

    var body: some View {
        List {
            ForEach(Self.entries) { entry in
                DisclosureGroup {
                    Text(entry.answer)
                        .font(.bleepDetail)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Spacing.tight)
                } label: {
                    Text(entry.question)
                }
            }
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
