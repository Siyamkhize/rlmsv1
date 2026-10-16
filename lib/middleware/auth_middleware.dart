import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

/// Authentication middleware for protecting API routes with JWT tokens.
/// 
/// This middleware provides JWT token generation, validation, and route protection.
/// 
/// Usage:
/// ```dart
/// final authMiddleware = AuthMiddleware(jwtSecret: 'your-secret-key');
/// 
/// // Generate token after successful login
/// final token = authMiddleware.generateToken(userId);
/// 
/// // Protect routes
/// final handler = Pipeline()
///   .addMiddleware((innerHandler) {
///     return (request) async {
///       final authResponse = await authMiddleware.protectRoute(request);
///       if (authResponse.statusCode == 401) {
///         return authResponse;
///       }
///       // Pass userId to your handler via request context
///       return innerHandler(request);
///     };
///   })
///   .addHandler(yourRouteHandler);
/// ```
class AuthMiddleware {
  final String _jwtSecret;

  /// Creates an AuthMiddleware instance with the provided JWT secret.
  /// 
  /// [jwtSecret] should be a strong, randomly generated secret stored securely
  /// (e.g., in environment variables or secure configuration).
  /// Minimum recommended length: 32 characters.
  AuthMiddleware({required String jwtSecret}) : _jwtSecret = jwtSecret {
    if (jwtSecret.isEmpty) {
      throw ArgumentError('JWT secret cannot be empty');
    }
    if (jwtSecret.length < 32) {
      debugPrint('WARNING: JWT secret is shorter than recommended 32 characters');
    }
  }

  /// Generates a JWT token for the given user ID
  String generateToken(int userId, {Duration? expiresIn}) {
    final expiration = expiresIn ?? const Duration(hours: 24);
    final jwt = JWT(
      {
        'userId': userId,
        'iat': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        'exp': DateTime.now().toUtc().add(expiration).millisecondsSinceEpoch ~/ 1000,
      },
    );
    return jwt.sign(SecretKey(_jwtSecret));
  }

  /// Validates the JWT token and returns the decoded payload
  /// Returns null if token is invalid or expired
  Future<Map<String, dynamic>?> validateToken(String token) async {
    try {
      final jwt = JWT.verify(token, SecretKey(_jwtSecret));
      
      // Check if token is expired
      if (jwt.payload['exp'] != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(
          jwt.payload['exp'] * 1000,
          isUtc: true,
        );
        if (expiry.isBefore(DateTime.now().toUtc())) {
          return null;
        }
      }
      
      return jwt.payload as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Token validation failed: $e');
      return null;
    }
  }

  /// Middleware to protect routes
  /// 
  /// Usage: Pass the validated userId to your route handler via request context
  /// or by wrapping this middleware with shelf_router's Pipeline
  Future<Response> protectRoute(Request request) async {
    final authHeader = request.headers['Authorization'];
    
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return Response(
        401,
        body: jsonEncode({'error': 'Unauthorized - Missing or invalid Authorization header'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    
    final token = authHeader.substring(7);
    
    // Validate token is not empty after extracting
    if (token.isEmpty) {
      return Response(
        401,
        body: jsonEncode({'error': 'Unauthorized - Empty token'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    
    final payload = await validateToken(token);
    
    if (payload == null) {
      return Response(
        401,
        body: jsonEncode({'error': 'Unauthorized - Invalid or expired token'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    
    // Extract userId with type validation
    final userId = payload['userId'];
    if (userId == null || userId is! int) {
      return Response(
        401,
        body: jsonEncode({'error': 'Unauthorized - Invalid token payload'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    
    // Store user ID in request context for downstream handlers
    return Response(
      200,
      body: jsonEncode({'userId': userId}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
