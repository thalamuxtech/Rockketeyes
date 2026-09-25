import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/env.dart';

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  bool get isNetwork => status == 0;

  @override
  String toString() => 'ApiException($status, $code, $message)';
}

/// Thin client for the `api` Cloud Function.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final http.Client _http = http.Client();
  static bool appCheckEnabled = false;

  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    if (appCheckEnabled) {
      try {
        final ac = await FirebaseAppCheck.instance.getToken();
        if (ac != null) headers['X-Firebase-AppCheck'] = ac;
      } catch (e) {
        debugPrint('App Check token failed: $e');
      }
    }
    return headers;
  }

  Uri _uri(String path) => Uri.parse('${Env.apiBase}$path');

  Future<Map<String, dynamic>> post(String path, Map<String, Object?> body) async {
    return _send(() async => _http
        .post(_uri(path), headers: await _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15)));
  }

  Future<Map<String, dynamic>> get(String path) async {
    return _send(() async =>
        _http.get(_uri(path), headers: await _headers()).timeout(const Duration(seconds: 15)));
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call();
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'The server took too long to respond.');
    } catch (e) {
      throw ApiException(0, 'network', 'Could not reach the server.');
    }
    Map<String, dynamic> json;
    try {
      json = res.body.isEmpty ? {} : jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      json = {};
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    final err = json['error'];
    if (err is Map) {
      throw ApiException(res.statusCode, '${err['code'] ?? 'error'}', '${err['message'] ?? ''}');
    }
    throw ApiException(res.statusCode, 'http_${res.statusCode}', 'Request failed.');
  }
}
