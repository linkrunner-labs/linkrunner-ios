import Foundation
import CryptoKit

/// Simple SHA-256 hashing utility for LinkrunnerSDK
enum SHA256 {
    /// Hashes data using SHA-256 algorithm
    /// - Parameter data: The data to hash
    /// - Returns: The hashed data
    static func hash(data: Data) -> Data {
        return Data(CryptoKit.SHA256.hash(data: data))
    }
}
