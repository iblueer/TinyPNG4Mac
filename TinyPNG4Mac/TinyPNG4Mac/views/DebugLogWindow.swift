//
//  DebugLogWindow.swift
//  TinyPNG4Mac
//
//  独立的调试日志浮动窗口
//

import SwiftUI
import AppKit

/// 调试日志窗口控制器
class DebugLogWindowController: NSWindowController {
    static let shared = DebugLogWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "Debug Log"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: DebugLogPanelView())
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showNextToMainWindow() {
        guard let mainWindow = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            window?.center()
            showWindow(nil)
            return
        }
        
        // 定位到主窗口右侧
        let mainFrame = mainWindow.frame
        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 400
        let x = mainFrame.maxX + 10
        let y = mainFrame.minY + (mainFrame.height - panelHeight) / 2
        
        window?.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        showWindow(nil)
    }
}

/// 调试日志面板视图
struct DebugLogPanelView: View {
    @ObservedObject private var debugVM = DebugViewModel.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 工具栏
            HStack {
                Text("Debug Log")
                    .font(.headline)
                
                Spacer()
                
                Button("Clear") {
                    debugVM.debugMessages.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(8)
            
            Divider()
            
            // 日志列表
            if debugVM.debugMessages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No log messages")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(debugVM.debugMessages.enumerated()), id: \.offset) { index, msg in
                                Text(msg)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .id(index)
                            }
                        }
                    }
                    .onChange(of: debugVM.debugMessages.count) { _ in
                        // 自动滚动到底部
                        if let lastIndex = debugVM.debugMessages.indices.last {
                            withAnimation {
                                proxy.scrollTo(lastIndex, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 280, minHeight: 200)
    }
}
