////
//  DebugViewModel.swift
//  TinyPNG4Mac
//
//  Created by kyleduo on 2025/1/12.
//

import SwiftUI

class DebugViewModel: ObservableObject {
    static let shared = DebugViewModel()

    @Published var debugMessages: [String] = []
    @Published var apiKeyLogs: [String] = []
    
    func addAPIKeyLog(_ message: String) {
        DispatchQueue.main.async {
            self.apiKeyLogs.append(message)
            // 只保留最近 10 条日志
            if self.apiKeyLogs.count > 10 {
                self.apiKeyLogs.removeFirst()
            }
        }
    }
}
