import SwiftUI
import AVKit
import AVFoundation

struct AnimatedSettingsValue: View {
    let text: String
    @State private var displayedText: String

    init(text: String) {
        self.text = text
        _displayedText = State(initialValue: text)
    }

    var body: some View {
        Text(displayedText)
            .monospacedDigit()
            .contentTransition(.numericText())
            .onChange(of: text) { newText in
                withSettingsAnimation {
                    displayedText = newText
                }
            }
    }
}

func withSettingsAnimation(_ action: () -> Void) {
    if #available(macOS 14.0, *) {
        withAnimation(.snappy(duration: 0.18)) {
            action()
        }
    } else {
        withAnimation(.easeOut(duration: 0.18)) {
            action()
        }
    }
}

class LoopVideoPlayerNSView: NSView {
    private var looper: AVPlayerLooper?
    private var player: AVQueuePlayer?
    private(set) var currentURL: URL?

    var playerLayer: AVPlayerLayer? {
        self.layer as? AVPlayerLayer
    }
    
    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.clear.cgColor
        return layer
    }
    
    func setupPlayer(with url: URL) {
        cleanup()
        self.currentURL = url
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        let player = AVQueuePlayer()
        let playerItem = AVPlayerItem(url: url)
        let playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        
        self.playerLayer?.player = player
        player.isMuted = true
        player.play()
        
        self.looper = playerLooper
        self.player = player
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        
        if let oldWindow = self.window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: oldWindow)
        }
        
        if let newWindow = newWindow {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: newWindow
            )
        } else {
            cleanup()
        }
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        cleanup()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func cleanup() {
        player?.pause()
        playerLayer?.player = nil
        looper = nil
        player = nil
        currentURL = nil
    }
    
    override func scrollWheel(with event: NSEvent) {
        self.nextResponder?.scrollWheel(with: event)
    }
}

struct LoopVideoPlayerRepresentable: NSViewRepresentable {
    let videoURL: URL
    
    func makeNSView(context: Context) -> LoopVideoPlayerNSView {
        let view = LoopVideoPlayerNSView()
        view.setupPlayer(with: videoURL)
        return view
    }
    
    func updateNSView(_ nsView: LoopVideoPlayerNSView, context: Context) {
        if nsView.currentURL != videoURL {
            nsView.setupPlayer(with: videoURL)
        }
    }
    
    static func dismantleNSView(_ nsView: LoopVideoPlayerNSView, coordinator: Coordinator) {
        nsView.cleanup()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {}
}

struct IsSettingsPreRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSettingsPreRendering: Bool {
        get { self[IsSettingsPreRenderingKey.self] }
        set { self[IsSettingsPreRenderingKey.self] = newValue }
    }
}

struct LoopVideoPlayerView: View {
    let videoURL: URL
    @Environment(\.isSettingsPreRendering) private var isPreRendering
    
    var body: some View {
        if isPreRendering {
            Color.clear
        } else {
            LoopVideoPlayerRepresentable(videoURL: videoURL)
        }
    }
}

struct SettingsTabKey: EnvironmentKey {
    static let defaultValue: SettingsTab = .general
}

extension EnvironmentValues {
    var settingsTab: SettingsTab {
        get { self[SettingsTabKey.self] }
        set { self[SettingsTabKey.self] = newValue }
    }
}
