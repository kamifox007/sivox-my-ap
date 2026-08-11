-- ١. أولاً: تهيئة الجداول (مسح القديم لضمان نظافة البيانات)
DROP TABLE IF EXISTS support_requests CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS staff_logs CASCADE;
DROP TABLE IF EXISTS staff_shifts CASCADE;
DROP TABLE IF EXISTS staff_assignments CASCADE;
DROP TABLE IF EXISTS follows CASCADE;
DROP TABLE IF EXISTS bookings CASCADE;
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS organizer_profiles CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

-- تفعيل تمديد UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ٢. بناء الجداول الجديدة والمطابقة بدقة لأكواد التطبيق

-- [1] جدول الملفات الشخصية الأساسي
CREATE TABLE profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  full_name TEXT,
  avatar_url TEXT,
  role TEXT DEFAULT 'attendee', -- attendee, organizer, staff
  phone TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- [2] بروفايل المنظم (تخزين بيانات النادي)
CREATE TABLE organizer_profiles (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  owner_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  bio TEXT,
  contact_phone TEXT,
  permanent_gallery TEXT[] DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- [3] الفعاليات
CREATE TABLE events (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  organizer_id UUID REFERENCES organizer_profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  category TEXT,
  venue TEXT,
  date_time TEXT, -- مخزن كنص للمرونة في واجهة العرض
  price NUMERIC DEFAULT 0.0,
  description TEXT,
  overline TEXT,
  contact_number TEXT,
  contact_type TEXT, -- CALL, WHATSAPP, VIBER, ALL
  require_call_confirmation BOOLEAN DEFAULT FALSE,
  hide_price BOOLEAN DEFAULT FALSE,
  is_hidden BOOLEAN DEFAULT FALSE, -- لإخفاء الفعاليات المبلغ عنها تلقائياً
  gallery_images TEXT[] DEFAULT '{}',
  max_capacity INT,
  latitude FLOAT8 DEFAULT 0.0,
  longitude FLOAT8 DEFAULT 0.0,
  country_code TEXT DEFAULT 'DZ',
  rules TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- [4] الحجوزات والتذاكر
CREATE TABLE bookings (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users ON DELETE CASCADE,
  user_name TEXT,
  ticket_type TEXT DEFAULT 'General',
  num_guests INT DEFAULT 1,
  payment_status TEXT DEFAULT 'pending', -- pending, confirmed, used, cancelled
  qr_code TEXT,
  guest_phone TEXT,
  table_number TEXT,
  created_by UUID, -- الموظف الذي أنشأ التذكرة يدوياً
  cancellation_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- [5] المتابعة (بين المستخدم والنادي)
CREATE TABLE follows (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES auth.users ON DELETE CASCADE,
  organizer_id UUID REFERENCES organizer_profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, organizer_id)
);

-- [6] تعيينات الموظفين
CREATE TABLE staff_assignments (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  organizer_id UUID REFERENCES organizer_profiles(id) ON DELETE CASCADE,
  staff_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'Scanner', -- Scanner, Security, VIP, Manager
  status TEXT DEFAULT 'pending', -- pending, active, declined
  permissions JSONB DEFAULT '{}', -- لتخزين الصلاحيات (can_scan, can_cancel, etc)
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- [7] دوام الموظفين (Clock-in/out)
CREATE TABLE staff_shifts (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  staff_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  assignment_id UUID REFERENCES staff_assignments(id) ON DELETE CASCADE,
  start_time TIMESTAMPTZ DEFAULT NOW(),
  end_time TIMESTAMPTZ,
  start_lat FLOAT8,
  start_lng FLOAT8,
  end_lat FLOAT8,
  end_lng FLOAT8
);

-- [8] سجلات التدقيق (Audit Logs)
CREATE TABLE staff_logs (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  user_name TEXT,
  role TEXT,
  action_type TEXT,
  description TEXT,
  related_event_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- [9] الإشعارات
CREATE TABLE notifications (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES auth.users ON DELETE CASCADE,
  title TEXT,
  body TEXT,
  type TEXT, -- staff_invite, entry_success, etc
  metadata JSONB DEFAULT '{}',
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- [10] طلبات الدعم الفني
CREATE TABLE support_requests (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES auth.users ON DELETE SET NULL,
  category TEXT,
  subject TEXT,
  message TEXT,
  status TEXT DEFAULT 'open',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ٣. تفعيل الحماية (RLS)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_requests ENABLE ROW LEVEL SECURITY;

-- ٤. سياسات الوصول (تسمح للقراءة حالياً لضمان عمل التطبيق)
CREATE POLICY "Public Read Access" ON profiles FOR SELECT USING (true);
CREATE POLICY "Own Profile Update" ON profiles FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Public Read Access" ON events FOR SELECT USING (true);
CREATE POLICY "Organizer Write Access" ON events FOR ALL USING (auth.uid() IN (SELECT owner_id FROM organizer_profiles WHERE id = organizer_id));

CREATE POLICY "Users Can Read Own Bookings" ON bookings FOR SELECT USING (auth.uid() = user_id OR auth.uid() IN (SELECT owner_id FROM organizer_profiles WHERE id IN (SELECT organizer_id FROM events WHERE id = event_id)));
CREATE POLICY "Staff/Organizer Can Update Bookings" ON bookings FOR UPDATE USING (
  auth.uid() IN (
    SELECT op.owner_id 
    FROM organizer_profiles op
    JOIN events e ON e.organizer_id = op.id
    WHERE e.id = bookings.event_id
  ) OR auth.uid() IN (
    SELECT sa.staff_id 
    FROM staff_assignments sa
    WHERE sa.event_id = bookings.event_id AND sa.status = 'active'
  )
);

CREATE POLICY "Follows Access" ON follows FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Staff Assignment Read" ON staff_assignments FOR SELECT USING (auth.uid() = staff_id OR auth.uid() IN (SELECT owner_id FROM organizer_profiles WHERE id = organizer_id));
CREATE POLICY "Staff Shift Access" ON staff_shifts FOR ALL USING (auth.uid() = staff_id);

CREATE POLICY "Staff Logs Access" ON staff_logs FOR SELECT USING (true); -- للمالك والموظفين لمشكلة النشاط
CREATE POLICY "Public Read Access" ON organizer_profiles FOR SELECT USING (true);
CREATE POLICY "Notifications Access" ON notifications FOR ALL USING (auth.uid() = user_id);

-- ٥. ميزة إنشاء البروفايل تلقائياً عند التسجيل والتحقق من الحسابات الوهمية (Trigger)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  email_domain TEXT;
BEGIN
  -- حماية من الحسابات الوهمية: منع التسجيل بالنطاقات المؤقتة ومزودي الإيميلات الوهمية
  IF new.email IS NOT NULL THEN
    email_domain := split_part(new.email, '@', 2);
    IF email_domain IN ('yopmail.com', 'mailinator.com', 'tempmail.com', '10minutemail.com', 'sharklasers.com', 'guerrillamail.com', 'getnada.com', 'dispostable.com') THEN
      RAISE EXCEPTION 'DISPOSABLE_EMAIL_BLOCKED: Registration using temporary/disposable email addresses is not allowed.';
    END IF;
  END IF;

  INSERT INTO public.profiles (id, full_name, avatar_url, role, phone)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'avatar_url',
    COALESCE(new.raw_user_meta_data->>'role', 'attendee'),
    COALESCE(new.phone, new.raw_user_meta_data->>'phone')
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    avatar_url = EXCLUDED.avatar_url,
    role = EXCLUDED.role,
    phone = EXCLUDED.phone,
    updated_at = NOW();

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT OR UPDATE ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ٦. دالة حذف الحساب الآمنة والنهائية (Account Deletion) متوافقة مع متجر جوجل بلاي
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void AS $$
BEGIN
  -- حذف المستخدم الحالي من جدول auth.users مما يؤدي لحذف تسلسلي (CASCADE) لكافة بياناته في الجداول الأخرى
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

-- ٧. جدول قائمة الحظر (Blacklist) لسلامة الفعاليات وأمان المستخدمين (Moderation & Safety)
CREATE TABLE IF NOT EXISTS public.blacklist (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  club_id UUID REFERENCES public.organizer_profiles(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  phone_number TEXT,
  reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(club_id, user_id)
);

-- تفعيل RLS على جدول قائمة الحظر
ALTER TABLE public.blacklist ENABLE ROW LEVEL SECURITY;

-- سياسات حماية جدول قائمة الحظر
CREATE POLICY "Organizers/Staff Can Manage Blacklist" ON public.blacklist FOR ALL USING (
  auth.uid() IN (
    SELECT op.owner_id 
    FROM organizer_profiles op
    WHERE op.id = blacklist.club_id
  ) OR auth.uid() IN (
    SELECT sa.staff_id 
    FROM staff_assignments sa
    WHERE sa.organizer_id = blacklist.club_id AND sa.status = 'active'
  )
);

CREATE POLICY "Users Can Read Own Blacklist Status" ON public.blacklist FOR SELECT USING (
  auth.uid() = user_id
);

-- ٨. جدول التقارير عن الفعاليات المخالفة (Event Reports) للمراجعة الذاتية وأمان المحتوى
CREATE TABLE IF NOT EXISTS public.event_reports (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  event_id UUID REFERENCES public.events(id) ON DELETE CASCADE,
  reporter_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reason TEXT NOT NULL,
  details TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- تفعيل RLS على جدول التقارير
ALTER TABLE public.event_reports ENABLE ROW LEVEL SECURITY;

-- سياسات حماية جدول التقارير
CREATE POLICY "Anyone Can Submit Report" ON public.event_reports FOR INSERT WITH CHECK (
  auth.uid() IS NOT NULL
);

CREATE POLICY "Organizers/Staff Can See Reports" ON public.event_reports FOR SELECT USING (
  auth.uid() IN (
    SELECT op.owner_id 
    FROM organizer_profiles op
    JOIN events e ON e.organizer_id = op.id
    WHERE e.id = event_reports.event_id
  ) OR auth.uid() IN (
    SELECT sa.staff_id 
    FROM staff_assignments sa
    WHERE sa.event_id = event_reports.event_id AND sa.status = 'active'
  )
);

-- ٩. جدول الحظر (Blocks) لتمكين المستخدمين من كتم وحظر المنظمين المسيئين
CREATE TABLE IF NOT EXISTS public.blocks (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_organizer_id UUID REFERENCES public.organizer_profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, blocked_organizer_id)
);

-- تفعيل RLS على جدول الحظر
ALTER TABLE public.blocks ENABLE ROW LEVEL SECURITY;

-- سياسات حماية جدول الحظر
CREATE POLICY "Users Can Manage Own Blocks" ON public.blocks FOR ALL USING (
  auth.uid() = user_id
);

-- ١٠. دالة تحديد معدل الطلبات (Rate Limiting) لمنع السبام وإغراق قاعدة البيانات
CREATE OR REPLACE FUNCTION public.check_booking_rate_limit()
RETURNS trigger AS $$
DECLARE
  row_count INT;
  max_limit INT := 10; -- الحد الأقصى للحجوزات في الدقيقة الواحدة
  limit_interval INTERVAL := '1 minute';
BEGIN
  IF auth.uid() IS NOT NULL THEN
    -- حساب عدد الحجوزات التي قام بها المستخدم في آخر دقيقة
    SELECT COUNT(*) INTO row_count
    FROM public.bookings
    WHERE user_id = auth.uid()
      AND created_at > NOW() - limit_interval;

    IF row_count >= max_limit THEN
      RAISE EXCEPTION 'RATE_LIMIT_EXCEEDED: You have exceeded the booking limit. Please wait a minute and try again.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- تطبيق الـ Trigger على جدول الحجوزات لمنع الحجوزات العشوائية والمتكررة
DROP TRIGGER IF EXISTS bookings_rate_limit_trigger ON public.bookings;
CREATE TRIGGER bookings_rate_limit_trigger
  BEFORE INSERT ON public.bookings
  FOR EACH ROW EXECUTE PROCEDURE public.check_booking_rate_limit();

-- ١١. دالات إرسال الإشعارات المؤمنة بالكامل (Notification RPCs)
-- دالة إرسال الإشعارات للموظفين من طرف المنظم
CREATE OR REPLACE FUNCTION public.send_staff_notification(
  p_staff_id UUID,
  p_organizer_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_type TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS void AS $$
BEGIN
  -- التحقق من أن المستدعي هو مالك النادي المنظم
  IF auth.uid() IN (SELECT owner_id FROM public.organizer_profiles WHERE id = p_organizer_id) THEN
    INSERT INTO public.notifications (user_id, title, body, type, metadata)
    VALUES (p_staff_id, p_title, p_body, p_type, p_metadata);
  ELSE
    RAISE EXCEPTION 'UNAUTHORIZED: Only club owners can send staff notifications.';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- دالة إشعار المتابعين تلقائياً بالإعلانات والعروض الجديدة
CREATE OR REPLACE FUNCTION public.send_organizer_notification(
  p_organizer_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_type TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS void AS $$
BEGIN
  -- التحقق من أن المستدعي هو مالك النادي
  IF auth.uid() IN (SELECT owner_id FROM public.organizer_profiles WHERE id = p_organizer_id) THEN
    -- إدخال الإشعارات لكافة المتابعين للنادي دفعة واحدة
    INSERT INTO public.notifications (user_id, title, body, type, metadata)
    SELECT user_id, p_title, p_body, p_type, p_metadata
    FROM public.follows
    WHERE organizer_id = p_organizer_id;
  ELSE
    RAISE EXCEPTION 'UNAUTHORIZED: Only club owners can notify followers.';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ١٢. دالة الرقابة التلقائية وحجب الفعاليات المخالفة (Auto-Moderation Trigger)
CREATE OR REPLACE FUNCTION public.auto_hide_event_on_reports()
RETURNS trigger AS $$
DECLARE
  report_count INT;
BEGIN
  -- حساب إجمالي عدد البلاغات لهذه الفعالية
  SELECT COUNT(*) INTO report_count
  FROM public.event_reports
  WHERE event_id = NEW.event_id;

  -- حجب الفعالية تلقائياً إذا بلغ عدد البلاغات 20 بلاغاً أو أكثر
  IF report_count >= 20 THEN
    UPDATE public.events
    SET is_hidden = TRUE
    WHERE id = NEW.event_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- تطبيق الـ Trigger بعد إدخال أي بلاغ جديد
DROP TRIGGER IF EXISTS trigger_auto_hide_event ON public.event_reports;
CREATE TRIGGER trigger_auto_hide_event
  AFTER INSERT ON public.event_reports
  FOR EACH ROW EXECUTE PROCEDURE public.auto_hide_event_on_reports();

-- ١٣. دالة فحص القدرة الاستيعابية للفعالية قبل إتمام الحجز لمنع زيادة الحجوزات (Capacity Check Trigger)
CREATE OR REPLACE FUNCTION public.check_event_capacity_before_booking()
RETURNS trigger AS $$
DECLARE
  current_booked INT := 0;
  v_max_capacity INT;
BEGIN
  -- جلب السعة القصوى للفعالية
  SELECT max_capacity INTO v_max_capacity
  FROM public.events
  WHERE id = NEW.event_id;

  -- فحص السعة فقط إذا كانت محددة وأكبر من الصفر
  IF v_max_capacity IS NOT NULL AND v_max_capacity > 0 THEN
    -- حساب إجمالي الأماكن المحجوزة مسبقاً وغير الملغية
    SELECT COALESCE(SUM(num_guests), 0) INTO current_booked
    FROM public.bookings
    WHERE event_id = NEW.event_id
      AND payment_status != 'cancelled';

    -- إذا تجاوز الحجز الجديد السعة المتاحة
    IF (current_booked + NEW.num_guests) > v_max_capacity THEN
      RAISE EXCEPTION 'EVENT_FULL: The event has reached its maximum capacity. Only % spots left.', (v_max_capacity - current_booked);
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- تطبيق الـ Trigger قبل عملية الحجز الفعلي لضمان السلامة المطلقة
DROP TRIGGER IF EXISTS trigger_check_event_capacity ON public.bookings;
CREATE TRIGGER trigger_check_event_capacity
  BEFORE INSERT ON public.bookings
  FOR EACH ROW EXECUTE PROCEDURE public.check_event_capacity_before_booking();

-- ١٤. فهارس قاعدة البيانات لتسريع الاستعلامات وعمليات البحث (Sivox Performance Indexes)
-- [1] فهارس جدول الحجوزات (bookings)
CREATE INDEX IF NOT EXISTS idx_bookings_user_id ON bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_bookings_event_id ON bookings(event_id);
CREATE INDEX IF NOT EXISTS idx_bookings_payment_status ON bookings(payment_status);
CREATE INDEX IF NOT EXISTS idx_bookings_event_status ON bookings(event_id, payment_status);

-- [2] فهارس جدول الفعاليات (events)
CREATE INDEX IF NOT EXISTS idx_events_organizer_id ON events(organizer_id);
CREATE INDEX IF NOT EXISTS idx_events_date_time ON events(date_time);

-- [3] فهارس جدول تعيينات الموظفين (staff_assignments)
CREATE INDEX IF NOT EXISTS idx_staff_assignments_staff_id ON staff_assignments(staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_assignments_event_id ON staff_assignments(event_id);
CREATE INDEX IF NOT EXISTS idx_staff_assignments_status ON staff_assignments(status);
CREATE INDEX IF NOT EXISTS idx_staff_assignments_active ON staff_assignments(event_id, staff_id, status);

-- [4] فهارس جدول المتابعة (follows)
CREATE INDEX IF NOT EXISTS idx_follows_user_id ON follows(user_id);
CREATE INDEX IF NOT EXISTS idx_follows_organizer_id ON follows(organizer_id);

-- [5] فهارس جدول دوام الموظفين وسجلات التدقيق (staff_shifts & staff_logs)
CREATE INDEX IF NOT EXISTS idx_staff_shifts_staff_id ON staff_shifts(staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_logs_event_id ON staff_logs(related_event_id);
CREATE INDEX IF NOT EXISTS idx_staff_logs_user_id ON staff_logs(user_id);
