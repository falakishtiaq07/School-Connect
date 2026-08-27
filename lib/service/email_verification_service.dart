import 'dart:convert';
import 'package:http/http.dart' as http;

class EmailVerificationService {
  static const String _apiKey = "51e464ed7ae7478e853facd171155578";

  static Future<bool> isEmailValid(String email) async {
    try {
      final url = Uri.parse(
        'https://api.zerobounce.net/v2/validate?api_key=$_apiKey&email=$email',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = data['status'];

        // Agar email valid hai toh true return hoga
        return status == 'valid';
      }
      return false;
    } catch (e) {
      print("Email Verification Error: $e");
      return false;
    }
  }
}
