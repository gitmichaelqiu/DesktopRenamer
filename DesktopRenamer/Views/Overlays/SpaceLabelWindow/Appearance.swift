import Cocoa
import Combine
import QuartzCore

extension SpaceLabelWindow {

    func refreshAppearance() {
        configureEffectView()
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
    /// layout role. Preview windows never pass through this path.
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

        updateLayout(isCurrentSpace: true, updateFrame: false)
        updateVisibility(animated: animated)
        bindToTargetSpace()
    }

    func setPreviewSize(_ size: NSSize) {
        if self.previewSize != size {
            self.previewSize = size
            if !isActiveMode {
                updateLayout(isCurrentSpace: false)
                updateVisibility(animated: false)
            }
        }
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
        // Inherit the effect view's appearance so the fallback label follows
        // the system's light/dark appearance changes.
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
