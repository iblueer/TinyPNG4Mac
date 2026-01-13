//
//  APIKeyStatusView.swift
//  TinyPNG4Mac
//
//  显示 API Key 状态的美观组件
//

import SwiftUI

struct APIKeyStatusView: View {
    @ObservedObject private var statusManager = APIKeyStatusManager.shared
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 主状态行 - 可点击展开
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    // 状态指示灯
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    
                    Text("Auto Keys")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color("textSecondary"))
                    
                    Text("\(statusManager.availableKeyCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statusColor)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Color("textCaption"))
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.05))
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // 展开后显示详细信息
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    // 最近日志
                    ForEach(statusManager.recentLogs.suffix(3), id: \.self) { log in
                        Text(log)
                            .font(.system(size: 9))
                            .foregroundStyle(Color("textCaption"))
                            .lineLimit(1)
                    }
                    
                    if statusManager.isApplying {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                            Text("Applying new key...")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.orange)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.2))
        )
    }
    
    private var statusColor: Color {
        if statusManager.isApplying {
            return .orange
        } else if statusManager.availableKeyCount > 0 {
            return .green
        } else {
            return .red
        }
    }
}

/// 剩余配额胶囊视图 - 显示当前 Key 的剩余可用量
struct QuotaCapsuleView: View {
    let usedQuota: Int
    private let maxQuota = 500 // 免费 Key 每月限额
    
    private var remainingQuota: Int {
        max(0, maxQuota - max(0, usedQuota))
    }
    
    private var quotaColor: Color {
        if usedQuota < 0 {
            return Color("textCaption") // 未知状态
        } else if remainingQuota > 100 {
            return .green
        } else if remainingQuota > 20 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var quotaText: String {
        if usedQuota < 0 {
            return "--"
        }
        return "\(remainingQuota)"
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // 配额图标
            Image(systemName: "bolt.fill")
                .font(.system(size: 9))
                .foregroundStyle(quotaColor)
            
            Text("Quota")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color("textSecondary"))
            
            Text(quotaText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(quotaColor)
            
            // 进度指示
            if usedQuota >= 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 4)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(quotaColor)
                            .frame(width: geo.size.width * CGFloat(remainingQuota) / CGFloat(maxQuota), height: 4)
                    }
                }
                .frame(width: 30, height: 4)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.05))
        )
    }
}

/// API Key 状态管理器 - 用于 UI 更新
class APIKeyStatusManager: ObservableObject {
    static let shared = APIKeyStatusManager()
    
    @Published var availableKeyCount: Int = 0
    @Published var recentLogs: [String] = []
    @Published var isApplying: Bool = false
    
    private init() {
        // 初始化时获取当前状态
        updateStatus()
    }
    
    func updateStatus() {
        DispatchQueue.main.async {
            self.availableKeyCount = APIKeyManager.shared.availableKeyCount
        }
    }
    
    func addLog(_ message: String) {
        DispatchQueue.main.async {
            // 添加时间戳
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            self.recentLogs.append("[\(timestamp)] \(message)")
            
            // 只保留最近 5 条
            if self.recentLogs.count > 5 {
                self.recentLogs.removeFirst()
            }
            
            self.updateStatus()
        }
    }
    
    func setApplying(_ applying: Bool) {
        DispatchQueue.main.async {
            self.isApplying = applying
        }
    }
}

#Preview {
    APIKeyStatusView()
        .padding()
        .background(Color("mainViewBackground"))
}
