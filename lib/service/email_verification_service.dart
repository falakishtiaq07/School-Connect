import 'dart:convert';
import 'package:http/http.dart' as http;

class EmailVerificationService {
  static const String _apiKey = "51e464ed7ae7478e853facd171155578";

  static Future<bool> isEmailValid(String email) async {
    try {
      final uri = Uri.https('api.zerobounce.net', '/v2/validate', {
        'api_key': _apiKey,
        'email': email.trim(),
      });

      final response = await http.get(uri);

      print('================================');
      print('ZEROBOUNCE EMAIL CHECK');
      print('EMAIL: $email');
      print('STATUS CODE: ${response.statusCode}');
      print('RESPONSE: ${response.body}');
      print('================================');

      if (response.statusCode != 200) {
        print('ZeroBounce API request failed.');
        return false;
      }

      final data = jsonDecode(response.body);

      final status = data['status']?.toString().toLowerCase();

      print('ZEROBOUNCE STATUS: $status');

      return status == 'valid';
    } catch (e) {
      print('ZeroBounce Error: $e');
      return false;
    }
  }
}
