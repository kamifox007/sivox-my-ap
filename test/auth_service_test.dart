import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/services/auth_service.dart';

void main() {
  group('AuthService.normalizeAlgerianPhone', () {
    test('converts a local 10-digit Algerian mobile number', () {
      expect(
        AuthService.normalizeAlgerianPhone('0551 23 45 67'),
        '+213551234567',
      );
    });

    test('normalizes the 00213 international prefix', () {
      expect(
        AuthService.normalizeAlgerianPhone('00213 551 23 45 67'),
        '+213551234567',
      );
    });

    test('removes an extra zero after the +213 country code', () {
      expect(
        AuthService.normalizeAlgerianPhone('+2130551234567'),
        '+213551234567',
      );
    });

    test('preserves other international numbers', () {
      expect(
        AuthService.normalizeAlgerianPhone('+33123456789'),
        '+33123456789',
      );
    });
  });
}
