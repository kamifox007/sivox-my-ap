import 'package:my_app/models/event.dart';

class Booking {
  final String id;
  final String eventId;
  final String userId;
  final String ticketType;
  final int numGuests;
  final String paymentStatus;
  final String qrCode;
  final String? createdAt;
  final String userName;
  final String? guestPhone;
  final String? createdBy;
  final String? cancellationReason;
  final String? appliedPerk;
  final double discountAmount;
  final double totalPricePaid; // RECORDED AT BOOKING TIME
  final Event? event;
  final String? tableNumber;
  final bool securityCleared;
  final bool paymentConfirmed;
  final bool isWalkin;
  final String? walkinSerial;
  final String? scannedAtSecurity;
  final String? scannedAtPayment;
  final String? confirmedByManager;

  String? get scannedAt => scannedAtPayment ?? scannedAtSecurity;

  Booking({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.ticketType,
    required this.numGuests,
    required this.paymentStatus,
    required this.qrCode,
    this.createdAt,
    required this.userName,
    this.guestPhone,
    this.createdBy,
    this.cancellationReason,
    this.appliedPerk,
    this.discountAmount = 0.0,
    this.totalPricePaid = 0.0,
    this.event,
    this.tableNumber,
    this.securityCleared = false,
    this.paymentConfirmed = false,
    this.isWalkin = false,
    this.walkinSerial,
    this.scannedAtSecurity,
    this.scannedAtPayment,
    this.confirmedByManager,
  });

  factory Booking.fromMap(Map<String, dynamic> map) {
    return Booking(
      id: map['id']?.toString() ?? '',
      eventId: map['event_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      ticketType: map['ticket_type'] ?? 'General',
      numGuests: map['num_guests'] ?? 1,
      paymentStatus: map['payment_status'] ?? 'pending',
      qrCode: map['qr_code'] ?? '',
      createdAt: map['created_at']?.toString(),
      userName: map['user_name'] ?? 'Attendee',
      guestPhone: map['guest_phone'],
      createdBy: map['created_by']?.toString(),
      cancellationReason: map['cancellation_reason']?.toString(),
      appliedPerk: map['applied_perk']?.toString(),
      discountAmount: (map['discount_amount'] ?? 0.0).toDouble(),
      totalPricePaid: (map['total_price_paid'] ?? 0.0).toDouble(),
      event: map['events'] != null ? Event.fromMap(map['events']) : null,
      tableNumber: map['table_number']?.toString(),
      securityCleared: map['security_cleared'] ?? false,
      paymentConfirmed: map['payment_confirmed'] ?? false,
      isWalkin: map['is_walkin'] ?? false,
      walkinSerial: map['walkin_serial']?.toString(),
      scannedAtSecurity: map['scanned_at_security']?.toString(),
      scannedAtPayment: map['scanned_at_payment']?.toString(),
      confirmedByManager: map['confirmed_by_manager']?.toString(),
    );
  }

  factory Booking.fromJson(Map<String, dynamic> json) => Booking.fromMap(json);

  Booking copyWith({
    String? id,
    String? eventId,
    String? userId,
    String? ticketType,
    int? numGuests,
    String? paymentStatus,
    String? qrCode,
    String? createdAt,
    String? userName,
    String? guestPhone,
    String? createdBy,
    String? cancellationReason,
    String? appliedPerk,
    double? discountAmount,
    double? totalPricePaid,
    Event? event,
    String? tableNumber,
    bool? securityCleared,
    bool? paymentConfirmed,
    bool? isWalkin,
    String? walkinSerial,
    String? scannedAtSecurity,
    String? scannedAtPayment,
    String? confirmedByManager,
  }) {
    return Booking(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      userId: userId ?? this.userId,
      ticketType: ticketType ?? this.ticketType,
      numGuests: numGuests ?? this.numGuests,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      qrCode: qrCode ?? this.qrCode,
      createdAt: createdAt ?? this.createdAt,
      userName: userName ?? this.userName,
      guestPhone: guestPhone ?? this.guestPhone,
      createdBy: createdBy ?? this.createdBy,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      appliedPerk: appliedPerk ?? this.appliedPerk,
      discountAmount: discountAmount ?? this.discountAmount,
      totalPricePaid: totalPricePaid ?? this.totalPricePaid,
      event: event ?? this.event,
      tableNumber: tableNumber ?? this.tableNumber,
      securityCleared: securityCleared ?? this.securityCleared,
      paymentConfirmed: paymentConfirmed ?? this.paymentConfirmed,
      isWalkin: isWalkin ?? this.isWalkin,
      walkinSerial: walkinSerial ?? this.walkinSerial,
      scannedAtSecurity: scannedAtSecurity ?? this.scannedAtSecurity,
      scannedAtPayment: scannedAtPayment ?? this.scannedAtPayment,
      confirmedByManager: confirmedByManager ?? this.confirmedByManager,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'event_id': eventId,
      'user_id': userId,
      'ticket_type': ticketType,
      'num_guests': numGuests,
      'payment_status': paymentStatus,
      'qr_code': qrCode,
      'guest_phone': guestPhone,
      'table_number': tableNumber,
      'created_by': createdBy,
      'cancellation_reason': cancellationReason,
      'applied_perk': appliedPerk,
      'discount_amount': discountAmount,
      'total_price_paid': totalPricePaid,
      'security_cleared': securityCleared,
      'payment_confirmed': paymentConfirmed,
      'is_walkin': isWalkin,
      'walkin_serial': walkinSerial,
      'scanned_at_security': scannedAtSecurity,
      'scanned_at_payment': scannedAtPayment,
      'confirmed_by_manager': confirmedByManager,
    };
  }
}
