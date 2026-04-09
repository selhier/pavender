// lib/core/services/tax_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TaxService {
  final String _baseUrl = 'https://rnc.megaplus.com.do/api/consulta';

  Future<Map<String, dynamic>?> lookupRNC(String rnc) async {
    try {
      final cleanRnc = rnc.replaceAll(RegExp(r'[^0-9]'), '');
      
      // Use CORS proxy on Web to avoid "Failed to fetch" errors.
      // On mobile/native, call the API directly.
      final url = kIsWeb 
          ? 'https://corsproxy.io/?${Uri.encodeComponent('$_baseUrl?rnc=$cleanRnc')}'
          : '$_baseUrl?rnc=$cleanRnc';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'VendePro/1.0',
        },
      );

      if (response.statusCode == 200) {
        // Use utf8.decode to handle special characters correctly
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['error'] == false) {
          return {
            'rnc': data['cedula_rnc'],
            'name': data['nombre_razon_social'],
            'commercialName': data['nombre_comercial'],
            'status': data['estado'],
          };
        }
      } else {
        print('RNC Lookup Error: ${response.statusCode} - ${response.body}');
      }
      return null;
    } catch (e) {
      print('Exception during RNC lookup: $e');
      return null;
    }
  }
}
