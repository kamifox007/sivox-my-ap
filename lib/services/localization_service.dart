import 'package:my_app/services/translation_service.dart';

class CountryInfo {
  final String name;
  final String code;
  final String flag;
  final String currency;
  final String currencySymbol;
  final String currencySymbolAr;
  final String paymentInfo;
  final String phonePrefix;

  CountryInfo({
    required this.name,
    required this.code,
    required this.flag,
    required this.currency,
    required this.currencySymbol,
    required this.currencySymbolAr,
    required this.paymentInfo,
    required this.phonePrefix,
  });
}

class LocalizationService {
  static final List<CountryInfo> supportedCountries = [
    // --- AFRICA & MENA ---
    CountryInfo(name: 'Algeria', code: 'DZ', flag: '🇩🇿', currency: 'DZD', currencySymbol: 'DA', currencySymbolAr: 'د.ج', paymentInfo: 'Cash / BaridiMob', phonePrefix: '+213'),
    CountryInfo(name: 'Morocco', code: 'MA', flag: '🇲🇦', currency: 'MAD', currencySymbol: 'DH', currencySymbolAr: 'د.م', paymentInfo: 'Cash / Wafacash', phonePrefix: '+212'),
    CountryInfo(name: 'Egypt', code: 'EG', flag: '🇪🇬', currency: 'EGP', currencySymbol: 'EGP', currencySymbolAr: 'ج.م', paymentInfo: 'Fawry / InstaPay', phonePrefix: '+20'),
    CountryInfo(name: 'South Africa', code: 'ZA', flag: '🇿🇦', currency: 'ZAR', currencySymbol: 'R', currencySymbolAr: 'R', paymentInfo: 'Card / EFT', phonePrefix: '+27'),
    CountryInfo(name: 'Nigeria', code: 'NG', flag: '🇳🇬', currency: 'NGN', currencySymbol: '₦', currencySymbolAr: '₦', paymentInfo: 'Paystack / Flutterwave', phonePrefix: '+234'),
    
    // --- AMERICAS ---
    CountryInfo(name: 'USA', code: 'US', flag: '🇺🇸', currency: 'USD', currencySymbol: '\$', currencySymbolAr: '\$', paymentInfo: 'Stripe / Apple Pay', phonePrefix: '+1'),
    CountryInfo(name: 'Canada', code: 'CA', flag: '🇨🇦', currency: 'CAD', currencySymbol: 'C\$', currencySymbolAr: 'C\$', paymentInfo: 'Interac / Card', phonePrefix: '+1'),
    CountryInfo(name: 'Brazil', code: 'BR', flag: '🇧🇷', currency: 'BRL', currencySymbol: 'R\$', currencySymbolAr: 'R\$', paymentInfo: 'Stripe / Pix', phonePrefix: '+55'),
    CountryInfo(name: 'Mexico', code: 'MX', flag: '🇲🇽', currency: 'MXN', currencySymbol: '\$', currencySymbolAr: '\$', paymentInfo: 'Stripe', phonePrefix: '+52'),
    CountryInfo(name: 'Argentina', code: 'AR', flag: '🇦🇷', currency: 'ARS', currencySymbol: '\$', currencySymbolAr: '\$', paymentInfo: 'Mercado Pago', phonePrefix: '+54'),

    // --- EUROPE ---
    CountryInfo(name: 'UK', code: 'GB', flag: '🇬🇧', currency: 'GBP', currencySymbol: '£', currencySymbolAr: '£', paymentInfo: 'Card / Apple Pay', phonePrefix: '+44'),
    CountryInfo(name: 'France', code: 'FR', flag: '🇫🇷', currency: 'EUR', currencySymbol: '€', currencySymbolAr: '€', paymentInfo: 'Card / Apple Pay', phonePrefix: '+33'),
    CountryInfo(name: 'Germany', code: 'DE', flag: '🇩🇪', currency: 'EUR', currencySymbol: '€', currencySymbolAr: '€', paymentInfo: 'Card / Apple Pay', phonePrefix: '+49'),
    CountryInfo(name: 'Spain', code: 'ES', flag: '🇪🇸', currency: 'EUR', currencySymbol: '€', currencySymbolAr: '€', paymentInfo: 'Bizum / Card', phonePrefix: '+34'),
    CountryInfo(name: 'Italy', code: 'IT', flag: '🇮🇹', currency: 'EUR', currencySymbol: '€', currencySymbolAr: '€', paymentInfo: 'Card / Apple Pay', phonePrefix: '+39'),
    CountryInfo(name: 'Turkey', code: 'TR', flag: '🇹🇷', currency: 'TRY', currencySymbol: '₺', currencySymbolAr: '₺', paymentInfo: 'Card / Wallet', phonePrefix: '+90'),
    CountryInfo(name: 'Russia', code: 'RU', flag: '🇷🇺', currency: 'RUB', currencySymbol: '₽', currencySymbolAr: '₽', paymentInfo: 'SberPay / Card', phonePrefix: '+7'),

    // --- ASIA & OCEANIA ---
    CountryInfo(name: 'China', code: 'CN', flag: '🇨🇳', currency: 'CNY', currencySymbol: '¥', currencySymbolAr: '¥', paymentInfo: 'Alipay / WeChat Pay', phonePrefix: '+86'),
    CountryInfo(name: 'Japan', code: 'JP', flag: '🇯🇵', currency: 'JPY', currencySymbol: '¥', currencySymbolAr: '¥', paymentInfo: 'Line Pay / Card', phonePrefix: '+81'),
    CountryInfo(name: 'India', code: 'IN', flag: '🇮🇳', currency: 'INR', currencySymbol: '₹', currencySymbolAr: '₹', paymentInfo: 'UPI / Razorpay', phonePrefix: '+91'),
    CountryInfo(name: 'South Korea', code: 'KR', flag: '🇰🇷', currency: 'KRW', currencySymbol: '₩', currencySymbolAr: '₩', paymentInfo: 'KakaoPay / Card', phonePrefix: '+82'),
    CountryInfo(name: 'Australia', code: 'AU', flag: '🇦🇺', currency: 'AUD', currencySymbol: 'A\$', currencySymbolAr: 'A\$', paymentInfo: 'Stripe', phonePrefix: '+61'),
    CountryInfo(name: 'Saudi Arabia', code: 'SA', flag: '🇸🇦', currency: 'SAR', currencySymbol: 'SR', currencySymbolAr: 'ر.س', paymentInfo: 'STC Pay / Mada', phonePrefix: '+966'),
    CountryInfo(name: 'UAE', code: 'AE', flag: '🇦🇪', currency: 'AED', currencySymbol: 'AED', currencySymbolAr: 'د.إ', paymentInfo: 'Apple Pay / Card', phonePrefix: '+971'),
    
    // --- GLOBAL FALLBACK ---
    CountryInfo(name: 'Global', code: 'INT', flag: '🌍', currency: 'USD', currencySymbol: '\$', currencySymbolAr: '\$', paymentInfo: 'Stripe / PayPal', phonePrefix: ''),
  ];

  static CountryInfo getCountryByCode(String code) {
    return supportedCountries.firstWhere(
      (c) => c.code == code,
      orElse: () => supportedCountries[0], // Default to Algeria
    );
  }

  static String formatPrice(double price, String countryCode) {
    if (price == 0) return 'FREE_ENTRY'.tr;
    final country = getCountryByCode(countryCode);
    final isAr = TranslationService.currentLanguage.value == Language.ar;
    final symbol = isAr ? country.currencySymbolAr : country.currencySymbol;
    
    // In Arabic, the symbol usually follows the number but for some it's before.
    // Standardizing to: [Number] [Symbol]
    return '${price.toInt()} $symbol';
  }

  /// Returns a list of major city names for a given country code.
  static List<String> getCitiesByCountry(String countryCode) {
    const Map<String, List<String>> citiesMap = {
      'DZ': ['Algiers', 'Oran', 'Constantine', 'Annaba', 'Blida', 'Tlemcen', 'Sétif', 'Bejaia'],
      'MA': ['Casablanca', 'Rabat', 'Marrakech', 'Fes', 'Tangier', 'Agadir'],
      'EG': ['Cairo', 'Alexandria', 'Giza', 'Luxor', 'Aswan', 'Hurghada'],
      'ZA': ['Cape Town', 'Johannesburg', 'Durban', 'Pretoria', 'Port Elizabeth'],
      'NG': ['Lagos', 'Abuja', 'Port Harcourt', 'Kano', 'Ibadan'],
      'US': ['New York', 'Los Angeles', 'Chicago', 'Miami', 'Houston', 'Las Vegas'],
      'CA': ['Toronto', 'Vancouver', 'Montreal', 'Calgary', 'Ottawa'],
      'BR': ['São Paulo', 'Rio de Janeiro', 'Brasília', 'Salvador'],
      'MX': ['Mexico City', 'Guadalajara', 'Monterrey', 'Cancún'],
      'AR': ['Buenos Aires', 'Córdoba', 'Rosario', 'Mendoza'],
      'GB': ['London', 'Manchester', 'Birmingham', 'Edinburgh', 'Liverpool'],
      'FR': ['Paris', 'Lyon', 'Marseille', 'Nice', 'Bordeaux'],
      'DE': ['Berlin', 'Munich', 'Hamburg', 'Frankfurt', 'Cologne'],
      'ES': ['Madrid', 'Barcelona', 'Valencia', 'Seville', 'Bilbao'],
      'IT': ['Rome', 'Milan', 'Naples', 'Turin', 'Florence'],
      'TR': ['Istanbul', 'Ankara', 'Izmir', 'Antalya', 'Bursa'],
      'RU': ['Moscow', 'Saint Petersburg', 'Kazan', 'Novosibirsk'],
      'CN': ['Beijing', 'Shanghai', 'Guangzhou', 'Shenzhen', 'Chengdu'],
      'JP': ['Tokyo', 'Osaka', 'Kyoto', 'Yokohama', 'Sapporo'],
      'IN': ['Mumbai', 'Delhi', 'Bangalore', 'Chennai', 'Kolkata'],
      'KR': ['Seoul', 'Busan', 'Incheon', 'Daegu'],
      'AU': ['Sydney', 'Melbourne', 'Brisbane', 'Perth', 'Adelaide'],
      'SA': ['Riyadh', 'Jeddah', 'Mecca', 'Medina', 'Dammam'],
      'AE': ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman'],
      'INT': ['Global'],
    };
    return citiesMap[countryCode] ?? ['Unknown'];
  }
}
