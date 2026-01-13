//
//  ContentView.swift
//  TinyPNG4Mac
//
//  Created by kyleduo on 2024/11/16.
//

import SwiftUI

struct MainContentView: View {
    @EnvironmentObject var appContext: AppContext
    @ObservedObject var vm: MainViewModel
    /// imageUrl : inputUrl
    @State private var dropResult: [URL: URL] = [:]
    @State private var showAlert = false
    @State private var showOpenPanel = false
    @State private var showRestoreAllConfirmAlert = false
    @State private var alertMessage: String? = nil
    @State private var rootSize: CGSize = CGSize.zero

    @AppStorage(AppConfig.key_saveMode) var saveMode: String = AppContext.shared.appConfig.saveMode

    var body: some View {
        ZStack {
            DropFileView(dropResult: $dropResult)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color("mainViewBackground"))

            VStack(spacing: 0) {
                Text("Tiny Image")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color("textMainTitle"))
                    .frame(height: 28)

                if vm.tasks.isEmpty {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(style: StrokeStyle(
                                lineWidth: 2,
                                dash: [8, 4]
                            ))
                            .foregroundColor(Color("textCaption"))
                            .padding(16)

                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color("textCaption"))
                                .frame(width: 60, height: 60)
                                .padding(.bottom, 12)

                            Text("Drop images or folders here!")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color("textBody"))

                            Text("Supports WebP, PNG, and JPEG images.")
                                .font(.system(size: 10))
                                .foregroundStyle(Color("textSecondary"))
                        }
                    }
                    .frame(idealWidth: 360, maxWidth: .infinity, idealHeight: 360, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(vm.tasks.indices, id: \.self) { index in
                            TaskRowView(vm: vm, task: $vm.tasks[index], last: index == vm.tasks.count - 1)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                    .clipped()
                    .frame(maxWidth: appContext.maxSize.width)
                    .scrollContentBackground(.hidden)
                    .listStyle(PlainListStyle())
                    .environment(\.defaultMinListRowHeight, 0)
                }

                // ═══════════════════════════════════════════════════════════
                // MARK: - 底部状态栏 (重构为2行逻辑分组)
                // ═══════════════════════════════════════════════════════════
                
                VStack(spacing: 0) {
                    // ─── 第一行: 统计 + 设置 ───────────────────────────────
                    HStack(spacing: 12) {
                        // 左侧: 任务统计 (只读信息)
                        HStack(spacing: 16) {
                            // 任务计数
                            Label {
                                Text("\(vm.tasks.count)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color("textSecondary"))
                            } icon: {
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color("textCaption"))
                            }
                            
                            // 完成计数
                            Label {
                                Text("\(vm.completedTaskCount)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color("textSecondary"))
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.green.opacity(0.8))
                            }
                            
                            // 节省大小
                            if vm.completedTaskCount > 0 {
                                let saved = Int64(vm.totalOriginSize) - Int64(vm.totalFinalSize)
                                if saved > 0 {
                                    Label {
                                        Text("-\(UInt64(saved).formatBytes())")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color.green)
                                    } icon: {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.green.opacity(0.8))
                                    }
                                }
                            }
                            
                            // 任务操作菜单 (放在统计信息旁边)
                            menuEntry()
                        }
                        
                        Spacer()
                        
                        // 右侧: 操作设置 (格式 + 保存模式)
                        HStack(spacing: 8) {
                            // 格式选择
                            Menu {
                                Button { vm.targetConvertType = nil } label: { Text("Keep origin") }
                                Divider()
                                Button { vm.targetConvertType = .auto } label: { Text("Auto") }
                                Divider()
                                ForEach(ImageType.allTypes, id: \.self) { type in
                                    Button { vm.targetConvertType = type } label: { Text(type.toDisplayName()) }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.badge.arrow.up")
                                        .font(.system(size: 10))
                                    Text(vm.convertTypeName)
                                        .font(.system(size: 11))
                                }
                                .foregroundStyle(Color("textSecondary"))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.05))
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            
                            // 保存模式
                            settingButton(useButtonStyle: false) {
                                HStack(spacing: 4) {
                                    Image(systemName: saveMode == AppConfig.saveModeNameOverwrite ? "doc.fill" : "folder.fill")
                                        .font(.system(size: 10))
                                    Text(LocalizedStringKey(saveMode))
                                        .font(.system(size: 11))
                                }
                                .foregroundStyle(Color("textSecondary"))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.05))
                                )
                            }
                            
                            // 输出文件夹按钮 - 使用 macOS 标准 .help()
                            if saveMode == AppConfig.saveModeNameSaveAs {
                                Button {
                                    if let outputDir = appContext.appConfig.outputDirectoryUrl {
                                        if outputDir.fileExists() {
                                            NSWorkspace.shared.open(outputDir)
                                        } else {
                                            alertMessage = String(localized: "The output directory does not exist.")
                                        }
                                    } else {
                                        vm.settingsNotReadyMessage = String(localized: "Output directory is not set.")
                                    }
                                } label: {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color("textSecondary"))
                                        .frame(width: 24, height: 24)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.white.opacity(0.05))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help(appContext.appConfig.outputDirectoryUrl?.rawPath() ?? "Output folder")
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    
                    // 分隔线 - 使用 macOS 标准 Divider
                    Divider()
                        .padding(.horizontal, 12)
                    
                    // ─── 第二行: API 状态 + 设置按钮 ─────────────────────────────
                    HStack(spacing: 8) {
                        // 自动密钥模式状态
                        if AppContext.shared.appConfig.autoKeyMode {
                            QuotaCapsuleView(usedQuota: vm.monthlyUsedQuota)
                            APIKeyStatusView()
                        } else {
                            let usedQuota = vm.monthlyUsedQuota >= 0 ? String(vm.monthlyUsedQuota) : "--"
                            Text("Compressed: \(usedQuota)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color("textCaption"))
                        }
                        
                        Spacer()
                        
                        // 设置按钮
                        settingButton(useButtonStyle: false) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 12))
                                .foregroundStyle(Color("textSecondary"))
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.05))
                                )
                        }
                        .help("Settings")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .coordinateSpace(name: "root")
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        rootSize = proxy.size
                    }
                    .onChange(of: proxy.size) { newSize in
                        rootSize = newSize
                    }
            }
        }
        .ignoresSafeArea()
        .onChange(of: dropResult) { newValue in
            if !newValue.isEmpty {
                dropResult = [:]
                vm.createTasks(imageURLs: newValue)
            }
        }
        .alert("Confirm to restore the image?",
               isPresented: Binding(
                   get: { vm.restoreConfirmTask != nil },
                   set: { if !$0 { } }
               ),
               actions: {
                   Button("Restore") { vm.restoreConfirmConfirmed() }
                   Button("Cancel", role: .cancel) { vm.restoreConfirmCancel() }
               },
               message: {
                   let path = vm.restoreConfirmTask == nil ? "" : vm.restoreConfirmTask?.originUrl.rawPath() ?? ""
                   Text("The image at \"\(path)\" will be replaced with the origin file.")
                       .font(.system(size: 12))
               }
        )
        .alert("The config is not ready",
               isPresented: Binding(
                   get: { vm.settingsNotReadyMessage != nil },
                   set: { if !$0 { vm.settingsNotReadyMessage = nil } }
               ),
               actions: {
                   settingButton(title: "Open Settings")
                   Button("Cancel", role: .cancel) { }
               },
               message: {
                   if let message = vm.settingsNotReadyMessage {
                       Text(message)
                   }
               }
        )
        .alert("Confirm to restore all the images?",
               isPresented: $showRestoreAllConfirmAlert,
               actions: {
                   Button("Restore") {
                       vm.restoreAll()
                   }
                   Button("Cancel", role: .cancel) { }
               },
               message: {
                   Text("All compressed images will be replaced with the origin file.")
               }
        )
        .alert("Confirm quit?",
               isPresented: $vm.showQuitWithRunningTasksAlert,
               actions: {
                   Button("Quit") {
                       vm.cancelAllTask()
                       NSApplication.shared.terminate(nil)
                   }
                   Button("Cancel", role: .cancel) {}
               },
               message: {
                   Text("There are ongoing tasks. Quitting will cancel them all.")
               })
        .alert(alertMessage ?? "",
               isPresented: Binding(
                   get: { alertMessage != nil },
                   set: { if !$0 { alertMessage = nil } }
               ),
               actions: {
                   Button("OK") { }
               }
        )
    }

    private func settingButton(title: String) -> some View {
        settingButton {
            Text(title)
        }
    }

    private func settingButton(useButtonStyle: Bool = true, @ViewBuilder view: () -> some View) -> some View {
        if #available(macOS 14.0, *) {
            AnyView(
                SettingsLink {
                    view()
                }
                .modifier(PlainButtonStyleModifier(plainButtonStyle: !useButtonStyle))
            )
        } else {
            AnyView(
                Button {
                    if #available(macOS 13.0, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                } label: {
                    view()
                }
                .modifier(PlainButtonStyleModifier(plainButtonStyle: !useButtonStyle))
            )
        }
    }

    private func menuEntry() -> some View {
        Menu {
            Button {
                vm.retryAllFailedTask()
            } label: {
                Text("Retry all failed tasks")
            }
            .disabled(vm.failedTaskCount == 0)

            Divider()

            Button {
                vm.clearAllTask()
            } label: {
                Text("Clear all tasks")
            }
            .disabled(vm.tasks.count == 0)

            Button {
                vm.clearFinishedTask()
            } label: {
                Text("Clear all finished tasks")
            }
            .disabled(vm.tasks.count == 0)

            Divider()

            Button {
                showRestoreAllConfirmAlert = true
            } label: {
                Text("Restore all compressed images")
            }
            .disabled(vm.completedTaskCount == 0)
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20, height: 20)
        .tint(Color("textSecondary"))
    }

    private func outputDirExist() -> Bool {
        if let outputDir = appContext.appConfig.outputDirectoryUrl {
            return outputDir.fileExists()
        }
        return false
    }
}

struct KeyValueLabel: View {
    var key: LocalizedStringKey
    var value: LocalizedStringKey

    var body: some View {
        HStack(spacing: 2) {
            Text(key)
                .font(.system(size: 12))
                .foregroundStyle(Color("textCaption"))

            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Color("textSecondary"))
        }
    }
}

struct PlainButtonStyleModifier: ViewModifier {
    var plainButtonStyle: Bool

    func body(content: Content) -> some View {
        if plainButtonStyle {
            content.buttonStyle(PlainButtonStyle())
        } else {
            content
        }
    }
}
