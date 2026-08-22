import SwiftUI

struct SliderSettingsRow<V>: View where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
    let title: LocalizedStringResource
    @Binding var value: V
    let range: ClosedRange<V>
    let defaultValue: V
    let step: V?
    let helperText: LocalizedStringKey?
    let warningText: LocalizedStringKey?
    let demoVideoName: String?
    let valueString: (V) -> String

    @AppStorage("ShowDemoVideos") private var showDemoVideos = true
    @Environment(\.settingsTab) var currentTab
    @Environment(\.isSettingsPreRendering) private var isPreRendering
    @EnvironmentObject var navigationState: SettingsNavigationState
    @State private var resetTask: Task<Void, Never>?

    init(
        _ title: LocalizedStringResource,
        helperText: LocalizedStringKey? = nil,
        warningText: LocalizedStringKey? = nil,
        demoVideoName: String? = nil,
        value: Binding<V>,
        range: ClosedRange<V>,
        defaultValue: V,
        step: V? = nil,
        valueString: @escaping (V) -> String = { String(format: "%.2f", Double($0)) }
    ) {
        self.title = title
        self.helperText = helperText
        self.warningText = warningText
        self.demoVideoName = demoVideoName
        self._value = value
        self.range = range
        self.defaultValue = defaultValue
        self.step = step
        self.valueString = valueString
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Text(highlightedText(text: String(localized: title), query: navigationState.searchText))
                    if let helperText = helperText {
                        HelperInfoButton(text: helperText)
                    }
                    if let warningText = warningText {
                        WarningInfoButton(text: warningText)
                    }
                }

                Spacer()

                Button("↺") {
                    resetTask?.cancel()
                    let start = Double(value)
                    let end = Double(defaultValue)
                    resetTask = Task { @MainActor in
                        let steps = 40
                        let startTime = DispatchTime.now().uptimeNanoseconds
                        let duration: UInt64 = 150_000_000
                        for step in 1...steps {
                            guard !Task.isCancelled else { return }
                            let targetTime = startTime + duration * UInt64(step) / UInt64(steps)
                            let currentTime = DispatchTime.now().uptimeNanoseconds
                            if targetTime > currentTime {
                                try? await Task.sleep(nanoseconds: targetTime - currentTime)
                            }
                            guard !Task.isCancelled else { return }
                            let linearProgress = Double(step) / Double(steps)
                            let progress = 1 - (1 - linearProgress) * (1 - linearProgress) * (1 - linearProgress)
                            withSettingsAnimation {
                                value = V(start + (end - start) * progress)
                            }
                        }
                        resetTask = nil
                    }
                }
                .help("Reset to default")
                .disabled(abs(value - defaultValue) < 0.001)
            }

            HStack {
                Group {
                    if let step = step {
                        Slider(value: animatedValueBinding, in: range, step: V.Stride(step))
                    } else {
                        Slider(value: animatedValueBinding, in: range)
                    }
                }

                AnimatedSettingsValue(text: valueString(value))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 50, alignment: .trailing)
            }

            if showDemoVideos,
               let videoName = demoVideoName,
               let videoURL = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
                LoopVideoPlayerView(videoURL: videoURL)
                    .frame(height: 180)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .id(title.key)
        .onAppear {
            navigationState.register(title: title.key, tab: currentTab)
        }
        .onDisappear {
            if !isPreRendering {
                navigationState.unregister(title: title.key, tab: currentTab)
            }
        }
    }

    private var animatedValueBinding: Binding<V> {
        Binding(
            get: { value },
            set: { newValue in
                withSettingsAnimation {
                    value = newValue
                }
            }
        )
    }
}
