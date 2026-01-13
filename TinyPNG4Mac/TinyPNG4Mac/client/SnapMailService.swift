//
//  SnapMailService.swift
//  TinyPNG4Mac
//
//  临时邮箱服务 - 使用 snapmail.cc 生成临时邮箱并接收邮件
//

import Foundation

enum SnapMailError: LocalizedError {
    case noEmailFound
    case requestTooFrequent
    case networkError(String)
    case maxRetriesExceeded
    
    var errorDescription: String? {
        switch self {
        case .noEmailFound:
            return "No emails found in mailbox"
        case .requestTooFrequent:
            return "Request too frequent, please try again later"
        case .networkError(let message):
            return "Network error: \(message)"
        case .maxRetriesExceeded:
            return "Max retries exceeded"
        }
    }
}

class SnapMailService {
    static let shared = SnapMailService()
    
    private let baseURL = "https://www.snapmail.cc"
    private var currentMail: String?
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }
    
    /// 生成一个新的随机临时邮箱地址
    func createNewMail() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let randomString = String((0..<16).map { _ in letters.randomElement()! })
        currentMail = "\(randomString)@snapmail.cc"
        return currentMail!
    }
    
    /// 获取当前邮箱地址
    func getCurrentMail() -> String {
        if currentMail == nil {
            return createNewMail()
        }
        return currentMail!
    }
    
    /// 获取邮件列表
    /// - Parameters:
    ///   - count: 要获取的邮件数量
    ///   - maxRetries: 最大重试次数
    /// - Returns: 邮件内容数组
    func getEmailList(count: Int = 1, maxRetries: Int = 3) async throws -> [[String: Any]] {
        guard let mail = currentMail else {
            _ = createNewMail()
            return try await getEmailList(count: count, maxRetries: maxRetries)
        }
        
        var retryCount = 0
        var lastError: Error?
        
        while retryCount <= maxRetries {
            do {
                let result = try await fetchEmailList(mail: mail, count: count)
                return result
            } catch let error as SnapMailError {
                lastError = error
                switch error {
                case .noEmailFound, .requestTooFrequent:
                    retryCount += 1
                    if retryCount <= maxRetries {
                        print("[SnapMail] Retrying in 10 seconds... (\(retryCount)/\(maxRetries))")
                        try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    }
                default:
                    throw error
                }
            } catch {
                lastError = error
                retryCount += 1
                if retryCount <= maxRetries {
                    print("[SnapMail] Error: \(error.localizedDescription), retrying...")
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                }
            }
        }
        
        throw lastError ?? SnapMailError.maxRetriesExceeded
    }
    
    private func fetchEmailList(mail: String, count: Int) async throws -> [[String: Any]] {
        var urlComponents = URLComponents(string: "\(baseURL)/emailList/\(mail)")!
        urlComponents.queryItems = [URLQueryItem(name: "count", value: String(count))]
        
        guard let url = urlComponents.url else {
            throw SnapMailError.networkError("Invalid URL")
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SnapMailError.networkError("Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            // 尝试解析错误信息
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMsg = json["error"] as? String {
                if errorMsg.contains("Email was not found") {
                    throw SnapMailError.noEmailFound
                } else if errorMsg.contains("Please try again") {
                    throw SnapMailError.requestTooFrequent
                }
                throw SnapMailError.networkError(errorMsg)
            }
            throw SnapMailError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SnapMailError.networkError("Failed to parse response")
        }
        
        return json
    }
}
