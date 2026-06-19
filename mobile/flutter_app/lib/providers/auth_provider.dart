import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService;

  bool _isLoggedIn = false;
  bool _isLoading = false;
  String _serverUrl = '';
  String? _errorMessage;

  AuthProvider(this._apiService);

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String get serverUrl => _serverUrl;
  String? get errorMessage => _errorMessage;

  Future<void> loadFromStorage() async {
    _isLoading = true;
    notifyListeners();

    await _apiService.loadSettings();
    _serverUrl = _apiService.baseUrl;

    if (_apiService.isConfigured && _apiService.hasToken) {
      // Verify token is still valid
      try {
        final health = await _apiService.getHealth();
        if (health['status'] != 'offline' && health['status'] != 'error') {
          _isLoggedIn = true;
        }
      } catch (_) {
        // If health check fails, still allow using cached token
        _isLoggedIn = _apiService.hasToken;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String url, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _apiService.setBaseUrl(url);
      final success = await _apiService.login(password);

      if (success) {
        _isLoggedIn = true;
        _serverUrl = url;
        _errorMessage = null;
      } else {
        _errorMessage = 'Falsches Passwort oder Serverfehler';
        _isLoggedIn = false;
      }

      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _errorMessage = 'Verbindung fehlgeschlagen: ${e.toString()}';
      _isLoggedIn = false;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _apiService.clearToken();
    _isLoggedIn = false;
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void setServerUrl(String url) {
    _serverUrl = url;
    notifyListeners();
  }
}
