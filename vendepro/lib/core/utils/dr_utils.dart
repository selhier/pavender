// lib/core/utils/dr_utils.dart

class DRUtils {
  /// Validates a Dominican RNC (9 digits) or Cédula (11 digits)
  static bool isValidTaxId(String id) {
    String cleanId = id.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (cleanId.length == 9) {
      return isValidRNC(cleanId);
    } else if (cleanId.length == 11) {
      return isValidCedula(cleanId);
    }
    return false;
  }

  /// Validates RNC (9 digits) using MOD-11
  static bool isValidRNC(String rnc) {
    if (rnc.length != 9) return false;
    
    List<int> weights = [3, 2, 7, 6, 5, 4, 3, 2];
    int sum = 0;
    
    for (int i = 0; i < 8; i++) {
      sum += int.parse(rnc[i]) * weights[i];
    }
    
    int remainder = sum % 11;
    int checkDigit;
    
    if (remainder == 0) {
      checkDigit = 2;
    } else if (remainder == 1) {
      checkDigit = 1;
    } else {
      checkDigit = 11 - remainder;
    }
    
    return int.parse(rnc[8]) == checkDigit;
  }

  /// Validates Cédula (11 digits)
  static bool isValidCedula(String cedula) {
    if (cedula.length != 11) return false;
    
    // Series 000 should not be valid for real IDs but some test ones exist
    if (cedula.startsWith('000')) return false;

    List<int> weights = [1, 2, 1, 2, 1, 2, 1, 2, 1, 2];
    int sum = 0;
    
    for (int i = 0; i < 10; i++) {
      int prod = int.parse(cedula[i]) * weights[i];
      if (prod > 9) prod -= 9;
      sum += prod;
    }
    
    int nextMultipleOf10 = ((sum / 10).ceil() * 10).toInt();
    int checkDigit = nextMultipleOf10 - sum;
    
    return int.parse(cedula[10]) == checkDigit;
  }

  /// Validates NCF Structure (e.g., B0100000001)
  static bool isValidNCF(String ncf) {
    return RegExp(r'^[BPE][0-9]{10}$').hasMatch(ncf);
  }

  /// Map of NCF Types
  static const Map<String, String> ncfTypes = {
    '01': 'Factura de Crédito Fiscal',
    '02': 'Factura de Consumo',
    '11': 'Registro de Proveedores Informales',
    '12': 'Registro de Único Ingreso',
    '14': 'Registro de Gastos Menores',
    '15': 'Registro de Regímenes Especiales',
    '16': 'Comprobantes Gubernamentales',
  };
}
