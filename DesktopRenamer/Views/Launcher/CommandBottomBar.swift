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
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: active.iconName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color.accentColor)
                        Text(active.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(colors.textPrimary)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: true, colorScheme: colorScheme))
                    
                    if let staging = viewModel.stagingWindow {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(colors.textQuaternary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(colors.greenText)
                            Text(String(format: NSLocalizedString("Move: %@", comment: ""), staging.ownerName))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(colors.textPrimary)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    }
                }
            }
            
            Spacer()
            
            // Right side: Context-sensitive actions
            if let type = viewModel.activeCommand?.type {
                switch type {
                case .switchToDesktop:
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Move Space Up"))
                            Text("⌘⇧↑")
                                .font(.system(.subheadline))
                                .fontWeight(.bold)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))

                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Move Space Down"))
                            Text("⌘⇧↓")
                                .font(.system(.subheadline))
                                .fontWeight(.bold)
                        }
                        .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))

                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Switch Space"))
                            Text("↵")
                                .font(.system(.subheadline))
                                .fontWeight(.bold)
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
                        Text("↵")
                            .font(.system(.subheadline))
                            .fontWeight(.bold)
                    }
                    .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.executeRowAction()
                    }

                case .listWindows:
                    if viewModel.stagingWindow != nil {
                        HStack(spacing: 4) {
                            Text(verbatim: String(localized: "Move"))
                            Text("↵")
                                .font(.system(.subheadline))
                                .fontWeight(.bold)
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
                                Text("↵")
                                    .font(.system(.subheadline))
                                    .fontWeight(.bold)
                            }
                            .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.executeRowAction()
                            }
                            
                            HStack(spacing: 4) {
                                Text(verbatim: String(localized: "Move"))
                                Text("⌘M")
                                    .font(.system(.subheadline))
                                    .fontWeight(.bold)
                            }
                            .modifier(BottomBarCapsule(isSelected: false, isActive: false, colorScheme: colorScheme))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let window = viewModel.selectedWindowForListWindows {
                                    viewModel.batchMoveLastSelectedIndex = viewModel.selectedRowIndex
                                    viewModel.stagingWindow = window
                                    viewModel.isExecutingRestoreToImmediately = true
                                    viewModel.selectedRowIndex = 0
                                }
                            }
                            
                            HStack(spacing: 4) {
                                Text(verbatim: String(localized: "Actions"))
                                Text("⌘K")
                                    .font(.system(.subheadline))
                                    .fontWeight(.bold)
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
                        Text("↵")
                            .font(.system(.subheadline))
                            .fontWeight(.bold)
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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(colors.bottomBarBg)
    }
}
