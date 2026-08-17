//
//  AppEnvironment.swift
//  BleepKit
//

import Foundation
import Observation
import SwiftData

/// Constructs and owns every service in the app.
///
/// Views and view models receive this container through the SwiftUI
/// environment, so each service can be swapped for a test double by
/// injecting a differently configured instance.
@MainActor
@Observable
final class AppEnvironment {
    /// Persistent store holding `Project` records.
    let modelContainer: ModelContainer
    /// Owner of the scratch directory under Caches.
    let tempFiles: TempFileManager
    /// CRUD façade over `Project` records and their source files.
    let projectStore: ProjectStore
    /// Extracts a video's audio track to an `.m4a` for transcription.
    let audioExtractor: AudioExtractor
    /// Engine-selecting façade over on-device speech transcription.
    let transcriptionService: TranscriptionService
    /// Whole-word profanity detection over the bundled vocabulary.
    let profanityMatcher: ProfanityMatcher
    /// Runtime beep-tone synthesis with a per-session cache.
    let beepGenerator: BeepGenerator
    /// Builds the muted-source-plus-beep audio composition.
    let audioCensorBuilder: AudioCensorBuilder
    /// Saves finished exports into the "BleepKit" Photos album.
    let photoLibraryWriter: PhotoLibraryWriter

    /// - Throws: Any error raised while opening the SwiftData store.
    init() throws {
        let schema = Schema([Project.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        tempFiles = TempFileManager()
        projectStore = ProjectStore(modelContainer: modelContainer)
        audioExtractor = AudioExtractor(tempFiles: tempFiles)
        transcriptionService = TranscriptionService()
        profanityMatcher = ProfanityMatcher(list: try ProfanityList.loadBundled())
        beepGenerator = BeepGenerator(tempFiles: tempFiles)
        audioCensorBuilder = AudioCensorBuilder(beepGenerator: beepGenerator)
        photoLibraryWriter = PhotoLibraryWriter()
    }
}
