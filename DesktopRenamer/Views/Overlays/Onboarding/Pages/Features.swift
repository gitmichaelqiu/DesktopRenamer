import SwiftUI

struct SingleVideoFeaturePage: View {
    let title: String
    let subtitle: String
    let videoName: String
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
            }
            
            GeometryReader { geo in
                if videoName == "LockSpace" {
                    let r: CGFloat = 1660.0 / 1080.0
                    let targetHeight = geo.size.width / r
                    AutoPlayingVideoView(videoName: videoName)
                        .frame(width: geo.size.width, height: targetHeight)
                        .position(x: geo.size.width / 2, y: targetHeight / 2)
                } else {
                    AutoPlayingVideoView(videoName: videoName)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .padding(.top, 30)
    }
}

struct DoubleVideoFeaturePage: View {
    let title: String
    let subtitle: String
    let videoName1: String
    let videoName2: String
    let label1: String
    let label2: String
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
            }
            
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(label1)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    AutoPlayingVideoView(videoName: videoName1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                }
                
                VStack(spacing: 8) {
                    Text(label2)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    GeometryReader { geo in
                        if videoName2 == "ActiveLabel" {
                            let targetWidth = max(geo.size.width, geo.size.height * (1736.0 / 1080.0))
                            AutoPlayingVideoView(videoName: videoName2)
                                .frame(width: targetWidth, height: geo.size.height)
                                .position(x: geo.size.width - targetWidth / 2, y: geo.size.height / 2)
                        } else {
                            AutoPlayingVideoView(videoName: videoName2)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .padding(.top, 30)
    }
}
