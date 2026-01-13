////
//  Settings.swift
//  TinyPNG4Mac
//
//  Created by kyleduo on 2024/12/1.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppConfig.key_apiKey) var apiKey: String = ""
    @AppStorage(AppConfig.key_autoKeyMode) var autoKeyMode: Bool = true

    @AppStorage(AppConfig.key_preserveCopyright) var preserveCopyright: Bool = false
    @AppStorage(AppConfig.key_preserveCreation) var preserveCreation: Bool = false
    @AppStorage(AppConfig.key_preserveLocation) var preserveLocation: Bool = false

    @AppStorage(AppConfig.key_concurrentTaskCount) var concurrentCount: Int = AppContext.shared.appConfig.concurrentTaskCount
    private let concurrentCountOptions = Array(1 ... 6)

    @AppStorage(AppConfig.key_saveMode) var saveMode: String = AppContext.shared.appConfig.saveMode
    private let saveModeOptions = AppConfig.saveModeKeys

    @AppStorage(AppConfig.key_outputDirectory)
    var outputDirectory: String = AppContext.shared.appConfig.outputDirectoryUrl?.rawPath() ?? ""

    @FocusState private var isTextFieldFocused: Bool

    @State private var failedToSelectOutputDirectory: Bool = false
    @State private var enableSaveAsModeAfterSelect: Bool = false
    @State private var showSelectOutputFolder: Bool = false

    @State private var contentSize: CGSize = CGSize.zero
    
    // 自动密钥模式状态
    @State private var availableKeyCount: Int = 0
    @State private var isApplyingKey: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            // Used to make sure content meature correctly
            ScrollView {
                // Content of Settings
                VStack(alignment: .leading) {
                    Text("TinyPNG")
                        .font(.system(size: 13, weight: .bold))

                    SettingsItem(title: "Auto Key Mode:", desc: "When enabled, API keys will be automatically applied and managed. No manual registration required.") {
                        Toggle("", isOn: $autoKeyMode)
                            .toggleStyle(.switch)
                            .onChange(of: autoKeyMode) { newValue in
                                if newValue {
                                    // 开启自动模式时，初始化密钥管理器
                                    TPClient.shared.initializeAutoKeyMode()
                                    updateKeyStatus()
                                }
                            }
                    }
                    
                    if autoKeyMode {
                        // 自动模式：显示密钥池状态
                        SettingsItem(title: "Key Status:", desc: "Available API keys in the pool. Keys are automatically applied when needed.") {
                            HStack {
                                Text("\(availableKeyCount) keys available")
                                    .foregroundColor(availableKeyCount > 0 ? .green : .red)
                                
                                Spacer()
                                
                                Button {
                                    applyNewKey()
                                } label: {
                                    if isApplyingKey {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Text("Apply New Key")
                                    }
                                }
                                .disabled(isApplyingKey)
                            }
                        }
                    } else {
                        // 手动模式：显示 API Key 输入框
                        SettingsItem(title: "API key:", desc: "Visit [https://tinypng.com/developers](https://tinypng.com/developers) to request an API key.") {
                            TextField("", text: $apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isTextFieldFocused)
                                .onAppear {
                                    isTextFieldFocused = false
                                }
                        }
                    }

                    SettingsItem(title: "Preserve:", desc: nil) {
                        VStack(alignment: .leading) {
                            Toggle("Copyright", isOn: $preserveCopyright)
                            Toggle("Creation", isOn: $preserveCreation)
                            Toggle("Location", isOn: $preserveLocation)
                        }
                    }

                    Spacer()
                        .frame(height: 16)

                    Text("Tasks")
                        .font(.system(size: 13, weight: .bold))

                    SettingsItem(title: "Concurrent tasks:", desc: nil) {
                        Picker("", selection: $concurrentCount) {
                            ForEach(concurrentCountOptions, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        }
                        .padding(.leading, -8)
                        .frame(maxWidth: 60)
                    }

                    SettingsItem(title: "Save Mode:", desc: "Overwrite Mode:\nThe compressed image will replace the original file. The original image is kept temporarily and can be restored before exit the app.\n\nSave As Mode:\nThe compressed image is saved as a new file, leaving the original image unchanged. You can choose where to save the compressed images.") {
                        Picker("", selection: $saveMode) {
                            ForEach(saveModeOptions, id: \.self) { mode in
                                Text(mode).tag(mode)
                            }
                        }
                        .padding(.leading, -8)
                        .frame(maxWidth: 120)
                    }

                    SettingsItem(title: "Output directory:", desc: "When \"Save As Mode\" is enabled, the compressed image will be saved to this directory. If a file with the same name exists, it will be overwritten.") {
                        HStack(alignment: .top) {
                            Text(outputDirectory.isEmpty ? "--" : outputDirectory)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                showSelectFolderPanel()
                            } label: {
                                Text("Select...")
                            }
                        }
                    }

                    if AppContext.shared.isDebug {
                        Button {
                            AppContext.shared.appConfig.clearOutputFolder()
                        } label: {
                            Text("[D]Clear output directory")
                        }
                    }
                }
                .padding(24)
                .frame(width: 540)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                contentSize = proxy.size
                            }
                            .onChange(of: proxy.size) { newSize in
                                contentSize = newSize
                            }
                    }
                }
            }
            .scrollDisabled(true)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color("settingViewBackground"))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color("settingViewBackgroundBorder"), lineWidth: 1)
                    }
            }
        }
        .padding(16)
        // Set the size of window.
        .frame(width: contentSize.width + 32, height: contentSize.height + 32)
        .onAppear {
            if autoKeyMode {
                updateKeyStatus()
            }
        }
        .onChange(of: saveMode) { newValue in
            if newValue == AppConfig.saveModeNameSaveAs && outputDirectory.isEmpty {
                saveMode = AppConfig.saveModeNameOverwrite
                enableSaveAsModeAfterSelect = true
                showSelectOutputFolder = true
            }
        }
        .onDisappear {
            if outputDirectory.isEmpty {
                AppContext.shared.appConfig.clearOutputFolder()
            }
            AppContext.shared.appConfig.update()
        }
        .alert("Failed to save output directory",
               isPresented: $failedToSelectOutputDirectory
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please select a different directory.")
        }
        .alert("Select output directory", isPresented: $showSelectOutputFolder) {
            Button("OK") {
                DispatchQueue.main.async {
                    enableSaveAsModeAfterSelect = false
                    showSelectFolderPanel()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Disable \"Overwrite Mode\" after selecting the output directory.")
        }
    }

    private func showSelectFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.prompt = "Select"

        panel.begin { result in
            if result == .OK, let url = panel.url {
                print("User Select: \(url.rawPath())")
                outputDirectory = url.rawPath()
            } else {
                print(\"User did not grant access.\")
            }
        }
    }
    
    // MARK: - Auto Key Mode Methods
    
    private func updateKeyStatus() {
        availableKeyCount = APIKeyManager.shared.availableKeyCount
    }
    
    private func applyNewKey() {
        isApplyingKey = true
        Task {
            do {
                try await APIKeyManager.shared.applyAndStoreKeys(times: 1)
                await MainActor.run {
                    updateKeyStatus()
                    isApplyingKey = false
                }
            } catch {
                print("[SettingsView] Failed to apply key: \(error.localizedDescription)")
                await MainActor.run {
                    isApplyingKey = false
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
