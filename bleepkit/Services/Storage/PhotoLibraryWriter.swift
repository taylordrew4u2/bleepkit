//
//  PhotoLibraryWriter.swift
//  BleepKit
//

import Foundation
import os
import OSLog
import Photos

/// Saves finished exports into the user's Photo Library, in a "BleepKit"
/// album created on first export.
nonisolated struct PhotoLibraryWriter: Sendable {
    enum WriteError: LocalizedError {
        /// The user declined (or policy restricts) adding to Photos.
        case notAuthorized
        /// The album could not be created or found after creation.
        case albumUnavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "BleepKit isn't allowed to save videos to your Photo Library. You can change this in Settings."
            case .albumUnavailable:
                return "The BleepKit album couldn't be created in your Photo Library."
            }
        }
    }

    private static let albumTitle = "BleepKit"

    /// Requests add-only authorization at point of use.
    static func requestAddAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }

    /// Saves the video file into the "BleepKit" album.
    ///
    /// - Throws: `WriteError.notAuthorized` when the user declined,
    ///   `WriteError.albumUnavailable` when the album can't be resolved, or
    ///   the underlying Photos error.
    func saveToAlbum(fileURL: URL) async throws {
        let status = await Self.requestAddAuthorization()
        guard status == .authorized || status == .limited else {
            throw WriteError.notAuthorized
        }

        let albumIdentifier = try await findOrCreateAlbumIdentifier()
        try await PHPhotoLibrary.shared().performChanges {
            let creation = PHAssetCreationRequest.forAsset()
            creation.addResource(with: .video, fileURL: fileURL, options: nil)
            // Re-fetch inside the change block: collection objects are not
            // Sendable, but their identifiers are.
            let album = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumIdentifier], options: nil
            ).firstObject
            if let album,
               let placeholder = creation.placeholderForCreatedAsset,
               let albumChange = PHAssetCollectionChangeRequest(for: album) {
                albumChange.addAssets([placeholder] as NSArray)
            }
        }
        Logger.export.info("Saved export to the \(Self.albumTitle) album")
    }

    /// Returns the local identifier of the "BleepKit" album, creating the
    /// album on first use.
    private func findOrCreateAlbumIdentifier() async throws -> String {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", Self.albumTitle)
        let existing = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: options
        )
        if let album = existing.firstObject {
            return album.localIdentifier
        }

        let identifierBox = OSAllocatedUnfairLock<String?>(initialState: nil)
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                withTitle: Self.albumTitle
            )
            let identifier = request.placeholderForCreatedAssetCollection.localIdentifier
            identifierBox.withLock { $0 = identifier }
        }
        guard let identifier = identifierBox.withLock({ $0 }) else {
            throw WriteError.albumUnavailable
        }
        return identifier
    }
}
