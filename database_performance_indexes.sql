-- ⚡ فهارس قاعدة البيانات لتسريع الاستعلامات وعمليات البحث (Sivox Performance Indexes)
-- هذا الملف يحتوي على الفهارس الذكية والمحسّنة لتسريع استجابة التطبيق وتقليل الضغط على قاعدة البيانات.

-- [1] فهارس جدول الحجوزات (bookings)
-- تسريع تصفية الحجوزات حسب المستخدم أو الفعالية
CREATE INDEX IF NOT EXISTS idx_bookings_user_id ON bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_bookings_event_id ON bookings(event_id);
CREATE INDEX IF NOT EXISTS idx_bookings_payment_status ON bookings(payment_status);

-- فهرس مركب فائق الأداء لتسريع فلترة حجوزات الفعالية حسب حالتها (مثل شاشات الفرز Vetting/Security)
CREATE INDEX IF NOT EXISTS idx_bookings_event_status ON bookings(event_id, payment_status);

-- [2] فهارس جدول الفعاليات (events)
-- تسريع جلب الفعاليات الخاصة بنادي منظم معين
CREATE INDEX IF NOT EXISTS idx_events_organizer_id ON events(organizer_id);
-- تسريع ترتيب وتصفية الفعاليات حسب تاريخ وتوقيت الفعالية
CREATE INDEX IF NOT EXISTS idx_events_date_time ON events(date_time);

-- [3] فهارس جدول تعيينات الموظفين (staff_assignments)
-- تسريع التحقق من الموظفين وصلاحياتهم وعمليات التحقق عند البوابة
CREATE INDEX IF NOT EXISTS idx_staff_assignments_staff_id ON staff_assignments(staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_assignments_event_id ON staff_assignments(event_id);
CREATE INDEX IF NOT EXISTS idx_staff_assignments_status ON staff_assignments(status);
-- فهرس مركب لتسريع فحص صلاحيات الموظف النشط لفعالية معينة بشكل لحظي
CREATE INDEX IF NOT EXISTS idx_staff_assignments_active ON staff_assignments(event_id, staff_id, status);

-- [4] فهارس جدول المتابعة (follows)
-- تسريع جلب المنظمين المتابعين بواسطة مستخدم معين وتسريع التحقق من الخصومات
CREATE INDEX IF NOT EXISTS idx_follows_user_id ON follows(user_id);
CREATE INDEX IF NOT EXISTS idx_follows_organizer_id ON follows(organizer_id);

-- [5] فهارس جدول دوام الموظفين وسجلات التدقيق (staff_shifts & staff_logs)
-- تسريع جلب سجلات التدقيق وساعات عمل الموظفين
CREATE INDEX IF NOT EXISTS idx_staff_shifts_staff_id ON staff_shifts(staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_logs_event_id ON staff_logs(related_event_id);
CREATE INDEX IF NOT EXISTS idx_staff_logs_user_id ON staff_logs(user_id);
