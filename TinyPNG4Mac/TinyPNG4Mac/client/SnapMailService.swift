//
//  MailService.swift
//  TinyPNG4Mac
//
//  临时邮箱服务 - 使用 mail.tm REST API 生成临时邮箱并接收邮件
//  API 文档: https://docs.mail.tm / https://api.mail.tm
//
//  优势: 使用动态域名（如 virgilian.com），不易被封禁
//

import Foundation

enum MailServiceError: LocalizedError {
    case noEmailFound
    case networkError(String)
    case maxRetriesExceeded
    case parseError(String)
    case authFailed(String)
    case noDomainsAvailable
    
    var errorDescription: String? {
        switch self {
        case .noEmailFound:
            return "No emails found in mailbox"
        case .networkError(let message):
            return "Network error: \(message)"
        case .maxRetriesExceeded:
            return "Max retries exceeded"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .authFailed(let message):
            return "Authentication failed: \(message)"
        case .noDomainsAvailable:
            return "No email domains available"
        }
    }
}

class MailDropService {
    static let shared = MailDropService()
    
    private let apiURL = "https://api.mail.tm"
    private var currentEmail: String?
    private var currentPassword: String?
    private var currentToken: String?
    private var currentAccountId: String?
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }
    
    /// 生成一个新的随机临时邮箱地址
    func createNewMail() -> String {
        // 生成随机用户名和密码
        let letters = "abcdefghijklmnopqrstuvwxyz0123456789"
        let username = String((0..<10).map { _ in letters.randomElement()! })
        let password = String((0..<12).map { _ in letters.randomElement()! })
        
        currentPassword = password
        // 返回占位符，实际邮箱在 createAccount 时确定
        currentEmail = "\(username)@pending.tm"
        return currentEmail!
    }
    
    /// 获取当前邮箱地址
    func getCurrentMail() -> String {
        return currentEmail ?? createNewMail()
    }
    
    /// 创建邮箱账号并返回完整邮箱地址
    func createAccount() async throws -> String {
        // Step 1: 获取可用域名
        let domain = try await getAvailableDomain()
        
        // Step 2: 生成账号信息
        let letters = "abcdefghijklmnopqrstuvwxyz0123456789"
        let username = String((0..<10).map { _ in letters.randomElement()! })
        let password = String((0..<12).map { _ in letters.randomElement()! })
        let email = "\(username)@\(domain)"
        
        currentEmail = email
        currentPassword = password
        
        print("[MailService] Creating account: \(email)")
        
        // Step 3: 创建账号
        let url = URL(string: "\(apiURL)/accounts")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["address": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MailServiceError.networkError("Invalid response")
        }
        
        if httpResponse.statusCode != 201 && httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MailServiceError.networkError("Create account failed (\(httpResponse.statusCode)): \(errorText)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accountId = json["id"] as? String else {
            throw MailServiceError.parseError("Failed to parse account response")
        }
        
        currentAccountId = accountId
        
        // Step 4: 获取认证 token
        try await authenticate()
        
        print("[MailService] Account created successfully: \(email)")
        return email
    }
    
    /// 获取可用域名
    private func getAvailableDomain() async throws -> String {
        let url = URL(string: "\(apiURL)/domains")!
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MailServiceError.networkError("Failed to get domains")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let members = json["hydra:member"] as? [[String: Any]],
              let firstDomain = members.first,
              let domain = firstDomain["domain"] as? String else {
            throw MailServiceError.noDomainsAvailable
        }
        
        print("[MailService] Using domain: \(domain)")
        return domain
    }
    
    /// 认证并获取 token
    private func authenticate() async throws {
        guard let email = currentEmail, let password = currentPassword else {
            throw MailServiceError.authFailed("No credentials")
        }
        
        let url = URL(string: "\(apiURL)/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["address": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MailServiceError.authFailed(errorText)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            throw MailServiceError.parseError("Failed to parse token response")
        }
        
        currentToken = token
    }
    
    /// 获取邮件列表
    func getEmailList(maxRetries: Int = 10) async throws -> [[String: Any]] {
        guard let token = currentToken else {
            throw MailServiceError.authFailed("Not authenticated")
        }
        
        var retryCount = 0
        
        while retryCount <= maxRetries {
            let url = URL(string: "\(apiURL)/messages")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw MailServiceError.networkError("Failed to get messages")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let members = json["hydra:member"] as? [[String: Any]] else {
                throw MailServiceError.parseError("Failed to parse messages response")
            }
            
            if members.isEmpty {
                retryCount += 1
                if retryCount <= maxRetries {
                    print("[MailService] No emails yet, retrying in 3 seconds... (\(retryCount)/\(maxRetries))")
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }
                throw MailServiceError.noEmailFound
            }
            
            return members
        }
        
        throw MailServiceError.maxRetriesExceeded
    }
    
    /// 获取特定邮件的内容
    func getEmailContent(messageId: String) async throws -> [String: Any] {
        guard let token = currentToken else {
            throw MailServiceError.authFailed("Not authenticated")
        }
        
        let url = URL(string: "\(apiURL)/messages/\(messageId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MailServiceError.networkError("Failed to get message content")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MailServiceError.parseError("Failed to parse message content")
        }
        
        return json
    }
    
    /// 获取第一封邮件的文本内容
    func getFirstEmailText(maxRetries: Int = 10) async throws -> String {
        let emails = try await getEmailList(maxRetries: maxRetries)
        
        guard let firstEmail = emails.first,
              let messageId = firstEmail["id"] as? String else {
            throw MailServiceError.noEmailFound
        }
        
        let content = try await getEmailContent(messageId: messageId)
        
        // 优先返回 text，其次返回 html
        if let text = content["text"] as? String, !text.isEmpty {
            return text
        }
        if let html = content["html"] as? [[String: Any]], let firstHtml = html.first,
           let htmlContent = firstHtml["content"] as? String {
            return htmlContent
        }
        
        throw MailServiceError.parseError("Email has no content")
    }
}
