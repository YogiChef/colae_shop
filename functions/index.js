const { onCall, HttpsError } = require("firebase-functions/v2/https");
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
        vendorBuyerSnap.docs.forEach(doc => batch.delete(doc.ref));

        const riderBuyerSnap = await db.collection('chats')
            .where('orderId', '==', orderId)
            .get();
        riderBuyerSnap.docs.forEach(doc => batch.delete(doc.ref));

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

  // เงื่อนไข 2: ตามประเภท user
  const now = new Date();
  const monthKey = now.toISOString().slice(0, 7);

  if (userType === 'vendor') {
    return (data.totalSales ?? 0) >= 5000;
  }

  if (userType === 'rider') {
    const monthDoc = await db.collection('riders').doc(userId)
        .collection('monthly_earnings').doc(monthKey).get();
    return (monthDoc.data()?.total ?? 0) >= 15000;
  }

  if (userType === 'customer') {
    return (data.totalSpent ?? 0) >= 5000;
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

exports.processReferralCommission = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  if (before?.status === after?.status) return;
  if (after?.status !== 'delivered') return;

  const db = admin.firestore();
  const orderId = event.params.orderId;
  const buyerId = after.buyerId;
  if (!buyerId) return;

  const shippingCharge = Number(after.shippingCharge ?? 0);
  const totalPrice = Number(after.totalPrice ?? 0);
  const foodTotal = totalPrice - shippingCharge;
  if (foodTotal <= 0) return;

  const pool = parseFloat((foodTotal * 0.05).toFixed(2));
  const rates = [0.20, 0.10, 0.05, 0.03, 0.02];

  const buyerFound = await getUserDoc(buyerId);
  if (!buyerFound) return;
  const uplineIds = buyerFound.doc.data()?.uplineIds ?? [];
  if (uplineIds.length === 0) return;

  const batch = db.batch();
  const month = new Date().toISOString().slice(0, 7);

  for (let i = 0; i < Math.min(uplineIds.length, 5); i++) {
    const uplineId = uplineIds[i];
    const commission = parseFloat((pool * rates[i]).toFixed(2));
    const level = i + 1;

    const qualified = await checkQualified(uplineId);
    const toId = qualified ? uplineId : 'platform';

    const earningsRef = db.collection('referral_earnings').doc(toId);
    batch.set(earningsRef, {
      pendingEarnings: admin.firestore.FieldValue.increment(commission),
      totalEarnings: admin.firestore.FieldValue.increment(commission),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    const txRef = db.collection('referral_transactions').doc();
    batch.set(txRef, {
      fromBuyerId: buyerId,
      toUserId: toId,
      originalUplineId: uplineId,
      qualified: qualified,
      orderId: orderId,
      level: level,
      foodTotal: foodTotal,
      pool: pool,
      commissionRate: rates[i],
      amount: commission,
      month: month,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  const totalDistributed = parseFloat(
    rates.slice(0, uplineIds.length)
      .reduce((sum, r) => sum + pool * r, 0)
      .toFixed(2)
  );
  const platformShare = parseFloat((pool - totalDistributed).toFixed(2));
  if (platformShare > 0) {
    const platformRef = db.collection('referral_earnings').doc('platform');
    batch.set(platformRef, {
      pendingEarnings: admin.firestore.FieldValue.increment(platformShare),
      totalEarnings: admin.firestore.FieldValue.increment(platformShare),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  await batch.commit();
  logger.info(`[REFERRAL] ✅ orderId=${orderId} pool=${pool} uplines=${uplineIds.length}`);
});

exports.updateBuyerTotalSpent = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  if (before?.status === after?.status) return;
  if (after?.status !== 'delivered') return;

  const buyerId = after.buyerId;
  if (!buyerId) return;

  const foodTotal = Number(after.totalPrice ?? 0) - Number(after.shippingCharge ?? 0);
  if (foodTotal <= 0) return;

  await admin.firestore().collection('buyers').doc(buyerId).update({
    totalSpent: admin.firestore.FieldValue.increment(foodTotal),
  });

  logger.info(`[BUYER-SPENT] buyerId=${buyerId} +${foodTotal}`);
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
    ...(currentCount + 1 >= 12 ? { referralQualified: true } : {}),
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