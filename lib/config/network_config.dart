/// Network Configuration Policy
/// 
/// MANDATORY RULES:
/// 1. All HTTP requests MUST use HttpClientService.makeRequest()
/// 2. Direct http.get/post calls are FORBIDDEN
/// 3. Default maxRetries = 1 for idempotent operations  
/// 4. Default maxRetries = 0 for non-idempotent operations
/// 5. Use NetworkConfig constants for all timeout values
/// 
/// TIMEOUT VALUES:
/// - Profile sync: 30s (complex multi-field operations)
/// - File uploads: 60s (network-dependent transfers)
/// - Lightweight reads: 20s (simple queries)
/// - Default fallback: 25s
library;

class NetworkConfig {
  // Timeout values (in seconds)
  static const int profileSyncTimeout = 30;     // Learner profile operations
  static const int fileUploadTimeout = 60;      // Image/document uploads  
  static const int lightweightTimeout = 20;     // Simple GET requests
  static const int defaultTimeout = 25;         // Fallback value
  
  // Retry policies
  static const int syncOperationsMaxRetries = 1;    // Idempotent operations
  static const int nonIdempotentMaxRetries = 0;     // Writes/uploads
  static const int readOperationsMaxRetries = 1;    // GET requests
}