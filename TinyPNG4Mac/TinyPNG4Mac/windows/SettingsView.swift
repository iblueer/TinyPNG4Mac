//
//  SettingsView.swift
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
    @State private var showSelectOutputFolder: Bool = false
    
    // 自动密钥模式状态
    @State private var availableKeyCount: Int = 0
    @State private var isApplyingKey: Bool = false

    var body: some View {
        Form {
            // MARK: - API Section
            Section {
                Toggle("Auto Key Mode", isOn: $autoKeyMode)
                    .onChange(of: autoKeyMode) { newValue in
                        if newValue {
                            TPClient.shared.initializeAutoKeyMode()
                            updateKeyStatus()
                        }
                    }
                
                if autoKeyMode {
                    HStack {
                        Text("Available Keys")
                        Spacer()
                        Text("\(availableKeyCount)")
                            .foregroundStyle(availableKeyCount > 0 ? .green : .red)
                            .fontWeight(.medium)
                        
                        Button {
                            applyNewKey()
                        } label: {
                            if isApplyingKey {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Text("Apply New")
                            }
                        }
                        .disabled(isApplyingKey)
                    }
                } else {
                    TextField("API Key", text: $apiKey)
                        .focused($isTextFieldFocused)
                        .onAppear { isTextFieldFocused = false }
                }
            } header: {
                Text("TinyPNG API")
            } footer: {
                if autoKeyMode {
                    Text("API keys are automatically applied and managed.")
                } else {
                    Text("Visit [tinypng.com/developers](https://tinypng.com/developers) to get an API key.")
                }
            }
            
            // MARK: - Metadata Section
            Section("Preserve Metadata") {
                Toggle("Copyright", isOn: $preserveCopyright)
                Toggle("Creation Date", isOn: $preserveCreation)
                Toggle("Location", isOn: $preserveLocation)
            }
            
            // MARK: - Tasks Section
            Section {
                Picker("Concurrent Tasks", selection: $concurrentCount) {
                    ForEach(concurrentCountOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                
                Picker("Save Mode", selection: $saveMode) {
                    ForEach(saveModeOptions, id: \.self) { mode in
                        Text(LocalizedStringKey(mode)).tag(mode)
                    }
                }
            } header: {
                Text("Tasks")
            } footer: {
                if saveMode == AppConfig.saveModeNameOverwrite {
                    Text("Compressed images replace originals. Originals can be restored before quitting.")
                } else {
                    Text("Compressed images are saved as new files.")
                }
            }
            
            // MARK: - Output Section
            if saveMode == AppConfig.saveModeNameSaveAs {
                Section("Output") {
                    HStack {
                        Text(outputDirectory.isEmpty ? "Not Set" : outputDirectory)
                            .foregroundStyle(outputDirectory.isEmpty ? .secondary : .primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Button("Select...") {
                            showSelectFolderPanel()
                        }
                    }
                }
            }
            
            // MARK: - Debug Section
            if AppContext.shared.isDebug {
                Section("Debug") {
                    Button("Clear Output Directory") {
                        AppContext.shared.appConfig.clearOutputFolder()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 480)
        .onAppear {
            if autoKeyMode {
                updateKeyStatus()
            }
        }
        .alert("Invalid Directory", isPresented: $failedToSelectOutputDirectory) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cannot use the app's internal directory. Please select a different location.")
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
                // 检查是否为无效目录
                let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? ""
                if url.path.hasPrefix(appSupportPath) {
                    failedToSelectOutputDirectory = true
                    return
                }
                outputDirectory = url.rawPath()
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
