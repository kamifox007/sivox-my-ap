import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// 🔑 إعداد الثوابت الأمنية من المتغيرات البيئية للمشروع (Supabase Secrets)
const CHARGILY_WEBHOOK_SECRET = Deno.env.get("CHARGILY_WEBHOOK_SECRET") || "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

// إنشاء عميل Supabase بصلاحيات الأدمن الخارق (Service Role) لتحديث الحجوزات بعد التحقق من الدفع
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

/**
 * 🔒 التحقق من التوقيع الرقمي للطلب (Signature Verification) باستخدام خوارزمية HMAC SHA-256
 * لضمان أن الطلب قادم بالفعل من بوابة Chargily وليس طلباً مزوراً من مخترق.
 */
async function verifySignature(signature: string, payload: string, secret: string): Promise<boolean> {
  try {
    const encoder = new TextEncoder();
    const keyData = encoder.encode(secret);
    const messageData = encoder.encode(payload);

    // استيراد مفتاح التحقق السري
    const key = await crypto.subtle.importKey(
      "raw",
      keyData,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign", "verify"]
    );

    // تحويل التوقيع المستلم من صيغة Hexadecimal إلى مصفوفة بايتات
    const signatureBytes = new Uint8Array(
      signature.match(/.{1,2}/g)!.map((byte) => parseInt(byte, 16))
    );

    // التحقق من تطابق التواقيع
    return await crypto.subtle.verify(
      "HMAC",
      key,
      signatureBytes,
      messageData
    );
  } catch (e) {
    console.error("Signature parsing/verification error:", e);
    return false;
  }
}

serve(async (req) => {
  // نقبل فقط طلبات POST الخاصة بالـ Webhook
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    // 1. استخراج التوقيع الرقمي من الترويسة (Header)
    const signature = req.headers.get("Signature") || req.headers.get("signature");
    if (!signature) {
      console.warn("Unauthorized attempt: Missing signature header");
      return new Response(JSON.stringify({ error: "Missing signature header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 2. قراءة بايلود الطلب الخام (Raw Body) كما هو لضمان صحة التحقق من التوقيع
    const rawBody = await req.text();

    // 3. التحقق من أمان ومصدر الطلب
    const isValid = await verifySignature(signature, rawBody, CHARGILY_WEBHOOK_SECRET);
    if (!isValid) {
      console.warn("Alert: Forbidden attempt with invalid signature signature!");
      return new Response(JSON.stringify({ error: "Invalid signature" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 4. معالجة البيانات بعد ضمان الأمان
    const payload = JSON.parse(rawBody);
    
    // بوابة Chargily Pay V2 ترسل نوع الحدث 'checkout.paid' عند نجاح عملية الدفع
    if (payload.type === "checkout.paid") {
      const checkout = payload.data;
      const metadata = checkout.metadata || {};
      const bookingId = metadata.booking_id;
      const amount = checkout.amount;

      if (!bookingId) {
        console.warn("Invalid webhook payload: booking_id not found in metadata");
        return new Response(JSON.stringify({ error: "Missing booking_id in metadata" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }

      // 5. تحديث تذكرة الحجز وحالة الدفع في قاعدة البيانات بأمان
      const { data: updatedBooking, error: dbError } = await supabase
        .from("bookings")
        .update({
          payment_status: "confirmed",
          total_price_paid: amount,
          payment_confirmed: true,
          scanned_at_payment: new Date().toISOString(),
        })
        .eq("id", bookingId)
        .select()
        .single();

      if (dbError) {
        console.error(`Database update failed for booking ${bookingId}:`, dbError);
        return new Response(JSON.stringify({ error: "Database update failed", details: dbError.message }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        });
      }

      console.log(`Success: Confirmed booking ${bookingId} with amount ${amount} DA`);

      // 6. توثيق العملية في سجلات التدقيق والأمان لحماية العمليات المالية
      await supabase.from("staff_logs").insert({
        action_type: "ONLINE_PAYMENT_VERIFIED",
        description: `Online payment of ${amount} DA verified securely via Chargily Webhook for booking ${bookingId}`,
        related_event_id: updatedBooking.event_id,
      });

      return new Response(JSON.stringify({ success: true, message: "Booking confirmed successfully" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // تجاهل الأحداث الأخرى غير المدفوعة حالياً
    return new Response(JSON.stringify({ success: true, message: "Event received and ignored" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("Webhook processing exception:", error);
    return new Response(JSON.stringify({ error: "Internal server error", details: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
