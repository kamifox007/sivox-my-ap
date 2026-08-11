-- 🚀 SIVOX PRODUCTION SETUP & PERFORMANCE INDEXES (MASTER SQL SCRIPT)
-- الصق هذا السكريبت بالكامل داخل SQL Editor في لوحة تحكم Supabase واضغط على RUN لتفعيل كافة الميزات الأمنية وتسريع قاعدة البيانات.

-- =========================================================================
-- ١. تعديلات الجدول وتحديث الحقول المفقودة
-- =========================================================================
-- إضافة عمود is_hidden لجدول الفعاليات لتمكين نظام الفرز والحجب التلقائي
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN DEFAULT FALSE;

-- =========================================================================
-- ٢. دالة حذف الحساب الآمنة والنهائية (Account Deletion) متوافقة مع متجر جوجل بلاي
-- =========================================================================
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void AS $$
BEGIN
  -- حذف المستخدم الحالي من جدول auth.users مما يؤدي لحذف تسلسلي (CASCADE) لكافة بياناته في الجداول الأخرى
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth;

-- =========================================================================
-- ٣. جدول قائمة الحظر (Blacklist) لسلامة الفعاليات وأمان المستخدمين
-- =========================================================================
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
DROP POLICY IF EXISTS "Organizers/Staff Can Manage Blacklist" ON public.blacklist;
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

DROP POLICY IF EXISTS "Users Can Read Own Blacklist Status" ON public.blacklist;
CREATE POLICY "Users Can Read Own Blacklist Status" ON public.blacklist FOR SELECT USING (
  auth.uid() = user_id
);

-- =========================================================================
-- ٤. جدول التقارير عن الفعاليات المخالفة (Event Reports) للمراجعة الذاتية وأمان المحتوى
-- =========================================================================
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
DROP POLICY IF EXISTS "Anyone Can Submit Report" ON public.event_reports;
CREATE POLICY "Anyone Can Submit Report" ON public.event_reports FOR INSERT WITH CHECK (
  auth.uid() IS NOT NULL
);

DROP POLICY IF EXISTS "Organizers/Staff Can See Reports" ON public.event_reports;
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

-- =========================================================================
-- ٥. جدول الحظر (Blocks) لتمكين المستخدمين من كتم وحظر المنظمين المسيئين
-- =========================================================================
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
DROP POLICY IF EXISTS "Users Can Manage Own Blocks" ON public.blocks;
CREATE POLICY "Users Can Manage Own Blocks" ON public.blocks FOR ALL USING (
  auth.uid() = user_id
);

-- =========================================================================
-- ٦. فهارس الأداء العالي لقاعدة البيانات (High-Performance Indexes)
-- =========================================================================
-- فهرس للبحث الفوري في التذاكر والحجوزات حسب الفعالية وحالة الدفع (لتسريع عمل موظفي الدخول)
CREATE INDEX IF NOT EXISTS idx_bookings_event_status ON public.bookings(event_id, payment_status);

-- فهرس مركب لتسريع التحقق اللحظي من موظفي الفعاليات النشطين
CREATE INDEX IF NOT EXISTS idx_staff_assignments_active ON public.staff_assignments(event_id, staff_id, status);

-- فهرس لتسريع فرز وجلب الفعاليات حسب توقيت العرض (لجلب الفيد الرئيسي للتطبيق بسرعة فائقة)
CREATE INDEX IF NOT EXISTS idx_events_date_time ON public.events(date_time);

-- فهرس لتسريع عمليات الفرز الجغرافي للفعاليات حسب الإحداثيات
CREATE INDEX IF NOT EXISTS idx_events_geolocation ON public.events(latitude, longitude);

-- فهرس لتسريع استعلامات المتابعين للمنظمين والأندية
CREATE INDEX IF NOT EXISTS idx_follows_organizer ON public.follows(organizer_id, user_id);

-- =========================================================================
-- ٧. حماية إضافية من الحسابات الوهمية (تحديث handle_new_user)
-- =========================================================================
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

-- =========================================================================
-- ٨. دالة تحديد معدل الطلبات (Rate Limiting) لمنع الحجوزات العشوائية
-- =========================================================================
CREATE OR REPLACE FUNCTION public.check_booking_rate_limit()
RETURNS trigger AS $$
DECLARE
  row_count INT;
  max_limit INT := 10; -- الحد الأقصى للحجوزات في الدقيقة الواحدة
  limit_interval INTERVAL := '1 minute';
BEGIN
  IF auth.uid() IS NOT NULL THEN
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

DROP TRIGGER IF EXISTS bookings_rate_limit_trigger ON public.bookings;
CREATE TRIGGER bookings_rate_limit_trigger
  BEFORE INSERT ON public.bookings
  FOR EACH ROW EXECUTE PROCEDURE public.check_booking_rate_limit();

-- =========================================================================
-- ٩. دالات إرسال الإشعارات المؤمنة بالكامل (Notification RPCs)
-- =========================================================================
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

-- =========================================================================
-- ١٠. دالة الرقابة التلقائية وحجب الفعاليات المخالفة (Auto-Moderation Trigger)
-- =========================================================================
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

DROP TRIGGER IF EXISTS trigger_auto_hide_event ON public.event_reports;
CREATE TRIGGER trigger_auto_hide_event
  AFTER INSERT ON public.event_reports
  FOR EACH ROW EXECUTE PROCEDURE public.auto_hide_event_on_reports();

-- =========================================================================
-- ١١. دالة فحص القدرة الاستيعابية للفعالية قبل إتمام الحجز لمنع زيادة الحجوزات
-- =========================================================================
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

DROP TRIGGER IF EXISTS trigger_check_event_capacity ON public.bookings;
CREATE TRIGGER trigger_check_event_capacity
  BEFORE INSERT ON public.bookings
  FOR EACH ROW EXECUTE PROCEDURE public.check_event_capacity_before_booking();
