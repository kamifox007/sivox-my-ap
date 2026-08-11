import sys

file_path = r'c:\ap_nv\my_app\lib\screens\scan_entry.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

def replace_line(ln, new_content):
    lines[ln-1] = new_content + '\n'

# Fix scan result titles (redo in case partial fail before)
replace_line(136, "          title: 'qr_unknown'.tr,")
replace_line(137, "          subtitle: 'qr_unknown_desc'.tr,")
replace_line(147, "          title: 'used_ticket'.tr,")
replace_line(149, "              '${booking.userName} — ${'used_ticket_desc'.tr}\\n${'guests_count'.tr}: ${booking.numGuests}',")
replace_line(161, "          title: currentStatus == 'arrived' ? 'arrived_at_checkin'.tr : (currentStatus == 'pending' ? 'pending_payment'.tr : 'entry_allowed'.tr),")
replace_line(163, "              '${booking.userName}\\n${booking.numGuests} ${'guests_count'.tr} • ${booking.ticketType}',")

# Notifications block
replace_line(393, "                            title: isFree ? 'welcome_night'.tr : 'arrived_at_checkin'.tr,")
replace_line(395, "                              ? '${'manual_entry_success'.tr} $eventTitle. ${'welcome_night'.tr} $clubName!'")
replace_line(396, "                              : '${'manual_entry_success'.tr}. ${'must_collect_manager'.tr} ${totalToPay.toInt()} DA.',")
replace_line(402, "                              ? 'Free Entry: ${booking.userName} in $eventTitle'")
replace_line(403, "                              : 'Arrival: ${booking.userName} (Pending Payment)',")
replace_line(406, "                          Navigator.pop(context);") # Context error fix

# Buttons
replace_line(416, "                      child: Text('register_attendance'.tr, style: const TextStyle(fontWeight: FontWeight.bold)),")
replace_line(423, "                        if (!isAuthorized && booking.paymentStatus == 'pending') {")
replace_line(424, "                           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('must_collect_manager'.tr)));")

# Search Hint
replace_line(789, "          hintText: 'phone_search_hint'.tr,")

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print("Fix applied successfully")
