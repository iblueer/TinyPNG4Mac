//
//  APIKeyManager.swift
//  TinyPNG4Mac
//
//  API 密钥管理器 - 自动申请、存储和管理 TinyPNG API 密钥
//

import Foundation

enum APIKeyError: LocalizedError {
    case registrationFailed(String)
    case emailReceiveFailed
    case linkExtractionFailed
    case keyGenerationFailed(String)
    case noAvailableKeys
    case rateLimited
    
    var errorDescription: String? {
        switch self {
        case .registrationFailed(let message):
            return "Registration failed: \(message)"
        case .emailReceiveFailed:
            return "Failed to receive registration email"
        case .linkExtractionFailed:
            return "Failed to extract login link from email"
        case .keyGenerationFailed(let message):
            return "Failed to generate API key: \(message)"
        case .noAvailableKeys:
            return "No available API keys"
        case .rateLimited:
            return "Rate limited, please try again later"
        }
    }
}

struct APIKeyStore: Codable {
    var available: [String]
    var unavailable: [String]
    
    init() {
        available = []
        unavailable = []
    }
}

class APIKeyManager {
    static let shared = APIKeyManager()
    
    private let snapMail = SnapMailService.shared
    private var keyStore = APIKeyStore()
    private let keysFilePath: URL
    
    /// 最小可用密钥数量，低于此值时自动申请新密钥
    private let minAvailableKeys = 3
    
    /// 密钥即将用尽的阈值（接近每月500次限制）
    private let quotaThreshold = 490
    
    private let session: URLSession
    
    private init() {
        // 设置密钥存储路径
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("TinyImage", isDirectory: true)
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        keysFilePath = appDir.appendingPathComponent("keys.json")
        
        // 配置 URLSession
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
        
        // 加载已存储的密钥
        loadKeys()
    }
    
    // MARK: - Public API
    
    /// 获取当前可用的 API 密钥
    var currentKey: String? {
        return keyStore.available.first
    }
    
    /// 可用密钥数量
    var availableKeyCount: Int {
        return keyStore.available.count
    }
    
    /// 已用尽密钥数量
    var unavailableKeyCount: Int {
        return keyStore.unavailable.count
    }
    
    /// 是否有可用密钥
    var hasAvailableKey: Bool {
        return !keyStore.available.isEmpty
    }
    
    /// 初始化密钥管理器，确保有足够的可用密钥
    func initialize() async throws {
        loadKeys()
        if keyStore.available.count < minAvailableKeys {
            print("[APIKeyManager] Available keys (\(keyStore.available.count)) < \(minAvailableKeys), applying new keys...")
            try await applyAndStoreKeys()
        }
    }
    
    /// 切换到下一个可用密钥
    /// - Returns: 新的可用密钥，如果没有可用密钥则返回 nil
    @discardableResult
    func switchToNextKey() async throws -> String? {
        loadKeys()
        
        // 将当前密钥移到不可用列表
        if let current = keyStore.available.first {
            keyStore.unavailable.append(current)
            keyStore.available.removeFirst()
            saveKeys()
            print("[APIKeyManager] Key switched, remaining: \(keyStore.available.count)")
        }
        
        // 检查是否需要申请新密钥
        if keyStore.available.count < minAvailableKeys {
            print("[APIKeyManager] Low on keys, applying new ones...")
            try await applyAndStoreKeys()
        }
        
        guard let newKey = keyStore.available.first else {
            throw APIKeyError.noAvailableKeys
        }
        
        return newKey
    }
    
    /// 申请并存储新密钥
    /// - Parameter times: 申请次数，默认为补足到 minAvailableKeys
    func applyAndStoreKeys(times: Int? = nil) async throws {
        let targetTimes = times ?? (minAvailableKeys - keyStore.available.count + 1)
        var remainingTimes = max(0, targetTimes)
        
        while remainingTimes > 0 {
            remainingTimes -= 1
            print("[APIKeyManager] Applying new key, remaining attempts: \(remainingTimes)")
            
            do {
                let key = try await applyNewAPIKey()
                keyStore.available.append(key)
                saveKeys()
                print("[APIKeyManager] Successfully applied new key")
            } catch {
                print("[APIKeyManager] Failed to apply key: \(error.localizedDescription)")
                // 如果是限流错误，等待后重试
                if case APIKeyError.rateLimited = error {
                    try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    remainingTimes += 1 // 不计入失败次数
                }
            }
        }
    }
    
    /// 检查密钥使用量，必要时触发后台密钥申请
    func checkQuotaAndPrepare(currentCount: Int) {
        if currentCount >= quotaThreshold && keyStore.available.count <= 1 {
            // 后台申请新密钥
            Task {
                try? await applyAndStoreKeys(times: 2)
            }
        }
    }
    
    // MARK: - Key Application Process
    
    /// 申请一个新的 API 密钥
    private func applyNewAPIKey() async throws -> String {
        // Step 1: 创建临时邮箱
        let mail = snapMail.createNewMail()
        let username = String(mail.prefix(while: { $0 != "@" }))
        
        // Step 2: 注册账号
        print("[APIKeyManager] Registering with email: \(mail)")
        try await registerAccount(email: mail, name: username)
        
        // Step 3: 等待邮件
        print("[APIKeyManager] Waiting for confirmation email...")
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        
        // Step 4: 获取确认链接
        let loginUrl = try await getLoginUrlFromEmail()
        print("[APIKeyManager] Got login URL")
        
        // Step 5: 登录并获取密钥
        let apiKey = try await loginAndGenerateKey(loginUrl: loginUrl)
        print("[APIKeyManager] Successfully generated API key")
        
        return apiKey
    }
    
    /// 向 TinyPNG 注册新账号
    private func registerAccount(email: String, name: String) async throws {
        let url = URL(string: "https://tinypng.com/web/api")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["fullName": name, "mail": email]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIKeyError.registrationFailed("Invalid response")
        }
        
        if httpResponse.statusCode == 429 {
            throw APIKeyError.rateLimited
        }
        
        if httpResponse.statusCode != 200 {
            let responseText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIKeyError.registrationFailed(responseText)
        }
    }
    
    /// 从邮件中提取登录链接
    private func getLoginUrlFromEmail() async throws -> String {
        let emails = try await snapMail.getEmailList(count: 1)
        
        guard let firstEmail = emails.first,
              let text = firstEmail["text"] as? String else {
            throw APIKeyError.emailReceiveFailed
        }
        
        // 使用正则表达式提取链接
        let pattern = #"(https://tinify\.com/login\?token=[^\s"']+api)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            throw APIKeyError.linkExtractionFailed
        }
        
        return String(text[range])
    }
    
    /// 登录并生成 API 密钥
    private func loginAndGenerateKey(loginUrl: String) async throws -> String {
        // Step 1: 访问登录链接获取 session
        guard let url = URL(string: loginUrl) else {
            throw APIKeyError.keyGenerationFailed("Invalid login URL")
        }
        
        // 使用共享的 cookie storage
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        let cookieSession = URLSession(configuration: config)
        
        // 访问登录链接
        let (_, _) = try await cookieSession.data(from: url)
        
        // Step 2: 获取认证 token
        let sessionUrl = URL(string: "https://tinify.com/web/session")!
        let (sessionData, _) = try await cookieSession.data(from: sessionUrl)
        
        guard let sessionJson = try? JSONSerialization.jsonObject(with: sessionData) as? [String: Any],
              let token = sessionJson["token"] as? String else {
            throw APIKeyError.keyGenerationFailed("Failed to get auth token")
        }
        
        // Step 3: 创建新密钥
        var createKeyRequest = URLRequest(url: URL(string: "https://api.tinify.com/api/keys")!)
        createKeyRequest.httpMethod = "POST"
        createKeyRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, createResponse) = try await cookieSession.data(for: createKeyRequest)
        
        guard let createHttpResponse = createResponse as? HTTPURLResponse,
              createHttpResponse.statusCode == 200 || createHttpResponse.statusCode == 201 else {
            throw APIKeyError.keyGenerationFailed("Failed to create key")
        }
        
        // Step 4: 获取密钥列表
        var getKeysRequest = URLRequest(url: URL(string: "https://api.tinify.com/api")!)
        getKeysRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (keysData, _) = try await cookieSession.data(for: getKeysRequest)
        
        guard let keysJson = try? JSONSerialization.jsonObject(with: keysData) as? [String: Any],
              let keys = keysJson["keys"] as? [[String: Any]],
              let lastKey = keys.last,
              let apiKey = lastKey["key"] as? String else {
            throw APIKeyError.keyGenerationFailed("Failed to extract API key")
        }
        
        return apiKey
    }
    
    // MARK: - Persistence
    
    private func loadKeys() {
        guard FileManager.default.fileExists(atPath: keysFilePath.path) else {
            keyStore = APIKeyStore()
            return
        }
        
        do {
            let data = try Data(contentsOf: keysFilePath)
            keyStore = try JSONDecoder().decode(APIKeyStore.self, from: data)
            print("[APIKeyManager] Loaded \(keyStore.available.count) available keys, \(keyStore.unavailable.count) unavailable keys")
        } catch {
            print("[APIKeyManager] Failed to load keys: \(error.localizedDescription)")
            keyStore = APIKeyStore()
        }
    }
    
    private func saveKeys() {
        do {
            let data = try JSONEncoder().encode(keyStore)
            try data.write(to: keysFilePath)
        } catch {
            print("[APIKeyManager] Failed to save keys: \(error.localizedDescription)")
        }
    }
}
