import sys

file_path = r'c:\ap_nv\my_app\lib\screens\scan_entry.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Line numbers are 1-indexed
def replace_line(ln, new_content):
    lines[ln-1] = new_content + '\n'

# Phase 1: Localization
replace_line(136, "          title: 'qr_unknown'.tr,")
replace_line(137, "          subtitle: 'qr_unknown_desc'.tr,")
replace_line(147, "          title: 'used_ticket'.tr,")
replace_line(149, "              '${booking.userName} — ${'used_ticket_desc'.tr}\\n${'guests_count'.tr}: ${booking.numGuests}',")
replace_line(161, "          title: currentStatus == 'arrived' ? 'arrived_at_checkin'.tr : (currentStatus == 'pending' ? 'pending_payment'.tr : 'entry_allowed'.tr),")
replace_line(163, "              '${booking.userName}\\n${booking.numGuests} ${'guests_count'.tr} • ${booking.ticketType}',")
replace_line(253, "        description: 'Manual entry: $num guests',") # Audit log can stay English or be translated later
replace_line(274, "            Text('deny_reason_title'.tr, style: AppTheme.headlineStyle),")
replace_line(276, "            _buildReasonTile('deny_security'.tr, booking),")
replace_line(277, "            _buildReasonTile('deny_dress_code'.tr, booking),")
replace_line(278, "            _buildReasonTile('deny_id'.tr, booking),")
replace_line(292, "          description: 'Entry denied: ${booking.userName} - Reason: $reason',")

# Phase 2: Lint fixes (already some were done but let's be sure)
# Line 390: use_build_context_synchronously
# I need to find the context in line 390.

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print("Done")
