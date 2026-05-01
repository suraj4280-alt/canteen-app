import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api.dart';

class ApiService {
  static String? token;

  static void setToken(String newToken) {
    token = newToken;
  }

  static Map<String, String> getHeaders() {
    final headers = {
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/auth/login');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identifier': email, // Maps to backend LoginRequest
        'password': password,
      }),
    );
    
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      if (decoded['access_token'] != null) {
        setToken(decoded['access_token']);
      }
      return decoded;
    } else {
      throw Exception(decoded['detail'] ?? 'Login failed');
    }
  }

  static Future<List<dynamic>> getMeals() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/meals/slots');
    final response = await http.get(
      url,
      headers: getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('Failed to load meals');
    }
  }

  static Future<http.Response> createBooking(int slotId, String date, List<int> itemIds) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/bookings');
    final response = await http.post(
      url,
      headers: getHeaders(),
      body: jsonEncode({
        'slot_id': slotId,
        'date': date,
        'item_ids': itemIds,
      }),
    );
    return response;
  }

  static Future<Map<String, dynamic>> getQrData(int bookingId) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/tokens/qr-data/$bookingId');
    final response = await http.get(url, headers: getHeaders());
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load QR data');
    }
  }
}
