import SwiftUI

struct OverscrollIndicatorView: View {
    enum Edge {
        case leading  // Leading screen edge
        case trailing // Trailing screen edge
    }
    
    let edge: Edge
    let progress: Double // 0.0 ... 1.0
    var isFadingOut: Bool = false
    
    private let size: CGFloat = 120
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: edge == .leading ? .leading : .trailing) {
                // Semi-circular background element
                Circle()
                    .fill(.regularMaterial)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 0)
                    .frame(width: size, height: size)
                    .offset(x: xOffset)
                    .opacity(isFadingOut ? 0 : 1)
                
                // Arrow
                Image(systemName: edge == .leading ? "arrow.right" : "arrow.left")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                    .opacity(isFadingOut ? 0 : arrowOpacity)
                    .scaleEffect(arrowScale)
                    .offset(x: arrowOffset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .leading ? .leading : .trailing)
            // Use explicit animation for the fade out transition
            .animation(.easeOut(duration: 0.2), value: isFadingOut)
            // Use interactive spring for the drag gesture
            .animation(isFadingOut ? nil : .interactiveSpring(), value: progress)
        }
    }
    
    // Animation logic for overscroll transitions.
    
    private var cappedProgress: Double {
        return min(max(progress, 0), 1.0)
    }
    
    private var xOffset: CGFloat {
        // Offset ranges from -size (fully hidden at progress 0) to -size/2 (half visible at progress 1).
        // Maintain position stability during fade-out.
        
        let move = (size / 2) * cappedProgress
        
        switch edge {
        case .leading:
            return -size + move
        case .trailing:
            return size - move
        }
    }
    
    private var arrowOpacity: Double {
        return cappedProgress
    }
    
    private var arrowScale: CGFloat {
        return 0.8 + (0.2 * cappedProgress)
    }
    
    private var arrowOffset: CGFloat {
        // Arrow follows the circle with a staggered delay.
        let baseOffset: CGFloat = edge == .leading ? -10 : 10
        let move: CGFloat = 20 * cappedProgress
        
        switch edge {
        case .leading:
            return baseOffset + move + (xOffset + size/2) // Align relative to circle center
        case .trailing:
            return baseOffset - move + (xOffset - size/2)
        }
    }
}
