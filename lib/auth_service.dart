import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _usersKey = 'all_users_list';
  static const String _currentUserKey = 'current_user_uid';
  static Map<String, dynamic>? currentUser;

  // Get all users
  static Future<List<Map<String, dynamic>>> _getAllUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final String? usersJson = prefs.getString(_usersKey);
    if (usersJson == null) return [];

    final List<dynamic> decodedList = jsonDecode(usersJson);
    return decodedList.map((e) => e as Map<String, dynamic>).toList();
  }

  // Register a new user
  static Future<String?> registerUser({
    required String firstName,
    required String middleName,
    required String lastName,
    required String email,
    required String phone,
    required String uid,
    required String hostel,
    required String room,
    required String password,
  }) async {
    final users = await _getAllUsers();

    // Check for duplicates
    for (var u in users) {
      if (u['uid'] == uid) return 'A user with this UID already exists.';
      if (u['email'] == email) return 'A user with this email already exists.';
    }

    final newUser = {
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'uid': uid,
      'hostel': hostel,
      'room': room,
      'password': password,
    };

    users.add(newUser);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usersKey, jsonEncode(users));

    return null; // Null means success
  }

  // Login
  static Future<String?> login(String identifier, String password) async {
    final users = await _getAllUsers();

    if (users.isEmpty) return 'No accounts found. Please register first.';

    for (var u in users) {
      if (u['uid'] == identifier || u['email'] == identifier) {
        if (u['password'] == password) {
          // Success
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_currentUserKey, u['uid']);
          currentUser = u;
          return null;
        } else {
          return 'Incorrect password.';
        }
      }
    }

    return 'Account not found. Please check your credentials or register.';
  }

  // Check session
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_currentUserKey);
    if (uid != null) {
      currentUser = await getCurrentUser();
      return true;
    }
    return false;
  }

  // Get current user details
  static Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUid = prefs.getString(_currentUserKey);
    if (currentUid == null) return null;

    final users = await _getAllUsers();
    for (var u in users) {
      if (u['uid'] == currentUid) {
        return u;
      }
    }
    return null;
  }

  // Logout
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserKey);
    currentUser = null;
  }
}
