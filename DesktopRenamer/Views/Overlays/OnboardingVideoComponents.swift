import AVFoundation
import Cocoa
import SwiftUI

class AutoPlayingVideoNSView: NSView {
    private var looper: AVPlayerLooper?
    private var player: AVQueuePlayer?

    var playerLayer: AVPlayerLayer? {
        self.layer as? AVPlayerLayer
    }
    
    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.clear.cgColor
        return layer
    }
    
    func setupPlayer(with url: URL) {
        cleanup()
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
    }
}

struct AutoPlayingVideoView: NSViewRepresentable {
    let videoName: String
    
    func makeNSView(context: Context) -> AutoPlayingVideoNSView {
        let view = AutoPlayingVideoNSView()
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            view.setupPlayer(with: url)
        }
        return view
    }
    
    func updateNSView(_ nsView: AutoPlayingVideoNSView, context: Context) {}
    
    static func dismantleNSView(_ nsView: AutoPlayingVideoNSView, coordinator: Coordinator) {
        nsView.cleanup()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {}
}
