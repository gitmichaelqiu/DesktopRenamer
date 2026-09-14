import SwiftUI

struct CommandBottomBar: View {
    @ObservedObject var viewModel: LauncherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var colors: ThemeColors {
        ThemeColors(isDark: colorScheme == .dark)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Left side: Active command pill matching Raycast look
            if let active = viewModel.activeCommand {
                HStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: active.iconName)
                            .font(.callout.weight(.medium))
                            .foregroundColor(Color.accentColor)
                        Text(active.title)
                            .font(.callout.weight(.medium))
                            .foregroundColor(colors.textSecondary)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))

                    if let staging = viewModel.stagingWindow, !viewModel.isSpaceMenuOpen {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(colors.textQuaternary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(colors.greenText)
                            Text(String(format: NSLocalizedString("Move: %@", comment: ""), staging.ownerName))
                                .font(.subheadline)
                                .foregroundColor(colors.textPrimary)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    }
                }
                .padding(LauncherLayout.bottomBarCapsulePadding)
                .launcherFrosted(in: Capsule())
            }
            
            Spacer()
            
            // Right side: Context-sensitive actions
            if let type = viewModel.activeCommand?.type {
                HStack(spacing: 2) {
                    switch type {
                case .switchToDesktop:
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Move Space Up"))
                            KeycapView(text: "⌘⇧↑", isSelected: false)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))

                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Move Space Down"))
                            KeycapView(text: "⌘⇧↓", isSelected: false)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))

                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Switch Space"))
                            KeycapView(text: "↵", isSelected: false)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.executeRowAction()
                        }
                    }

                case .moveWindow:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Move Window"))
                        KeycapView(text: "↵", isSelected: false)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeRowAction()
                    }

                case .listWindows:
                    if viewModel.stagingWindow != nil && !viewModel.isSpaceMenuOpen {
                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Move"))
                            KeycapView(text: "↵", isSelected: false)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.executeRowAction()
                        }
                    } else {
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Text(verbatim: String(localized: "Focus"))
                                KeycapView(text: "↵", isSelected: false)
                            }
                            .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.executeRowAction()
                            }
                            
                            HStack(spacing: 4) {
                                Text(verbatim: String(localized: "Actions"))
                                KeycapView(text: "⌘K", isSelected: false)
                            }
                            .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.showCommandKPanel()
                            }
                        }
                    }

                case .renameCurrentSpace:
                    HStack(spacing: 4) {
                        Text(verbatim: String(localized: "Rename Space"))
                        KeycapView(text: "↵", isSelected: false)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeRowAction()
                    }
                    
                default:
                    EmptyView()
                    }
                }
                .padding(LauncherLayout.bottomBarCapsulePadding)
                .launcherFrosted(in: Capsule())
            }
        }
        .padding(.horizontal, LauncherLayout.bottomBarHorizontalPadding)
        .padding(.vertical, LauncherLayout.bottomBarVerticalPadding)
        .frame(height: LauncherLayout.bottomBarHeight)
        .animation(LauncherAnimation.capsule, value: viewModel.stagingWindow?.id ?? 0)
    }
}
