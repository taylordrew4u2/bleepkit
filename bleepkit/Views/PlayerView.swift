//
//  PlayerView.swift
//  BleepKit
//

import AVFoundation
import SwiftUI
import UIKit

/// The censored-video preview surface.
///
/// `AVVideoCompositionCoreAnimationTool` renders only on export (§3.4), so
/// the preview carries its own copies of the caption and overlay trees on an
/// `AVSynchronizedLayer`, which evaluates the same `CAAnimation` timings
/// against the player item's clock. The trees come from the same builders
/// as export, sized to the on-screen video rect.
struct PlayerView: UIViewRepresentable {
    let player: AVPlayer
    /// The composition's output size; determines the displayed video rect.
    let renderSize: CGSize
    /// Bumped by the view model whenever tokens or styles change; triggers
    /// a rebuild of the synchronized layer trees.
    let revision: Int
    /// Builds the preview layer trees for a given video-rect size and
    /// screen scale.
    let buildOverlayLayers: @MainActor (CGSize, CGFloat) -> [CALayer]

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.buildOverlayLayers = buildOverlayLayers
        view.player = player
        view.renderSize = renderSize
        view.setRevision(revision)
        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        view.buildOverlayLayers = buildOverlayLayers
        view.player = player
        view.renderSize = renderSize
        view.setRevision(revision)
    }
}

/// UIKit host for the player layer plus the synchronized preview trees.
@MainActor
final class PlayerContainerView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var syncLayer: AVSynchronizedLayer?
    private var revision = Int.min
    private var lastLayoutSize: CGSize = .zero

    var buildOverlayLayers: (@MainActor (CGSize, CGFloat) -> [CALayer])?

    var player: AVPlayer? {
        didSet {
            guard playerLayer.player !== player else { return }
            playerLayer.player = player
            rebuildSyncLayer()
        }
    }

    /// The composition's output size — the source's native aspect ratio.
    var renderSize = CompositionBuilder.renderSize {
        didSet {
            guard renderSize != oldValue else { return }
            rebuildSyncLayer()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
    }

    /// Rebuilds the preview trees when the content revision changes.
    func setRevision(_ newRevision: Int) {
        guard newRevision != revision else { return }
        revision = newRevision
        rebuildSyncLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
        if bounds.size != lastLayoutSize {
            lastLayoutSize = bounds.size
            rebuildSyncLayer()
        }
    }

    /// The on-screen rect of the video. The composition's render size is
    /// known up front, so this is computable without waiting for the player
    /// to become ready for display.
    private var videoRect: CGRect {
        AVMakeRect(aspectRatio: renderSize, insideRect: bounds)
    }

    /// Tears down and rebuilds the synchronized layer with fresh preview
    /// trees, attached to the player's current item.
    private func rebuildSyncLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        syncLayer?.removeFromSuperlayer()
        syncLayer = nil
        guard let item = player?.currentItem, let buildOverlayLayers else { return }
        let rect = videoRect
        guard rect.width > 1, rect.height > 1 else { return }

        let sync = AVSynchronizedLayer(playerItem: item)
        sync.frame = rect
        let scale = window?.screen.scale ?? traitCollection.displayScale
        for sublayer in buildOverlayLayers(rect.size, scale) {
            sync.addSublayer(sublayer)
        }
        layer.addSublayer(sync)
        syncLayer = sync
    }
}
