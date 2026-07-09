const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const {
    onDocumentWritten,
    onDocumentCreated,
    onDocumentUpdated
} = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

const { setGlobalOptions } = require("firebase-functions/v2");
setGlobalOptions({ maxInstances: 10, region: 'asia-southeast1' });

// ─── CONFIG CACHE (5-min TTL) ─────────────────────────────────────────────────
// อ่าน admin_config จาก Firestore ครั้งเดียวต่อ instance แล้ว cache ไว้
// ทำให้ admin เปลี่ยน rate ใน Firestore โดยไม่ต้อง redeploy
let _configCache = null;
let _configCachedAt = 0;
const CONFIG_TTL_MS = 5 * 60 * 1000; // 5 minutes

exports.calculateVendorFee = onCall(async (request) => {
    const totalSales = request.data.totalSales || 0;
    const accumulatedCommission = request.data.accumulatedCommission || 0;

    if (typeof totalSales !== 'number' || totalSales < 0) {
        throw new HttpsError('invalid-argument', 'totalSales must be a positive number');
    }

    let fee = 0;
    if (totalSales <= 5000) fee = 0;
    else if (totalSales <= 25000) fee = 159;
    else if (totalSales <= 55000) fee = 359;
    else if (totalSales <= 150000) fee = 759;
    else if (totalSales <= 250000) fee = 1259;
    else fee = 1259 + (totalSales - 250000) * 0.07;

    fee = parseFloat((fee + accumulatedCommission).toFixed(2));
    logger.info(`fee=${fee} (base+commission:${accumulatedCommission}) totalSales=${totalSales}`);
    return { fee: fee };
});

exports.updateVendorSales = onDocumentWritten("orders/{orderId}", async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const before = snapshot.before.data();
    const after = snapshot.after.data();
    if (!after) return;

    const vendorId = after.vendorId;
    if (!vendorId) return;

    const status = after.status;
    const previousStatus = before ? before.status : null;

    if (status === 'delivered' && previousStatus !== 'delivered') {
        const vendorEarnings = Number(after.vendorEarnings || 0);
        const platformCommission = Number(after.platformCommission || 0);
        if (vendorEarnings <= 0) return;

        const vendorRef = admin.firestore().collection('vendors').doc(vendorId);
        const monthKey = new Date().toISOString().slice(0, 7);

        await vendorRef.update({
            totalSales: admin.firestore.FieldValue.increment(vendorEarnings),
            accumulatedCommission: admin.firestore.FieldValue.increment(platformCommission),
        });
        const monthRef = vendorRef.collection('monthly_sales').doc(monthKey);
        await monthRef.set({
            total_sales: admin.firestore.FieldValue.increment(vendorEarnings),
            platform_commission: admin.firestore.FieldValue.increment(platformCommission),
            paid: false,
            month: monthKey,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        logger.info(`✅ vendor:+${vendorEarnings} commission:+${platformCommission} | Vendor: ${vendorId} | Month: ${monthKey}`);
    }
});

exports.notifyVendorNewOrder = onDocumentCreated("orders/{orderId}", async (event) => {
    const orderData = event.data.data();
    const vendorId = orderData.vendorId;

    if (!vendorId) return;

    const vendorSnap = await admin.firestore().collection('vendors').doc(vendorId).get();
    const fcmToken = vendorSnap.data()?.fcmToken;

    if (!fcmToken) return;

    const message = {
        token: fcmToken,
        notification: {
            title: "🛵 มีออร์เดอร์ใหม่!",
            body: `ออร์เดอร์ ${event.params.orderId} เข้ามาแล้ว`,
        },
        data: {
            orderId: event.params.orderId,
            type: "new_order_vendor"
        },
        android: {
            priority: 'high',
            notification: {
                channelId: 'new_order_channel',
                sound: 'new_order_sound',
                defaultSound: false,
                defaultVibrateTimings: false,
                vibrateTimingsMillis: [0, 500, 200, 500],
            },
        },
    };

    try {
        await admin.messaging().send(message);
        console.log(`[SUCCESS-VENDOR] ส่งสำเร็จ → ${vendorId}`);
    } catch (e) {
        console.error(`[ERROR-VENDOR] ${e.message}`);
    }
});

// ─── HELPER ────────────────────────────────────────────────────────────────────

function formatThaiDate(date) {
  if (!date) return '-';
  const thMonth = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  const d = date.getDate();
  const m = thMonth[date.getMonth()];
  const y = date.getFullYear() + 543;
  const h = String(date.getHours()).padStart(2, '0');
  const min = String(date.getMinutes()).padStart(2, '0');
  return `${d} ${m} ${y} ${h}:${min}`;
}

// ─── SERVICE BOOKING NOTIFICATIONS ────────────────────────────────────────────

exports.notifyVendorNewServiceBooking = onDocumentCreated(
  {
    document: 'service_bookings/{bookingId}',
    region: 'asia-southeast1',
  },
  async (event) => {
    const booking = event.data.data();
    if (!booking) return;

    const vendorId = booking.shopId;
    if (!vendorId) return;

    const vendorSnap = await admin.firestore().collection('vendors').doc(vendorId).get();
    const fcmToken = vendorSnap.data()?.fcmToken;

    if (!fcmToken) {
      console.log('[SERVICE-NOTIFY] Vendor has no FCM token:', vendorId);
      return;
    }

    const bookingDate = booking.bookingDate?.toDate();
    const dateStr = formatThaiDate(bookingDate);

    const message = {
      token: fcmToken,
      notification: {
        title: '🛎️ มีการจองบริการใหม่!',
        body: `${booking.customerName} จอง ${booking.serviceName}\n${dateStr}`,
      },
      data: {
        type: 'new_service_booking',
        bookingId: event.params.bookingId,
        shopId: vendorId,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'new_order_channel',
          sound: 'new_order_sound',
        },
      },
    };

    try {
      await admin.messaging().send(message);
      console.log('[SERVICE-NOTIFY] Notified vendor:', vendorId);
    } catch (e) {
      console.error('[SERVICE-NOTIFY] FCM send error:', e.message);
    }
  }
);

exports.notifyServiceBookingStatusUpdate = onDocumentUpdated(
  {
    document: 'service_bookings/{bookingId}',
    region: 'asia-southeast1',
  },
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    if (before.status === after.status) return;

    // Skip notification for walk-in bookings (no customer app account)
    if (after.isWalkIn === true) return;

    const customerId = after.customerId;
    const vendorId = after.shopId;
    const newStatus = after.status;

    let recipient = null;
    let title = '';
    let body = '';

    if (newStatus === 'confirmed') {
      recipient = 'customer';
      title = '✅ ร้านยืนยันการจอง';
      body = `${after.shopName} ยืนยัน ${after.serviceName} ของคุณ`;
    } else if (newStatus === 'rejected') {
      recipient = 'customer';
      title = '❌ การจองถูกปฏิเสธ';
      body = `${after.shopName} ไม่สะดวก${after.cancelReason ? ': ' + after.cancelReason : ''}`;
    } else if (newStatus === 'in_service') {
      recipient = 'customer';
      title = '🛎️ เริ่มบริการแล้ว';
      body = `${after.shopName} เริ่มให้บริการ ${after.serviceName}`;
    } else if (newStatus === 'completed') {
      recipient = 'customer';
      title = '🌟 บริการเสร็จแล้ว';
      body = `กรุณาให้คะแนน ${after.shopName} เพื่อช่วยลูกค้าคนอื่น`;
    } else if (newStatus === 'cancelled') {
      recipient = 'vendor';
      title = '🚫 ลูกค้ายกเลิกการจอง';
      body = `${after.customerName} ยกเลิก ${after.serviceName}`;
    } else {
      return;
    }

    const recipientId = recipient === 'customer' ? customerId : vendorId;
    const collection = recipient === 'customer' ? 'buyers' : 'vendors';

    const userSnap = await admin.firestore().collection(collection).doc(recipientId).get();
    const fcmToken = userSnap.data()?.fcmToken;

    if (!fcmToken) {
      console.log(`[SERVICE-STATUS] No FCM token for ${recipient}:`, recipientId);
      return;
    }

    const message = {
      token: fcmToken,
      notification: { title, body },
      data: {
        type: `service_booking_${newStatus}`,
        bookingId: event.params.bookingId,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: recipient === 'customer' ? 'order_status_channel' : 'new_order_channel',
          sound: 'order_ready',
        },
      },
    };

    try {
      await admin.messaging().send(message);
      console.log(`[SERVICE-STATUS] Notified ${recipient} (${recipientId}):`, newStatus);
    } catch (e) {
      console.error('[SERVICE-STATUS] FCM send error:', e.message);
    }
  }
);

exports.notifyServiceBookingReminder = onSchedule(
  {
    schedule: 'every 15 minutes',
    timeZone: 'Asia/Bangkok',
    region: 'asia-southeast1',
  },
  async (event) => {
    const db = admin.firestore();
    const now = new Date();
    const oneHourLater = new Date(now.getTime() + 60 * 60 * 1000);
    const oneHourFifteenLater = new Date(now.getTime() + 75 * 60 * 1000);

    const snap = await db.collection('service_bookings')
      .where('status', '==', 'confirmed')
      .where('bookingDate', '>=', admin.firestore.Timestamp.fromDate(oneHourLater))
      .where('bookingDate', '<', admin.firestore.Timestamp.fromDate(oneHourFifteenLater))
      .get();

    for (const doc of snap.docs) {
      const booking = doc.data();
      if (booking.reminderSent === true) continue;

      const customerSnap = await db.collection('buyers').doc(booking.customerId).get();
      const vendorSnap = await db.collection('vendors').doc(booking.shopId).get();

      const customerToken = customerSnap.data()?.fcmToken;
      const vendorToken = vendorSnap.data()?.fcmToken;

      const promises = [];

      if (customerToken) {
        promises.push(admin.messaging().send({
          token: customerToken,
          notification: {
            title: '⏰ ใกล้ถึงเวลานัด',
            body: `อีก 1 ชม. จะถึงเวลานัด ${booking.serviceName}`,
          },
          data: { type: 'service_reminder', bookingId: doc.id },
          android: {
            priority: 'high',
            notification: { channelId: 'order_status_channel', sound: 'order_ready' },
          },
        }));
      }

      if (vendorToken) {
        promises.push(admin.messaging().send({
          token: vendorToken,
          notification: {
            title: '⏰ ใกล้ถึงเวลานัด',
            body: `อีก 1 ชม. จะถึงนัดของ ${booking.customerName} (${booking.serviceName})`,
          },
          data: { type: 'service_reminder', bookingId: doc.id },
          android: {
            priority: 'high',
            notification: { channelId: 'new_order_channel', sound: 'new_order_sound' },
          },
        }));
      }

      promises.push(doc.ref.update({ reminderSent: true }));

      try {
        await Promise.all(promises);
        console.log('[SERVICE-REMINDER] Sent reminder for booking:', doc.id);
      } catch (e) {
        console.error('[SERVICE-REMINDER] Error for booking:', doc.id, e.message);
      }
    }
  }
);

exports.notifyRiderNewOrder = onDocumentUpdated("orders/{orderId}", async (event) => {
    const newData = event.data.after.data();
    const oldData = event.data.before.data();

    if (oldData?.status !== "pending_rider" && newData?.status === "pending_rider") {
        const riderId = newData.riderId;
        console.log(`[RIDER] Status เปลี่ยนเป็น pending_rider → Rider: ${riderId}`);

        if (!riderId) return;

        const riderSnap = await admin.firestore().collection("riders").doc(riderId).get();
        const fcmToken = riderSnap.data()?.fcmToken;

        if (!fcmToken) {
            console.log(`[SKIP-RIDER] ไม่มี fcmToken`);
            return;
        }

        const message = {
            token: fcmToken,
            data: {
                title: "🚀 มีงานส่งใหม่!",
                body: `ออร์เดอร์ ${event.params.orderId}`,
                orderId: event.params.orderId,
                type: "new_order_rider"
            },
            android: {
                priority: 'high',
            },
        };

        try {
            await admin.messaging().send(message);
            console.log(`[SUCCESS-RIDER] ส่งสำเร็จ → ${riderId}`);
        } catch (e) {
            console.error(`[ERROR-RIDER] ${e.message}`);
        }
    }
});

exports.notifyBuyerOrderReady = onDocumentUpdated("orders/{orderId}", async (event) => {
    const newData = event.data.after.data();
    const oldData = event.data.before.data();

    if (oldData?.status === 'delivered' || newData?.status !== 'delivered') return;

    const serviceType = newData.serviceType ?? 'pickup';
    const paymentMethod = newData.paymentMethod ?? '';

    if (serviceType === 'delivery') {

        return;
    }
    if (paymentMethod === 'cash') {
        return;
    }

    const buyerId = newData.buyerId;
    if (!buyerId) {
        console.log(`[SKIP-BUYER] ไม่มี buyerId`);
        return;
    }
    const buyerSnap = await admin.firestore().collection('buyers').doc(buyerId).get();
    const fcmToken = buyerSnap.data()?.fcmToken;

    if (!fcmToken) {
        console.log(`[SKIP-BUYER] ไม่มี fcmToken สำหรับ buyer: ${buyerId}`);
        return;
    }

    const orderId = event.params.orderId;
    const vendorName = newData.bussiName ?? 'ร้านค้า';

    const label = serviceType === 'dine-in' ? 'รับที่โต๊ะ' : 'รับที่ร้าน';

    const message = {
        token: fcmToken,
        notification: {
            title: '🍽️ อาหารพร้อมแล้ว!',
            body: `${vendorName} — ${label} ได้เลยครับ`,
        },
        data: {
            orderId: orderId,
            type: 'order_ready_buyer',
            title: '🍽️ อาหารพร้อมแล้ว!',
            body: `${vendorName} — ${label} ได้เลยครับ`,
        },
        android: {
            priority: 'high',
            notification: {
                channelId: 'order_ready_channel',
                sound: 'order_ready',
                defaultSound: false,
            },
        },
    };

    try {
        await admin.messaging().send(message);
        console.log(`[SUCCESS-BUYER] ส่งสำเร็จ → buyer: ${buyerId} | order: ${orderId} | type: ${serviceType}`);
    } catch (e) {
        console.error(`[ERROR-BUYER] ${e.message}`);
    }
});
exports.deleteChatsOnOrderDelivered = onDocumentUpdated("orders/{orderId}", async (event) => {
    const newData = event.data.after.data();
    const oldData = event.data.before.data();

    if (oldData?.status === 'delivered' || newData?.status !== 'delivered') return;

    const buyerId = newData.buyerId;
    const vendorId = newData.vendorId;
    const orderId = event.params.orderId;

    if (!buyerId || !vendorId) return;

    const db = admin.firestore();
    const batch = db.batch();

    try {
        const vendorBuyerSnap = await db.collection('chats')
            .where('buyerId', '==', buyerId)
            .where('vendorId', '==', vendorId)
            .get();
        vendorBuyerSnap.docs.forEach(doc => {
            const proId = doc.data().proId ?? '';
            if (typeof proId === 'string' && proId.startsWith('hotel_')) return;
            batch.delete(doc.ref);
        });

        const riderBuyerSnap = await db.collection('chats')
            .where('orderId', '==', orderId)
            .get();
        riderBuyerSnap.docs.forEach(doc => {
            const proId = doc.data().proId ?? '';
            if (typeof proId === 'string' && proId.startsWith('hotel_')) return;
            batch.delete(doc.ref);
        });

        await batch.commit();
        console.log(`[DELETE-CHATS] ✅ orderId=${orderId} | vendorBuyer=${vendorBuyerSnap.size} | riderBuyer=${riderBuyerSnap.size}`);
    } catch (e) {
        console.error(`[DELETE-CHATS] ❌ ${e.message}`);
    }
});

exports.notifyBuyerFoodReady = onDocumentUpdated("orders/{orderId}", async (event) => {
    const newData = event.data.after.data();
    const oldData = event.data.before.data();

    // ทำงานเฉพาะตอนที่ field เปลี่ยนจาก false/undefined → true
    if (!newData?.notifyCustomerReady || oldData?.notifyCustomerReady === true) return;

    const buyerId = newData.buyerId;
    if (!buyerId) return;

    const buyerSnap = await admin.firestore().collection('buyers').doc(buyerId).get();
    const fcmToken = buyerSnap.data()?.fcmToken;
    if (!fcmToken) return;

    const orderId = event.params.orderId;
    const vendorName = newData.bussiName ?? 'ร้านค้า';

    const message = {
        token: fcmToken,
        notification: {
            title: '🔔 อาหารพร้อมแล้ว!',
            body: `${vendorName} — กรุณาชำระเงินได้เลยครับ`,
        },
        data: {
            orderId: orderId,
            type: 'food_ready_cash',
            title: '🔔 อาหารพร้อมแล้ว!',
            body: `${vendorName} — กรุณาชำระเงินได้เลยครับ`,
        },
        android: {
            priority: 'high',
            notification: {
                channelId: 'order_ready_channel',
                sound: 'order_ready',
                defaultSound: false,
            },
        },
    };

    try {
        await admin.messaging().send(message);
        console.log(`[SUCCESS-FOOD-READY] → buyer: ${buyerId} | order: ${orderId}`);

        // reset flag หลังส่งแล้ว เพื่อกันส่งซ้ำ
        await admin.firestore().collection('orders').doc(orderId).update({
            notifyCustomerReady: false,
        });
    } catch (e) {
        console.error(`[ERROR-FOOD-READY] ${e.message}`);
    }
});

// ─── REFERRAL SYSTEM ───────────────────────────────────────────────────────────

async function getUserDoc(userId) {
  const db = admin.firestore();
  const [buyerDoc, vendorDoc, riderDoc] = await Promise.all([
    db.collection('buyers').doc(userId).get(),
    db.collection('vendors').doc(userId).get(),
    db.collection('riders').doc(userId).get(),
  ]);
  if (buyerDoc.exists) return { doc: buyerDoc, col: 'buyers', userType: 'customer' };
  if (vendorDoc.exists) return { doc: vendorDoc, col: 'vendors', userType: 'vendor' };
  if (riderDoc.exists) return { doc: riderDoc, col: 'riders', userType: 'rider' };
  return null;
}

async function checkQualified(userId) {
  const db = admin.firestore();
  const found = await getUserDoc(userId);
  if (!found) return false;

  const { doc, userType } = found;
  const data = doc.data();

  // เงื่อนไข 1: ต้องแนะนำครบ 12 คน
  if ((data.referralCount ?? 0) < 12) return false;

  // เงื่อนไข 2: ยอดเดือนปัจจุบัน (monthly) ตามประเภท user
  const monthKey = new Date().toISOString().slice(0, 7);

  if (userType === 'customer') {
    const monthDoc = await db.collection('buyers').doc(userId)
        .collection('monthly_spending').doc(monthKey).get();
    return (monthDoc.data()?.total ?? 0) >= 5000;
  }

  if (userType === 'vendor') {
    const monthDoc = await db.collection('vendors').doc(userId)
        .collection('monthly_sales').doc(monthKey).get();
    return (monthDoc.data()?.total_sales ?? 0) >= 5000;
  }

  if (userType === 'rider') {
    const monthDoc = await db.collection('riders').doc(userId)
        .collection('monthly_earnings').doc(monthKey).get();
    return (monthDoc.data()?.total ?? 0) >= 5000;
  }

  return false;
}

async function generateUniqueReferralCode() {
  const db = admin.firestore();
  const digits = '0123456789';

  let attempts = 0;
  while (attempts < 10) {
    // generate 13 หลัก
    let code = '';
    for (let i = 0; i < 13; i++) {
      code += digits.charAt(Math.floor(Math.random() * digits.length));
    }

    // เช็คว่าซ้ำไหมใน 3 collections พร้อมกัน
    const [b, v, r] = await Promise.all([
      db.collection('buyers').where('referralCode', '==', code).limit(1).get(),
      db.collection('vendors').where('referralCode', '==', code).limit(1).get(),
      db.collection('riders').where('referralCode', '==', code).limit(1).get(),
    ]);

    // ถ้าไม่ซ้ำ return code นี้
    if (b.empty && v.empty && r.empty) return code;

    attempts++;
    logger.warn(`[GEN-CODE] collision attempt ${attempts}`);
  }

  // fallback ถ้าชน 10 ครั้งติด (แทบเป็นไปไม่ได้) เพิ่มเป็น 16 หลัก
  let code = '';
  for (let i = 0; i < 16; i++) {
    code += digits.charAt(Math.floor(Math.random() * digits.length));
  }
  logger.error('[GEN-CODE] fallback to 16 digits after 10 collisions');
  return code;
}

// ─── CONFIG LOADER ────────────────────────────────────────────────────────────

async function getConfig(db) {
  const now = Date.now();
  if (_configCache && (now - _configCachedAt) < CONFIG_TTL_MS) return _configCache;

  const [platformDoc, mlmDoc] = await Promise.all([
    db.collection('admin_config').doc('platform_rates').get(),
    db.collection('admin_config').doc('mlm_level_rates').get(),
  ]);

  _configCache = {
    platformRates: platformDoc.data() ?? {},
    mlmLevels: (mlmDoc.data()?.levels) ?? [0.20, 0.10, 0.05, 0.03, 0.02],
  };
  _configCachedAt = now;
  logger.info('[CONFIG] cache refreshed');
  return _configCache;
}

// ─── GENERIC MLM COMMISSION ───────────────────────────────────────────────────
/**
 * คำนวณและบันทึก referral_transactions สำหรับทุก mode (delivery/hotel/services/vehicle)
 *
 * Pool calculation: baseAmount × mode.rate × mode.mlmPoolRatio
 *   เช่น delivery: 1000 × 0.15 × 0.40 = 60 บาท (admin เปลี่ยนได้ใน Firestore)
 *
 * @param {object} p
 * @param {'delivery'|'hotel'|'services'|'vehicle'} p.source
 * @param {string}  p.fromUserId  – buyer/guest UID
 * @param {string}  p.refId       – orderId / bookingId
 * @param {string}  p.refField    – ชื่อ field ใน transaction doc (เช่น 'orderId', 'bookingId')
 * @param {number}  p.baseAmount  – ยอดเงิน base สำหรับคำนวณ pool
 * @param {object}  [p.extraFields] – fields เพิ่มเติมที่ต้องการบันทึกในแต่ละ transaction
 * @param {admin.firestore.Firestore} p.db
 * @returns {Promise<{ pool: number, txCount: number }>}
 */
async function calculateMlmCommission({ source, fromUserId, refId, refField, baseAmount, extraFields = {}, db }) {
  const config = await getConfig(db);
  const modeConfig = config.platformRates[source] ?? {};
  const rate       = Number(modeConfig.rate         ?? 0.15);
  const poolRatio  = Number(modeConfig.mlmPoolRatio ?? 0.40);
  const levelRates = config.mlmLevels;

  // pool = platform fee share ที่แบ่งให้ MLM network
  const pool = parseFloat((baseAmount * rate * poolRatio).toFixed(2));
  if (pool <= 0) return { pool: 0, txCount: 0 };

  const userFound = await getUserDoc(fromUserId);
  if (!userFound) return { pool, txCount: 0 };

  const uplineIds = userFound.doc.data()?.uplineIds ?? [];
  if (uplineIds.length === 0) return { pool, txCount: 0 };

  const month = new Date().toISOString().slice(0, 7);
  const batch = db.batch();
  const count = Math.min(uplineIds.length, levelRates.length);

  for (let i = 0; i < count; i++) {
    const commission = parseFloat((pool * levelRates[i]).toFixed(2));
    const txRef = db.collection('referral_transactions').doc();
    batch.set(txRef, {
      source,
      fromBuyerId: fromUserId,
      toUserId: uplineIds[i],
      [refField]: refId,
      level: i + 1,
      baseAmount,
      pool,
      commissionRate: levelRates[i],
      amount: commission,
      month,
      status: 'pending_payout',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      ...extraFields,
    });
  }

  await batch.commit();
  return { pool, txCount: count };
}

// ─── DELIVERY: referral commission ────────────────────────────────────────────

exports.processReferralCommission = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();

  if (before?.status === after?.status) return;
  if (after?.status !== 'delivered') return;

  const db      = admin.firestore();
  const orderId = event.params.orderId;
  const buyerId = after.buyerId;
  if (!buyerId) return;

  const shippingCharge = Number(after.shippingCharge ?? 0);
  const shippingFee    = Number(after.shippingFee    ?? 0); // ecommerce field
  const totalPrice     = Number(after.totalPrice     ?? 0);
  const foodTotal      = totalPrice - shippingCharge - shippingFee;
  if (foodTotal <= 0) return;

  const { pool, txCount } = await calculateMlmCommission({
    source: 'delivery',
    fromUserId: buyerId,
    refId: orderId,
    refField: 'orderId',
    baseAmount: foodTotal,
    extraFields: { foodTotal },
    db,
  });

  logger.info(`[REFERRAL] ✅ orderId=${orderId} pool=${pool} uplines=${txCount}`);
});

// ─── HOTEL: referral commission ───────────────────────────────────────────────

exports.processHotelReferralCommission = onDocumentUpdated("hotel_bookings/{bookingId}", async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();

  if (before?.status === after?.status) return;
  if (after?.status !== 'completed') return;

  const db        = admin.firestore();
  const bookingId = event.params.bookingId;
  const guestId   = after.guestId;
  if (!guestId) return;

  const totalPrice      = Number(after.totalPrice    ?? 0);
  const refundAmount    = Number(after.refundAmount  ?? 0);
  const effectiveAmount = totalPrice - refundAmount;
  if (effectiveAmount <= 0) return; // คืนเงินเต็ม = ไม่คิด MLM

  const { pool, txCount } = await calculateMlmCommission({
    source: 'hotel',
    fromUserId: guestId,
    refId: bookingId,
    refField: 'bookingId',
    baseAmount: effectiveAmount,
    extraFields: { totalPrice, effectiveAmount, refundAmount },
    db,
  });

  // update buyers totalSpent + monthly_spending (hotel-specific)
  const month = new Date().toISOString().slice(0, 7);
  await db.collection('buyers').doc(guestId).update({
    totalSpent: admin.firestore.FieldValue.increment(effectiveAmount),
  });
  await db.collection('buyers').doc(guestId)
      .collection('monthly_spending').doc(month)
      .set({
        total: admin.firestore.FieldValue.increment(effectiveAmount),
        month,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

  logger.info(`[HOTEL-REFERRAL] ✅ bookingId=${bookingId} pool=${pool} uplines=${txCount}`);
});

// ─── SERVICES: referral commission ────────────────────────────────────────────

exports.onServiceBookingComplete = onDocumentUpdated("service_bookings/{bookingId}", async (event) => {
  const before = event.data.before.data();
  const after  = event.data.after.data();

  if (before?.status === after?.status) return;
  if (after?.status !== 'completed') return;

  // Skip MLM for walk-in bookings (no customer referral chain)
  if (after.isWalkIn === true) {
    logger.info(`[SERVICE-REFERRAL] Skip walk-in booking: ${event.params.bookingId}`);
    return;
  }

  const db        = admin.firestore();
  const bookingId = event.params.bookingId;
  const buyerId   = after.buyerId ?? after.guestId ?? after.customerId;
  if (!buyerId) {
    logger.info(`[SERVICE-REFERRAL] Skip booking without customerId: ${bookingId}`);
    return;
  }

  const totalPrice = Number(after.totalPrice ?? 0);
  if (totalPrice <= 0) return;

  const { pool, txCount } = await calculateMlmCommission({
    source: 'services',
    fromUserId: buyerId,
    refId: bookingId,
    refField: 'bookingId',
    baseAmount: totalPrice,
    extraFields: {
      totalPrice,
      serviceTypeId: after.serviceTypeId ?? '',
      vendorId: after.vendorId ?? '',
    },
    db,
  });

  // update buyer totalSpent + monthly_spending
  const month = new Date().toISOString().slice(0, 7);
  try {
    await db.collection('buyers').doc(buyerId).update({
      totalSpent: admin.firestore.FieldValue.increment(totalPrice),
    });
    await db.collection('buyers').doc(buyerId)
        .collection('monthly_spending').doc(month)
        .set({
          total: admin.firestore.FieldValue.increment(totalPrice),
          month,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
  } catch (e) {
    logger.warn(`[SERVICE-REFERRAL] totalSpent update skipped for ${buyerId}: ${e.message}`);
  }

  logger.info(`[SERVICE-REFERRAL] ✅ bookingId=${bookingId} pool=${pool} uplines=${txCount}`);
});

exports.monthlyReferralPayout = onSchedule({
  schedule: '0 9 5 * *',  // 09:00 วันที่ 5 ทุกเดือน
  timeZone: 'Asia/Bangkok',
  region: 'asia-southeast1',
}, async (event) => {
  const db = admin.firestore();
  const now = new Date();

  // คำนวณเดือนก่อน
  const prevMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const prevMonthKey = prevMonth.toISOString().slice(0, 7); // "2026-05"

  logger.info(`[PAYOUT] เริ่ม payout เดือน ${prevMonthKey}`);

  // ดึง transactions ทั้งหมดของเดือนก่อน ที่ยัง pending_payout
  const snap = await db.collection('referral_transactions')
    .where('month', '==', prevMonthKey)
    .where('status', '==', 'pending_payout')
    .get();

  if (snap.empty) {
    logger.info(`[PAYOUT] ไม่มี transaction ในเดือน ${prevMonthKey}`);
    return;
  }

  // group ตาม toUserId
  const userTotals = {}; // { uid: { total: 0, txIds: [] } }
  for (const doc of snap.docs) {
    const d = doc.data();
    const uid = d.toUserId;
    const amount = Number(d.amount ?? 0);
    if (!userTotals[uid]) userTotals[uid] = { total: 0, txIds: [] };
    userTotals[uid].total += amount;
    userTotals[uid].txIds.push(doc.id);
  }

  // จ่าย commission ทีละคน
  let qualifiedCount = 0;
  let unqualifiedCount = 0;
  let platformTotal = 0;

  for (const [uid, data] of Object.entries(userTotals)) {
    const qualified = await checkQualified(uid);
    const totalAmount = parseFloat(data.total.toFixed(2));

    if (qualified) {
      // อัปเดต earnings ของ user
      await db.collection('referral_earnings').doc(uid).set({
        pendingEarnings: admin.firestore.FieldValue.increment(totalAmount),
        totalEarnings: admin.firestore.FieldValue.increment(totalAmount),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      // mark transactions as paid_out
      const batch = db.batch();
      for (const txId of data.txIds) {
        batch.update(db.collection('referral_transactions').doc(txId), {
          status: 'paid_out',
          paidOutAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      qualifiedCount++;
      logger.info(`[PAYOUT] ✅ ${uid}: +฿${totalAmount}`);
    } else {
      // ไป platform
      platformTotal += totalAmount;

      const batch = db.batch();
      for (const txId of data.txIds) {
        batch.update(db.collection('referral_transactions').doc(txId), {
          status: 'forfeited',
          forfeitedAt: admin.firestore.FieldValue.serverTimestamp(),
          originalToUserId: uid,
          toUserId: 'platform',
        });
      }
      await batch.commit();

      unqualifiedCount++;
      logger.info(`[PAYOUT] ❌ ${uid} ไม่ qualified: ฿${totalAmount} → platform`);
    }
  }

  // อัปเดต platform earnings
  if (platformTotal > 0) {
    await db.collection('referral_earnings').doc('platform').set({
      pendingEarnings: admin.firestore.FieldValue.increment(platformTotal),
      totalEarnings: admin.firestore.FieldValue.increment(platformTotal),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  logger.info(`[PAYOUT] DONE: qualified=${qualifiedCount} forfeited=${unqualifiedCount} platform=฿${platformTotal}`);
});

exports.deleteOldHotelChats = onSchedule({
  schedule: '0 3 * * *',  // ทุกวัน 03:00
  timeZone: 'Asia/Bangkok',
  region: 'asia-southeast1',
}, async (event) => {
  const db = admin.firestore();
  const now = new Date();
  const cutoff = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000); // 30 วันก่อน

  logger.info(`[CHAT-CLEANUP] เริ่มลบ hotel chat ก่อน ${cutoff.toISOString()}`);

  // หา booking ที่ completed + checkOut เกิน 30 วัน
  const bookingsSnap = await db.collection('hotel_bookings')
    .where('status', '==', 'completed')
    .where('checkOut', '<', admin.firestore.Timestamp.fromDate(cutoff))
    .get();

  if (bookingsSnap.empty) {
    logger.info('[CHAT-CLEANUP] ไม่มี booking ที่ต้องลบ chat');
    return;
  }

  let deletedChats = 0;
  let processedBookings = 0;

  for (const bookingDoc of bookingsSnap.docs) {
    const bookingId = bookingDoc.id;
    const proId = `hotel_${bookingId}`;

    // ข้ามถ้าลบไปแล้ว (มี flag)
    if (bookingDoc.data().chatDeleted === true) continue;

    // ลบ chat ของ booking นี้
    const chatSnap = await db.collection('chats')
      .where('proId', '==', proId)
      .get();

    if (!chatSnap.empty) {
      const batch = db.batch();
      chatSnap.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      deletedChats += chatSnap.docs.length;
    }

    // mark ว่าลบ chat แล้ว (กันลบซ้ำ + skip ครั้งหน้า)
    await bookingDoc.ref.update({ chatDeleted: true });
    processedBookings++;
  }

  logger.info(`[CHAT-CLEANUP] DONE: bookings=${processedBookings} chats deleted=${deletedChats}`);
});

exports.autoConfirmEcommerceDelivered = onSchedule({
  schedule: '0 2 * * *',  // ทุกวัน 02:00
  timeZone: 'Asia/Bangkok',
  region: 'asia-southeast1',
}, async (event) => {
  const db = admin.firestore();
  const now = new Date();
  const cutoff = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000); // 7 วันก่อน

  logger.info(`[AUTO-CONFIRM] เริ่มหา ecommerce orders shipped < ${cutoff.toISOString()}`);

  let ordersSnap;
  try {
    ordersSnap = await db.collection('orders')
      .where('orderType', '==', 'ecommerce')
      .where('status', '==', 'shipped')
      .where('shippedAt', '<', admin.firestore.Timestamp.fromDate(cutoff))
      .get();
  } catch (err) {
    logger.error('[AUTO-CONFIRM] query error (อาจต้องสร้าง composite index):', err);
    return;
  }

  if (ordersSnap.empty) {
    logger.info('[AUTO-CONFIRM] ไม่มี orders ที่ต้อง confirm');
    return;
  }

  let confirmedCount = 0;
  let failedCount = 0;

  for (const orderDoc of ordersSnap.docs) {
    try {
      await orderDoc.ref.update({
        status: 'delivered',
        deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        autoConfirmed: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      confirmedCount++;
      logger.info(`[AUTO-CONFIRM] order ${orderDoc.id} → delivered`);
    } catch (err) {
      failedCount++;
      logger.error(`[AUTO-CONFIRM] order ${orderDoc.id} ผิดพลาด:`, err);
    }
  }

  logger.info(`[AUTO-CONFIRM] DONE: confirmed=${confirmedCount} failed=${failedCount}`);
});

exports.updateBuyerTotalSpent = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  if (before?.status === after?.status) return;
  if (after?.status !== 'delivered') return;

  const buyerId = after.buyerId;
  if (!buyerId) return;

  const foodTotal = Number(after.totalPrice ?? 0)
    - Number(after.shippingCharge ?? 0)
    - Number(after.shippingFee ?? 0);
  if (foodTotal <= 0) return;

  const monthKey = new Date().toISOString().slice(0, 7);
  const db = admin.firestore();

  await db.collection('buyers').doc(buyerId).update({
    totalSpent: admin.firestore.FieldValue.increment(foodTotal),
  });

  await db.collection('buyers').doc(buyerId)
      .collection('monthly_spending').doc(monthKey)
      .set({
        total: admin.firestore.FieldValue.increment(foodTotal),
        month: monthKey,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

  logger.info(`[BUYER-SPENT] buyerId=${buyerId} +${foodTotal} month=${monthKey}`);
});

exports.updateRiderMonthlyEarnings = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  if (before?.status === after?.status) return;
  if (after?.status !== 'delivered') return;

  const riderId = after.riderId;
  if (!riderId) return;

  const riderEarnings = Number(after.riderEarnings ?? 0);
  if (riderEarnings <= 0) return;

  const monthKey = new Date().toISOString().slice(0, 7);
  const monthRef = admin.firestore()
    .collection('riders').doc(riderId)
    .collection('monthly_earnings').doc(monthKey);

  await monthRef.set({
    total: admin.firestore.FieldValue.increment(riderEarnings),
    month: monthKey,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  logger.info(`[RIDER-EARNINGS] riderId=${riderId} +${riderEarnings} month=${monthKey}`);
});

exports.registerReferral = onCall(async (request) => {
  const { newUserId, referralCode, userType } = request.data;
  if (!newUserId || !referralCode) return { success: false, message: 'missing params' };

  const db = admin.firestore();

  // กำหนด collection ตาม userType
  const colMap = { customer: 'buyers', vendor: 'vendors', rider: 'riders' };
  const newUserCol = colMap[userType] ?? 'buyers';

  // หา referrer จาก referralCode — ค้นใน 3 collections
  let referrerDoc = null;
  let referrerCol = null;
  for (const col of ['buyers', 'vendors', 'riders']) {
    const snap = await db.collection(col)
        .where('referralCode', '==', referralCode)
        .limit(1)
        .get();
    if (!snap.empty) {
      referrerDoc = snap.docs[0];
      referrerCol = col;
      break;
    }
  }

  if (!referrerDoc) return { success: false, message: 'referral code not found' };

  const referrerId = referrerDoc.id;
  const referrerUplines = referrerDoc.data()?.uplineIds ?? [];
  const newUplineIds = [referrerId, ...referrerUplines].slice(0, 5);
  const newCode = await generateUniqueReferralCode();

  const batch = db.batch();

  // อัปเดต user ใหม่
  const newUserRef = db.collection(newUserCol).doc(newUserId);
  batch.set(newUserRef, {
    referralCode: newCode,
    referredBy: referrerId,
    uplineIds: newUplineIds,
    referralCount: 0,
    referralQualified: false,
  }, { merge: true });

  // เพิ่ม referralCount ให้ referrer
  const currentCount = referrerDoc.data()?.referralCount ?? 0;
  batch.update(referrerDoc.ref, {
    referralCount: admin.firestore.FieldValue.increment(1),
  });

  await batch.commit();

  logger.info(`[REFERRAL-REGISTER] newUser=${newUserId} col=${newUserCol} referrer=${referrerId} code=${newCode}`);
  return { success: true, referralCode: newCode, uplineIds: newUplineIds };
});

exports.generateReferralCodeForUser = onCall(async (request) => {
  const { userId, userType } = request.data;
  if (!userId) throw new HttpsError('invalid-argument', 'userId required');

  const db = admin.firestore();
  const colMap = { customer: 'buyers', vendor: 'vendors', rider: 'riders' };
  const col = colMap[userType ?? 'customer'] ?? 'buyers';

  const userRef = db.collection(col).doc(userId);
  const userDoc = await userRef.get();

  if (userDoc.exists && userDoc.data()?.referralCode) {
    return { referralCode: userDoc.data().referralCode };
  }

  const code = await generateUniqueReferralCode();
  await userRef.set({
    referralCode: code,
    referralCount: 0,
    referralQualified: false,
    uplineIds: [],
  }, { merge: true });

  logger.info(`[GEN-CODE] col=${col} userId=${userId} code=${code}`);
  return { referralCode: code };
});

exports.notifyAdminNewWithdrawal = onDocumentCreated({
  document: 'withdrawal_requests/{requestId}',
  region: 'asia-southeast1',
}, async (event) => {
  const data = event.data.data();
  if (!data) return;

  const requestId = event.params.requestId;
  const userId = data.userId;
  const amount = Number(data.amount ?? 0);
  const payoutInfo = data.payoutInfo || {};
  const fullName = payoutInfo.fullName || '-';
  const promptPay = payoutInfo.promptPayId || '';
  const bankName = payoutInfo.bankName || '';
  const bankAccount = payoutInfo.bankAccount || '';

  logger.info(`[WITHDRAWAL] new request: ${requestId} from ${userId} amount=${amount}`);

  const payoutMethod = promptPay
    ? `PromptPay: ${promptPay}`
    : `${bankName} ${bankAccount}`;

  const message = {
    notification: {
      title: '💰 คำขอถอนเงิน MLM ใหม่',
      body: `${fullName} ขอถอน ฿${amount.toFixed(2)} (${payoutMethod})`,
    },
    data: {
      type: 'withdrawal_request',
      requestId: requestId,
      userId: userId,
      amount: amount.toString(),
    },
    topic: 'admin_notifications',
  };

  try {
    await admin.messaging().send(message);
    logger.info(`[WITHDRAWAL] notification sent: ${requestId}`);
  } catch (err) {
    logger.error(`[WITHDRAWAL] notification failed:`, err);
  }

  try {
    await admin.firestore().collection('admin_notifications').add({
      type: 'withdrawal_request',
      title: 'คำขอถอนเงิน MLM ใหม่',
      message: `${fullName} ขอถอน ฿${amount.toFixed(2)}`,
      requestId: requestId,
      userId: userId,
      amount: amount,
      payoutMethod: payoutMethod,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    logger.error(`[WITHDRAWAL] log failed:`, err);
  }
});

// ─── BACKFILL FUNCTIONS ────────────────────────────────────────────────────────

const RECALC_SECRET = 'colae-recalc-rating-2026';

exports.recalculateVendorRatings = onRequest(
  { region: 'asia-southeast1', timeoutSeconds: 540, memory: '512MiB' },
  async (req, res) => {
    if (req.query.token !== RECALC_SECRET) {
      return res.status(401).send('Unauthorized');
    }

    const db = admin.firestore();
    const stats = { processed: 0, updated: 0, skipped: 0, errors: 0 };

    try {
      const vendorsSnap = await db.collection('vendors').get();
      stats.total_vendors = vendorsSnap.size;

      for (const vendorDoc of vendorsSnap.docs) {
        stats.processed++;
        const vendorId = vendorDoc.id;

        try {
          const reviewsSnap = await db
            .collection('product_reviews')
            .where('vendorId', '==', vendorId)
            .get();

          if (reviewsSnap.empty) {
            stats.skipped++;
            continue;
          }

          let totalAvg = 0;
          let totalTaste = 0;
          let totalCleanliness = 0;
          let totalService = 0;
          let totalSpeed = 0;
          const count = reviewsSnap.size;

          for (const reviewDoc of reviewsSnap.docs) {
            const data = reviewDoc.data();
            const ratings = data.ratings || {};
            totalAvg += (data.average || 0);
            totalTaste += (ratings.taste || 0);
            totalCleanliness += (ratings.cleanliness || 0);
            totalService += (ratings.service || 0);
            totalSpeed += (ratings.speed || 0);
          }

          await vendorDoc.ref.set({
            averageRating: parseFloat((totalAvg / count).toFixed(2)),
            ratingCount: count,
            tasteAvg: parseFloat((totalTaste / count).toFixed(2)),
            cleanlinessAvg: parseFloat((totalCleanliness / count).toFixed(2)),
            serviceAvg: parseFloat((totalService / count).toFixed(2)),
            speedAvg: parseFloat((totalSpeed / count).toFixed(2)),
            _ratingsRecalculatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });

          stats.updated++;
          logger.info(`[RECALC-VENDOR] ✅ ${vendorId} count=${count} avg=${(totalAvg / count).toFixed(2)}`);

        } catch (e) {
          logger.error(`[RECALC-VENDOR] ❌ vendor ${vendorId}:`, e);
          stats.errors++;
        }
      }

      return res.status(200).json({ success: true, message: 'Recalculation complete', stats });

    } catch (e) {
      logger.error('[RECALC-VENDOR] Fatal error:', e);
      return res.status(500).json({ success: false, error: e.message, stats });
    }
  }
);

exports.recalculateProductRatings = onRequest(
  { region: 'asia-southeast1', timeoutSeconds: 540, memory: '512MiB' },
  async (req, res) => {
    if (req.query.token !== RECALC_SECRET) {
      return res.status(401).send('Unauthorized');
    }

    const db = admin.firestore();
    const stats = { processed: 0, updated: 0, skipped: 0, errors: 0 };

    try {
      const reviewsSnap = await db.collection('product_reviews').get();
      const byProduct = {};

      for (const reviewDoc of reviewsSnap.docs) {
        const data = reviewDoc.data();
        const proId = data.proId;
        if (!proId) continue;
        if (!byProduct[proId]) byProduct[proId] = [];
        byProduct[proId].push(data);
      }

      stats.total_products_with_reviews = Object.keys(byProduct).length;

      for (const [proId, reviews] of Object.entries(byProduct)) {
        stats.processed++;
        try {
          let totalAvg = 0;
          for (const r of reviews) {
            totalAvg += (r.average || 0);
          }

          await db.collection('products').doc(proId).set({
            averageRating: parseFloat((totalAvg / reviews.length).toFixed(2)),
            ratingCount: reviews.length,
            _ratingsRecalculatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });

          stats.updated++;
        } catch (e) {
          logger.error(`[RECALC-PRODUCT] ❌ product ${proId}:`, e);
          stats.errors++;
        }
      }

      return res.status(200).json({ success: true, stats });

    } catch (e) {
      logger.error('[RECALC-PRODUCT] Fatal error:', e);
      return res.status(500).json({ success: false, error: e.message, stats });
    }
  }
);

exports.onWithdrawalCompleted = onDocumentUpdated({
  document: 'withdrawal_requests/{requestId}',
  region: 'asia-southeast1',
}, async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  if (!before || !after) return;
  if (before.status === after.status) return;
  if (after.status !== 'completed') return;

  const userId = after.userId;
  const amount = Number(after.amount ?? 0);

  if (!userId || amount <= 0) return;

  logger.info(`[WITHDRAWAL-COMPLETE] requestId=${event.params.requestId} userId=${userId} amount=${amount}`);

  const db = admin.firestore();

  // หา referral_transactions ที่ pending_payout ของ user นี้
  const txSnap = await db.collection('referral_transactions')
    .where('toUserId', '==', userId)
    .where('status', '==', 'pending_payout')
    .orderBy('timestamp', 'asc')
    .get();

  if (txSnap.empty) {
    logger.warn(`[WITHDRAWAL-COMPLETE] no pending transactions for ${userId}`);
    return;
  }

  const batch = db.batch();
  let deletedCount = 0;
  let deletedSum = 0;

  for (const doc of txSnap.docs) {
    const txAmount = Number(doc.data().amount ?? 0);
    batch.delete(doc.ref);
    deletedCount++;
    deletedSum += txAmount;
  }

  // update user totalWithdrawn (reuse getUserDoc helper)
  const userFound = await getUserDoc(userId);
  if (userFound) {
    batch.update(userFound.doc.ref, {
      totalWithdrawn: admin.firestore.FieldValue.increment(amount),
      lastWithdrawalAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  await batch.commit();

  logger.info(`[WITHDRAWAL-COMPLETE] ✅ deleted ${deletedCount} txs sum=${deletedSum.toFixed(2)} for ${userId}`);
});

// ─── Provider Management ───────────────────────────────────────────────────────

const bcrypt = require('bcryptjs');

exports.createProvider = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Login required');

    const { shopId, name, username, password, specialties, isSpecialistOnly, photo } = request.data;

    if (!shopId || !name || !username || !password) {
      throw new HttpsError('invalid-argument', 'Missing required fields');
    }
    if (password.length < 6) {
      throw new HttpsError('invalid-argument', 'Password must be at least 6 characters');
    }

    const db = admin.firestore();

    // ตรวจว่าเป็น owner
    const shopSnap = await db.collection('service_shops').doc(shopId).get();
    if (!shopSnap.exists) throw new HttpsError('not-found', 'Shop not found');
    if (shopSnap.data().ownerId !== uid) {
      throw new HttpsError('permission-denied', 'Not shop owner');
    }

    // ตรวจ username unique per shop
    const existingSnap = await db
      .collection('service_shops').doc(shopId)
      .collection('providers')
      .where('username', '==', username)
      .get();
    if (!existingSnap.empty) {
      throw new HttpsError('already-exists', 'Username already taken in this shop');
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);

    // Auto-order
    const providersSnap = await db
      .collection('service_shops').doc(shopId)
      .collection('providers')
      .orderBy('order', 'desc')
      .limit(1)
      .get();
    const nextOrder = providersSnap.empty ? 0 : (providersSnap.docs[0].data().order + 1);

    const providerData = {
      name,
      username,
      passwordHash,
      photo: photo || null,
      specialties: specialties || [],
      isSpecialistOnly: isSpecialistOnly || false,
      active: true,
      status: 'available',
      order: nextOrder,
      firebaseUid: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const docRef = await db
      .collection('service_shops').doc(shopId)
      .collection('providers')
      .add(providerData);

    logger.info(`[PROVIDER] created ${docRef.id} for shop ${shopId}`);
    return { providerId: docRef.id, success: true };
  }
);

exports.updateProviderPassword = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Login required');

    const { shopId, providerId, newPassword } = request.data;

    if (!shopId || !providerId || !newPassword) {
      throw new HttpsError('invalid-argument', 'Missing required fields');
    }
    if (newPassword.length < 6) {
      throw new HttpsError('invalid-argument', 'Password must be at least 6 characters');
    }

    const db = admin.firestore();

    // ตรวจว่าเป็น owner
    const shopSnap = await db.collection('service_shops').doc(shopId).get();
    if (!shopSnap.exists) throw new HttpsError('not-found', 'Shop not found');
    if (shopSnap.data().ownerId !== uid) {
      throw new HttpsError('permission-denied', 'Not shop owner');
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);

    await db
      .collection('service_shops').doc(shopId)
      .collection('providers').doc(providerId)
      .update({
        passwordHash,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    logger.info(`[PROVIDER] password updated for ${providerId}`);
    return { success: true };
  }
);

exports.deleteProvider = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Login required');

    const { shopId, providerId } = request.data;

    if (!shopId || !providerId) {
      throw new HttpsError('invalid-argument', 'Missing required fields');
    }

    const db = admin.firestore();

    // ตรวจว่าเป็น owner
    const shopSnap = await db.collection('service_shops').doc(shopId).get();
    if (!shopSnap.exists) throw new HttpsError('not-found', 'Shop not found');
    if (shopSnap.data().ownerId !== uid) {
      throw new HttpsError('permission-denied', 'Not shop owner');
    }

    // ตรวจว่ามี active bookings ไหม
    const activeBookings = await db.collection('service_bookings')
      .where('providerId', '==', providerId)
      .where('status', 'in', ['pending', 'confirmed', 'in_service'])
      .limit(1)
      .get();

    if (!activeBookings.empty) {
      throw new HttpsError(
        'failed-precondition',
        'ไม่สามารถลบพนักงานที่มีการจองที่ยังดำเนินการอยู่'
      );
    }

    await db
      .collection('service_shops').doc(shopId)
      .collection('providers').doc(providerId)
      .delete();

    logger.info(`[PROVIDER] deleted ${providerId} from shop ${shopId}`);
    return { success: true };
  }
);

// ─── PHASE 3: PROVIDER LOGIN ───────────────────────────────────────────────────

/**
 * Part A — ensureShopCode
 * Auto-generate a 6-digit numeric shopCode when a service_shops doc is created
 * or when it lacks the shopCode field.
 */
exports.ensureShopCode = onDocumentWritten(
  { document: 'service_shops/{shopId}', region: 'asia-southeast1' },
  async (event) => {
    const after = event.data?.after;
    if (!after || !after.exists) return; // doc deleted

    const data = after.data();
    if (data.shopCode) return; // already has code

    // Generate unique 6-digit code
    const db = admin.firestore();
    let code;
    let attempts = 0;
    do {
      code = String(Math.floor(100000 + Math.random() * 900000));
      const existing = await db.collection('service_shops')
        .where('shopCode', '==', code).limit(1).get();
      if (existing.empty) break;
      attempts++;
    } while (attempts < 10);

    await after.ref.update({ shopCode: code });
    logger.info(`[SHOP_CODE] assigned ${code} to shop ${event.params.shopId}`);
  }
);

/**
 * Part B — verifyProviderLogin
 * Verify shopCode + username + password, return Firebase custom token.
 */
exports.verifyProviderLogin = onCall(
  { region: 'asia-southeast1' },
  async (request) => {
    const { shopCode, username, password } = request.data;

    if (!shopCode || !username || !password) {
      throw new HttpsError('invalid-argument', 'ต้องระบุ shopCode, username, และ password');
    }

    const db = admin.firestore();

    // Find the shop by shopCode
    const shopSnap = await db.collection('service_shops')
      .where('shopCode', '==', shopCode.trim())
      .limit(1)
      .get();

    if (shopSnap.empty) {
      throw new HttpsError('not-found', 'ไม่พบร้านค้า — กรุณาตรวจสอบรหัสร้าน');
    }

    const shopDoc = shopSnap.docs[0];
    const shopId = shopDoc.id;

    // Find the provider by username within this shop
    const providerSnap = await db
      .collection('service_shops').doc(shopId)
      .collection('providers')
      .where('username', '==', username.trim().toLowerCase())
      .limit(1)
      .get();

    if (providerSnap.empty) {
      throw new HttpsError('not-found', 'ไม่พบชื่อผู้ใช้งาน');
    }

    const providerDoc = providerSnap.docs[0];
    const provider = providerDoc.data();

    if (!provider.isActive) {
      throw new HttpsError('permission-denied', 'บัญชีนี้ถูกระงับการใช้งาน');
    }

    // Verify password
    const bcrypt = require('bcryptjs');
    const match = await bcrypt.compare(password, provider.passwordHash);
    if (!match) {
      throw new HttpsError('unauthenticated', 'รหัสผ่านไม่ถูกต้อง');
    }

    // Create a custom token with provider claims
    const providerId = providerDoc.id;
    const uid = `provider_${shopId}_${providerId}`;

    const customToken = await admin.auth().createCustomToken(uid, {
      role: 'provider',
      shopId: shopId,
      providerId: providerId,
    });

    logger.info(`[PROVIDER_LOGIN] ${username} logged in shop ${shopId}`);

    return {
      customToken,
      providerId,
      shopId,
      providerName: provider.name,
      shopName: shopDoc.data().shopName ?? '',
    };
  }
);

// ─── Phase C: Auto-Assign Provider (Round-Robin Queue) ────────────────────────

/**
 * formatDateKey — returns 'YYYY-MM-DD' in Asia/Bangkok timezone.
 * Uses en-CA locale (ISO date format) with timezone option.
 */
function formatDateKey(date) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Bangkok',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

/**
 * assignProviderToBooking
 * Triggered on every new service_booking doc.
 * Skips if providerId is already set (customer/vendor manual choice).
 * Assigns an eligible, free provider via round-robin using queue_state per day.
 */
exports.assignProviderToBooking = onDocumentCreated(
  {
    document: 'service_bookings/{bookingId}',
    region: 'asia-southeast1',
  },
  async (event) => {
    const bookingId = event.params.bookingId;
    const booking = event.data?.data();
    if (!booking) return;

    // Skip if customer/vendor already chose a provider manually
    if (booking.providerId) {
      logger.info(`[ASSIGN] ${bookingId} — skip (manual: ${booking.providerId})`);
      return;
    }

    const shopId = booking.shopId;
    const typeId = booking.typeId;
    const bookingDate = booking.bookingDate?.toDate();
    const bookingEndAt = booking.bookingEndAt?.toDate();

    if (!shopId || !bookingDate || !bookingEndAt) {
      logger.warn(`[ASSIGN] ${bookingId} — missing required fields, skip`);
      return;
    }

    const db = admin.firestore();
    const FieldValue = admin.firestore.FieldValue;

    // 1. Load all active providers ordered by 'order' field
    const providersSnap = await db
      .collection('service_shops').doc(shopId)
      .collection('providers')
      .where('active', '==', true)
      .orderBy('order')
      .get();

    const providers = providersSnap.docs.map(d => ({ id: d.id, ...d.data() }));

    if (providers.length === 0) {
      logger.info(`[ASSIGN] ${bookingId} — no providers in shop ${shopId}, skip`);
      return;
    }

    // 2. Filter eligible (specialties empty = can do any service type)
    // typeId empty/null = service has no type restriction → all providers eligible
    const eligible = providers.filter(p => {
      const specs = p.specialties || [];
      if (specs.length === 0) return true;
      if (!typeId) return true;
      return specs.includes(typeId);
    });

    if (eligible.length === 0) {
      logger.warn(`[ASSIGN] ${bookingId} — no eligible provider for typeId=${typeId}`);
      await event.data.ref.update({
        assignmentError: 'no_eligible_provider',
        assignmentErrorAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    // 3. Get queue state for this day (Bangkok time)
    const dateKey = formatDateKey(bookingDate);
    const queueRef = db
      .collection('service_shops').doc(shopId)
      .collection('queue_state').doc(dateKey);

    const queueSnap = await queueRef.get();
    let lastIdx;
    if (queueSnap.exists) {
      lastIdx = queueSnap.data().lastAssignedIndex ?? -1;
    } else {
      // New day — seed from most recent previous queue_state so rotation continues
      const prevSnap = await db
        .collection('service_shops').doc(shopId)
        .collection('queue_state')
        .orderBy('date', 'desc')
        .limit(1)
        .get();
      if (!prevSnap.empty) {
        const prevData = prevSnap.docs[0].data();
        const prevProviderId = prevData.lastAssignedProviderId;
        if (prevProviderId) {
          // Resolve by ID to handle provider reordering between days
          const idx = providers.findIndex((p) => p.id === prevProviderId);
          lastIdx = idx !== -1 ? idx : (prevData.lastAssignedIndex ?? -1);
        } else {
          lastIdx = prevData.lastAssignedIndex ?? -1;
        }
      } else {
        lastIdx = -1; // First ever booking in this shop
      }
    }
    const startIdx = (lastIdx + 1) % providers.length;

    logger.info(
      `[ASSIGN] ${bookingId} dateKey=${dateKey} startIdx=${startIdx}` +
      ` eligible=${eligible.length}/${providers.length}`,
    );

    // 4. Round-robin: iterate full providers list from startIdx, wrap around
    for (let i = 0; i < providers.length; i++) {
      const idx = (startIdx + i) % providers.length;
      const provider = providers[idx];

      // Skip providers who can't do this service type
      if (!eligible.some(p => p.id === provider.id)) {
        logger.info(`[ASSIGN] idx=${idx} ${provider.name} — ineligible, skip`);
        continue;
      }

      // Check for time conflict: does this provider have an active booking
      // that overlaps with [bookingDate, bookingEndAt)?
      //
      // Firestore: bookingDate < bookingEndAt (their start < our end)
      // Memory:    bookingEndAt > bookingDate  (their end  > our start)
      // Together: full overlap detection.
      const conflictSnap = await db
        .collection('service_bookings')
        .where('shopId', '==', shopId)
        .where('providerId', '==', provider.id)
        .where('status', 'in', ['pending', 'confirmed', 'in_service'])
        .where('bookingDate', '<', admin.firestore.Timestamp.fromDate(bookingEndAt))
        .get();

      const hasConflict = conflictSnap.docs.some(d => {
        const bEnd = d.data().bookingEndAt?.toDate();
        return bEnd && bEnd > bookingDate;
      });

      if (hasConflict) {
        logger.info(`[ASSIGN] idx=${idx} ${provider.name} — busy, skip`);
        continue;
      }

      // Found a free eligible provider — assign!
      logger.info(`[ASSIGN] ${bookingId} → ${provider.name} (idx=${idx})`);

      await Promise.all([
        event.data.ref.update({
          providerId: provider.id,
          providerName: provider.name,
          assignedByQueue: true,
          assignedAt: FieldValue.serverTimestamp(),
        }),
        queueRef.set(
          {
            date: dateKey,
            lastAssignedIndex: idx,
            lastAssignedProviderId: provider.id,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        ),
      ]);

      return;
    }

    // 5. All eligible providers busy — flag for vendor attention
    logger.warn(`[ASSIGN] ${bookingId} — all_busy in shop ${shopId}`);
    await event.data.ref.update({
      assignmentError: 'all_busy',
      assignmentErrorAt: FieldValue.serverTimestamp(),
    });
  },
);