import Cocoa
import Combine
import QuartzCore

extension SpaceLabelWindow {

    func refreshAppearance() {
        configureEffectView()
        if !isActiveMode && SpaceHelper.getVisibleSystemSpaceIDs().contains(spaceId) {
            updateLayout(isCurrentSpace: false, updateFrame: false)
            hideImmediately()
            return
        }
        if isActiveMode && !isCurrentSpaceLabel {
            updateLayout(isCurrentSpace: true, updateFrame: false)
            alphaValue = 0.0
            contentView?.alphaValue = 0.0
            orderOut(nil)
            return
        }
        updateInteractivity()
        updateLayout(isCurrentSpace: self.isActiveMode)
        updateVisibility(animated: true)
    }

    /// Shows or hides a dedicated active-label window without changing its
    /// active layout into the preview layout.
    func setActiveVisibility(_ isVisible: Bool, animated: Bool) {
        guard isActiveMode else { return }

        pendingVisibilityTask?.cancel()
        pendingVisibilityTask = nil
        isCurrentSpaceLabel = isVisible

        guard isVisible else {
            alphaValue = 0.0
            contentView?.alphaValue = 0.0
            orderOut(nil)
            return
        }

        // Each space has its own active-label window. Reload the shared
        // position/docking state before laying out this window; otherwise a
        // window created on launch keeps the state it had when it was created.
        syncFromGlobalState()
        updateLayout(isCurrentSpace: true, updateFrame: false)
        updateVisibility(animated: animated)
        bindToTargetSpace()
    }

    func setPreviewSize(_ size: NSSize) {
        if self.previewSize != size {
            self.previewSize = size
            if !isActiveMode {
                if SpaceHelper.getVisibleSystemSpaceIDs().contains(spaceId) {
                    hideImmediately()
                } else {
                    updateLayout(isCurrentSpace: false)
                    updateVisibility(animated: false)
                }
            }
        }
    }

    func setMode(isCurrentSpace: Bool) {
        if self.isActiveMode != isCurrentSpace {
            print("SpaceLabelWindow[\(self.spaceId)]: setMode(isCurrentSpace: \(isCurrentSpace))")
        }

        let wasAnchor = self.isInvisibleAnchorMode
        let wasHidden = self.contentView?.alphaValue == 0

        // Pre-calculate visibility to avoid "flashing" or "stuttering" during mode change
        let willBeVisible = isCurrentSpace ? (labelManager?.showActiveLabels ?? true) : (labelManager?.showPreviewLabels ?? true)

        self.isActiveMode = isCurrentSpace
        self.isInvisibleAnchorMode = !willBeVisible
        configureEffectView()

        if isCurrentSpace {
            syncFromGlobalState()
            if let manager = labelManager, !manager.showOnDesktop {
                self.isDocked = true
            }
        }

        // We only animate the transition if the window was ALREADY visible as a preview window
        // and is now becoming an active window (shrinking/docking).
        // If it was an invisible anchor or explicitly hidden via hideImmediately, we snap it.
        let shouldAnimate = isCurrentSpace ? (!wasAnchor && !wasHidden) : true

        self.updateLayout(isCurrentSpace: isCurrentSpace, updateFrame: shouldAnimate)
        updateVisibility(animated: shouldAnimate)
        updateInteractivity()
    }

    private func shouldUseGlassEffect() -> Bool {
        guard #available(macOS 26.0, *) else { return false }
        if isActiveMode {
            return labelManager?.disableActiveLiquidGlass != true
        }
        return labelManager?.disablePreviewLiquidGlass != true
    }

    func configureEffectView(force: Bool = false) {
        let shouldUseGlass = shouldUseGlassEffect()
        guard force || isUsingGlassEffect != shouldUseGlass else { return }

        let alpha = self.contentView?.alphaValue ?? 1
        NSLayoutConstraint.deactivate(contentContainerConstraints)
        contentContainerConstraints.removeAll()
        contentContainer.removeFromSuperview()

        let rootContentView: NSView
        if shouldUseGlass {
            if #available(macOS 26.0, *) {
                let glassView = NSGlassEffectView(frame: .zero)
                glassView.contentView = self.contentContainer
                rootContentView = glassView
            } else {
                rootContentView = makeVisualEffectView()
            }
        } else {
            rootContentView = makeVisualEffectView()
        }

        rootContentView.wantsLayer = true
        rootContentView.layer?.cornerRadius = 20
        rootContentView.layer?.masksToBounds = true
        rootContentView.alphaValue = alpha

        self.contentView = rootContentView
        isUsingGlassEffect = shouldUseGlass
    }

    private func makeVisualEffectView() -> NSVisualEffectView {
        let effectView = NSVisualEffectView(frame: .zero)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        // Inherit the window's effective appearance so the fallback label updates
        // when the system switches between Light and Dark mode.
        effectView.appearance = nil
        effectView.addSubview(self.contentContainer)

        self.contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainerConstraints = [
            self.contentContainer.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            self.contentContainer.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            self.contentContainer.topAnchor.constraint(equalTo: effectView.topAnchor),
            self.contentContainer.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ]
        NSLayoutConstraint.activate(contentContainerConstraints)
        return effectView
    }
}
