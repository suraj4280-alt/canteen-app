import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for all API communication and auth state.
class ApiService {
  // Configurable base URL — change via environment or build flavor
  static String baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: "http://10.99.182.8:8000",
  );

  /// HTTP timeout for all requests
  static const Duration _timeout = Duration(seconds: 15);

  // ── Token & User State ──────────────────────────────────────────────────────

  static String? _token;
  static String? _refreshToken;
  static Map<String, dynamic>? currentUser;

  static const String _tokenKey = 'api_access_token';
  static const String _refreshTokenKey = 'api_refresh_token';
  static const String _userKey = 'api_cached_user';

  // ── Init: call once at app startup ──────────────────────────────────────────

  /// Restores token + cached user from SharedPreferences.
  /// Returns true if a valid token exists (user is "logged in").
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_tokenKey);
    if (savedToken != null && savedToken.isNotEmpty) {
      _token = savedToken;
      _refreshToken = prefs.getString(_refreshTokenKey);
      final cachedUser = prefs.getString(_userKey);
      if (cachedUser != null) {
        currentUser = jsonDecode(cachedUser) as Map<String, dynamic>;
      }
      return true;
    }
    return false;
  }

  // ── Token Management ───────────────────────────────────────────────────────

  static void setToken(String newToken) {
    _token = newToken;
  }

  static String? get token => _token;

  static Future<void> _persistToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<void> _persistUser(Map<String, dynamic> user) async {
    currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<void> _persistRefreshToken(String token) async {
    _refreshToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, token);
  }

  // ── Headers ────────────────────────────────────────────────────────────────

  static Map<String, String> getHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  // ── Error Handling ─────────────────────────────────────────────────────────

  static void Function()? onTokenExpired;

  static bool _isRefreshing = false;

  static Future<bool> _tryRefresh() async {
    if (_refreshToken == null || _isRefreshing) return false;
    _isRefreshing = true;
    try {
      final url = Uri.parse('$baseUrl/api/auth/refresh');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': _refreshToken}),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await _persistToken(decoded['access_token'] as String);
        await _persistRefreshToken(decoded['refresh_token'] as String);
        _isRefreshing = false;
        return true;
      }
    } catch (_) {}
    _isRefreshing = false;
    return false;
  }

  /// Retry wrapper — executes [requestFn], and if it gets a 401,
  /// attempts a token refresh then retries ONCE with new headers.
  /// Wraps all calls with a timeout for production safety.
  static Future<http.Response> _withRetry(
    Future<http.Response> Function() requestFn,
  ) async {
    try {
      http.Response response = await requestFn().timeout(_timeout);
      if (response.statusCode == 401) {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          // Retry the request with the new token
          response = await requestFn().timeout(_timeout);
        } else {
          // Refresh failed — force logout
          await logout();
          if (onTokenExpired != null) onTokenExpired!();
          throw Exception('Session expired. Please login again.');
        }
      }
      return response;
    } on TimeoutException {
      throw Exception(
        'Server is not responding. Please check your connection.',
      );
    }
  }

  static String _extractError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded.containsKey('detail')) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is List) {
          return detail
              .map((e) => e is Map ? e['msg'] ?? e.toString() : e.toString())
              .join(', ');
        }
      }
      return 'Unknown error occurred';
    } catch (_) {
      return 'Network error or invalid server response';
    }
  }

  // ── Auth: Register ─────────────────────────────────────────────────────────

  static Future<String?> register({
    required String firstName,
    required String lastName,
    required String email,
    required String uid,
    required String hostel,
    required String password,
    String? middleName,
    String? phone,
    String? roomNumber,
  }) async {
    final url = Uri.parse('$baseUrl/api/auth/register');
    try {
      final body = <String, dynamic>{
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'uid': uid,
        'hostel': hostel,
        'password': password,
      };
      if (middleName != null && middleName.isNotEmpty) {
        body['middle_name'] = middleName;
      }
      if (phone != null && phone.isNotEmpty) {
        body['phone'] = phone;
      }
      if (roomNumber != null && roomNumber.isNotEmpty) {
        body['room_number'] = roomNumber;
      }

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode == 201) {
        return null; // Success
      } else {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['detail'] is List) {
          final errors = decoded['detail'] as List;
          final messages = errors
              .map((e) {
                if (e is Map && e['msg'] != null) return e['msg'];
                return e.toString();
              })
              .join(', ');
          return messages;
        }
        return decoded['detail']?.toString() ?? 'Registration failed';
      }
    } catch (e) {
      return 'Network error: ${e.toString().replaceAll('Exception: ', '')}';
    }
  }

  // ── Auth: Login ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(
    String identifier,
    String password,
  ) async {
    final url = Uri.parse('$baseUrl/api/auth/login');
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'identifier': identifier, 'password': password}),
          )
          .timeout(_timeout);

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final accessToken = decoded['access_token'] as String?;
        final refreshToken = decoded['refresh_token'] as String?;
        if (accessToken != null) {
          await _persistToken(accessToken);
        }
        if (refreshToken != null) {
          await _persistRefreshToken(refreshToken);
        }
        try {
          await fetchAndCacheUser();
        } catch (_) {}
        return decoded;
      } else {
        throw Exception(decoded['detail'] ?? 'Login failed');
      }
    } on TimeoutException {
      throw Exception(
        'Server is not responding. Please check your connection.',
      );
    }
  }

  // ── Auth: Get Current User ─────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> fetchAndCacheUser() async {
    try {
      final response = await _withRetry(
        () =>
            http.get(Uri.parse('$baseUrl/api/auth/me'), headers: getHeaders()),
      );
      if (response.statusCode == 200) {
        final user = jsonDecode(response.body) as Map<String, dynamic>;
        await _persistUser(user);
        return user;
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> getCurrentUser() async {
    if (currentUser != null) return currentUser;
    return await fetchAndCacheUser();
  }

  // ── Auth: Logout ───────────────────────────────────────────────────────────

  static Future<void> logout() async {
    // Try to notify the backend (best-effort)
    try {
      if (_token != null) {
        await http.post(
          Uri.parse('$baseUrl/api/auth/logout'),
          headers: getHeaders(),
        );
      }
    } catch (_) {}
    _token = null;
    _refreshToken = null;
    currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);
  }

  // ── Meals ──────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getMeals() async {
    final response = await _withRetry(
      () => http.get(
        Uri.parse('$baseUrl/api/meals/slots'),
        headers: getHeaders(),
      ),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception(_extractError(response));
    }
  }

  static Future<Map<String, dynamic>> getMenu(String date, int slotId) async {
    final response = await _withRetry(
      () => http.get(
        Uri.parse('$baseUrl/api/meals/menu?date=$date&slot_id=$slotId'),
        headers: getHeaders(),
      ),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(_extractError(response));
    }
  }

  // ── Bookings ───────────────────────────────────────────────────────────────

  static Future<http.Response> createBooking(
    int slotId,
    String date,
    List<int> itemIds,
  ) async {
    return await _withRetry(
      () => http.post(
        Uri.parse('$baseUrl/api/bookings'),
        headers: getHeaders(),
        body: jsonEncode({
          'slot_id': slotId,
          'date': date,
          'item_ids': itemIds,
        }),
      ),
    );
  }

  static Future<Map<String, dynamic>> getBookingHistory({
    int page = 1,
    int size = 50,
  }) async {
    final response = await _withRetry(
      () => http.get(
        Uri.parse('$baseUrl/api/bookings?page=$page&size=$size'),
        headers: getHeaders(),
      ),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(_extractError(response));
    }
  }

  static Future<http.Response> skipBooking(int bookingId, String reason) async {
    return await _withRetry(
      () => http.post(
        Uri.parse('$baseUrl/api/bookings/$bookingId/skip'),
        headers: getHeaders(),
        body: jsonEncode({'reason': reason}),
      ),
    );
  }

  static Future<http.Response> cancelBooking(int bookingId) async {
    return await _withRetry(
      () => http.delete(
        Uri.parse('$baseUrl/api/bookings/$bookingId'),
        headers: getHeaders(),
      ),
    );
  }

  static Future<http.Response> undoSkipBooking(int bookingId) async {
    return await _withRetry(
      () => http.delete(
        Uri.parse('$baseUrl/api/bookings/$bookingId/skip'),
        headers: getHeaders(),
      ),
    );
  }

  static Future<Map<String, dynamic>> getSlotStatus(String date) async {
    final response = await _withRetry(
      () => http.get(
        Uri.parse('$baseUrl/api/bookings/status?date=$date'),
        headers: getHeaders(),
      ),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(_extractError(response));
    }
  }

  // ── QR / Tokens ────────────────────────────────────────────────────────────

  static Future<http.Response> getBookingQR(int bookingId) async {
    return await _withRetry(
      () => http.get(
        Uri.parse('$baseUrl/api/bookings/$bookingId/qr'),
        headers: getHeaders(),
      ),
    );
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getBookingStats() async {
    final response = await _withRetry(
      () => http.get(
        Uri.parse('$baseUrl/api/bookings/stats'),
        headers: getHeaders(),
      ),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(_extractError(response));
    }
  }

  // ── Upcoming Bookings ─────────────────────────────────────────────────────

  static Future<List<dynamic>> getUpcomingBookings() async {
    final response = await _withRetry(
      () => http.get(
        Uri.parse('$baseUrl/api/bookings/upcoming'),
        headers: getHeaders(),
      ),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception(_extractError(response));
    }
  }

  // ── Feedback ──────────────────────────────────────────────────────────────

  static Future<http.Response> submitFeedback({
    required int bookingId,
    required int foodRating,
    required int serviceRating,
    required int cleanlinessRating,
    String? comment,
    List<int>? tagIds,
  }) async {
    final body = <String, dynamic>{
      'booking_id': bookingId,
      'food_rating': foodRating,
      'service_rating': serviceRating,
      'cleanliness_rating': cleanlinessRating,
    };
    if (comment != null && comment.isNotEmpty) body['comment'] = comment;
    if (tagIds != null && tagIds.isNotEmpty) body['tag_ids'] = tagIds;
    return await _withRetry(
      () => http.post(
        Uri.parse('$baseUrl/api/feedback'),
        headers: getHeaders(),
        body: jsonEncode(body),
      ),
    );
  }

  static Future<List<dynamic>> getFeedback() async {
    final response = await _withRetry(
      () => http.get(Uri.parse('$baseUrl/api/feedback'), headers: getHeaders()),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception(_extractError(response));
    }
  }

  // ── Profile Update ────────────────────────────────────────────────────────

  static Future<http.Response> updateProfile({
    String? phone,
    String? roomNumber,
    String? dietaryPreference,
  }) async {
    final body = <String, dynamic>{};
    if (phone != null) body['phone'] = phone;
    if (roomNumber != null) body['room_number'] = roomNumber;
    if (dietaryPreference != null)
      body['dietary_preference'] = dietaryPreference;
    return await _withRetry(
      () => http.put(
        Uri.parse('$baseUrl/api/auth/profile'),
        headers: getHeaders(),
        body: jsonEncode(body),
      ),
    );
  }

  // ── Feedback Tags ─────────────────────────────────────────────────────────

  static Future<List<dynamic>> getFeedbackTags() async {
    final response = await _withRetry(
      () => http.get(
        Uri.parse('$baseUrl/api/feedback/tags'),
        headers: getHeaders(),
      ),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception(_extractError(response));
    }
  }
}
