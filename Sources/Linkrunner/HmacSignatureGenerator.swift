import Foundation
import CommonCrypto

public class HmacSignatureGenerator {
    // MARK: - Constants
    private static let HMAC_ALGORITHM = kCCHmacAlgSHA256
    
    // MARK: - Properties
    private let secretKey: String
    private let keyId: String
    
    // MARK: - Initialization
    public init(secretKey: String, keyId: String) {
        self.secretKey = secretKey
        self.keyId = keyId
    }
    
    // MARK: - Models
    public struct SignedRequest {
        public let signature: String
        public let timestamp: Int64
        public let keyId: String
    }
    
    // MARK: - Public Methods
    public func signRequest(
        payload: String?,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        onCanonicalString: ((String) -> Void)? = nil
    ) -> SignedRequest {
        // Calculate content hash if payload exists, otherwise use empty string
        let contentHash: String
        if let payload = payload, !payload.isEmpty {
            contentHash = sha256Hash(payload)
        } else {
            contentHash = ""
        }
        
        // Build the canonical string with timestamp and content hash
        let stringToSign = buildCanonicalString(timestamp: timestamp, contentHash: contentHash)
        onCanonicalString?(stringToSign)
        // Generate the signature
        let signature = generateHmac(data: stringToSign)
        
        return SignedRequest(signature: signature, timestamp: timestamp, keyId: keyId)
    }
    
    // MARK: - Private Methods
    private func buildCanonicalString(timestamp: Int64, contentHash: String) -> String {
        return "\(timestamp)\n\(contentHash)"
    }
    
    private func generateHmac(data: String) -> String {
        guard let dataBytes = data.data(using: .utf8) else {
            return ""
        }
        
        // Create a mutable pointer to hold the HMAC result
        let digestLength = Int(CC_SHA256_DIGEST_LENGTH)
        var hmacResult = [UInt8](repeating: 0, count: digestLength)
        
        // Calculate HMAC using a more compatible approach
        let keyData = Data(secretKey.utf8)
        
        keyData.withUnsafeBytes { keyBytes in
            dataBytes.withUnsafeBytes { dataBytes in
                let keyPtr = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                let dataPtr = dataBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyPtr, keyBytes.count,
                    dataPtr, dataBytes.count,
                    &hmacResult
                )
            }
        }
        
        // Convert to base64
        let hmacData = Data(hmacResult)
        return hmacData.base64EncodedString()
    }
    
    private func sha256Hash(_ data: String) -> String {
        guard let dataBytes = data.data(using: .utf8) else { return "" }
        
        var hashBytes = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        dataBytes.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hashBytes)
        }
        
        let hashData = Data(hashBytes)
        return hashData.base64EncodedString()
    }
}
