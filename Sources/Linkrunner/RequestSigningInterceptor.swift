import Foundation

public class RequestSigningInterceptor: NSObject {
    // MARK: - Constants
    private static let AUTHORIZATION_HEADER = "Authorization"
    private static let TIMESTAMP_HEADER = "x-Timestamp"
    private static let SIGNATURE_HEADER = "x-Signature"
    private static let KEY_ID_HEADER = "x-Key-Id"
    
    // MARK: - Properties
    // Set from initialize while other calls are signing requests on other threads.
    @Synchronized private var generator: HmacSignatureGenerator? = nil
    
    // Dedicated URLSession for the SDK to avoid interference with app's networking
    private let sdkSession: URLSession
    
    // MARK: - Initialization
    public override init() {
        // Create a dedicated URLSession with ephemeral configuration for the SDK
        // This ensures it doesn't share cookies, cache or credentials with the app's sessions
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30.0
        
        self.sdkSession = URLSession(configuration: config)
        super.init()
    }
    
   
    /// Configure the interceptor with the necessary credentials using raw data
    /// - Parameters:
    ///   - secretKeyData: The raw secret key data
    ///   - keyId: The key ID for signing requests
    public func configure(secretKey: String, keyId: String) {
        self.generator = HmacSignatureGenerator(secretKey: secretKey, keyId: keyId)
    }
    
    /// Reset the interceptor configuration
    public func reset() {
        self.generator = nil
    }
    
    // MARK: - Request Signing Methods
    
    /// Sign a URL request with HMAC authentication
    /// - Parameter request: The original request to sign
    /// - Returns: A signed copy of the request, or the original if signing fails or credentials aren't set
    public func signRequest(_ request: URLRequest) -> URLRequest {
        // If the generator is not configured (no credentials set), return the original request
        guard let generator = self.generator else {
            return request
        }
        
        var requestBody: String? = nil
        
        if let bodyData = request.httpBody {
            requestBody = String(data: bodyData, encoding: .utf8)
        }
        
        let signedData = generator.signRequest(payload: requestBody)
        
        return addSignatureHeaders(
            originalRequest: request,
            signature: signedData.signature,
            timestamp: signedData.timestamp,
            keyId: signedData.keyId
        )
    }
    
    // MARK: - Private Methods
    
    /// Add signature headers to the request
    /// - Parameters:
    ///   - originalRequest: The original request
    ///   - signature: The generated signature
    ///   - timestamp: The timestamp used for signing
    ///   - keyId: The key ID the signature was made with
    /// - Returns: A new request with signature headers
    private func addSignatureHeaders(
        originalRequest: URLRequest,
        signature: String,
        timestamp: Int64,
        keyId: String
    ) -> URLRequest {
        var request = originalRequest
        request.setValue("HMAC", forHTTPHeaderField: RequestSigningInterceptor.AUTHORIZATION_HEADER)
        request.setValue(keyId, forHTTPHeaderField: RequestSigningInterceptor.KEY_ID_HEADER)
        request.setValue(String(timestamp), forHTTPHeaderField: RequestSigningInterceptor.TIMESTAMP_HEADER)
        request.setValue(signature, forHTTPHeaderField: RequestSigningInterceptor.SIGNATURE_HEADER)
        return request
    }
}

// MARK: - Request Signing Methods

@available(iOS 15.0, macOS 12.0, watchOS 8.0, tvOS 15.0, *)
extension RequestSigningInterceptor {
    /// Sign and send a request using the SDK's dedicated URLSession
    /// - Parameter request: The request to sign and send
    /// - Returns: A tuple containing Data and URLResponse
    public func signAndSendRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let signedRequest = signRequest(request)
        
        let (data, response) = try await sdkSession.data(for: signedRequest)
        
        return (data, response)
    }
}
