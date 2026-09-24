const asyncHandler = require("../utils/asyncHandler");
const { atomicOperation, fail } = require("../utils/atomicOperation");
const PromoCode = require("../models/PromoCode");
const PromoRedemption = require("../models/PromoRedemption");
const StudentWalletEntry = require("../models/StudentWalletEntry");

// ---- Student: redeem a promo code ----------------------------------------

const redeemPromoCode = asyncHandler(async (req, res) => {
  const { code } = req.body;
  if (!code || typeof code !== "string" || code.trim().length === 0 || code.length > 50) {
    return res.status(400).json({ message: "Code required" });
  }
  const result = await atomicOperation(res, async (session) => {
    const promo = await PromoCode.findOne({
      code: code.toUpperCase().trim(),
      isActive: true,
    }).session(session).lean();
    if (!promo) fail(404, "الرمز غير موجود أو غير نشط");
    if (promo.expiresAt && new Date(promo.expiresAt) < new Date()) {
      fail(409, "انتهت صلاحية هذا الرمز");
    }
    if (promo.maxUsesTotal !== null && promo.usedCount >= promo.maxUsesTotal) {
      fail(409, "الرمز استُنفد بالكامل");
    }
    const userUses = await PromoRedemption.countDocuments({
      user: req.user._id,
      promoCode: promo._id,
    }).session(session);
    if (userUses >= (promo.maxUsesPerUser ?? 1)) {
      fail(409, "لقد استخدمت هذا الرمز مسبقاً");
    }
    try {
      await PromoRedemption.create(
        [{ user: req.user._id, promoCode: promo._id, creditAmount: promo.creditAmount }],
        { session }
      );
    } catch (e) {
      if (e.code === 11000) fail(409, "لقد استخدمت هذا الرمز مسبقاً");
      throw e;
    }
    await PromoCode.updateOne({ _id: promo._id }, { $inc: { usedCount: 1 } }, { session });
    await StudentWalletEntry.create(
      [{
        student: req.user._id,
        direction: "credit",
        kind: "promo-credit",
        amount: promo.creditAmount,
        notes: `Promo code: ${promo.code}`,
      }],
      { session }
    );
    return { creditAmount: promo.creditAmount, description: promo.description, code: promo.code };
  });
  res.json(result);
});

// ---- Student: my redemption history -------------------------------------

const getMyRedemptions = asyncHandler(async (req, res) => {
  const redemptions = await PromoRedemption.find({ user: req.user._id })
    .populate("promoCode", "code description creditAmount")
    .sort({ createdAt: -1 })
    .lean();
  res.json(redemptions);
});

// ---- Admin: promo code management ----------------------------------------

const getPromoCodesAdmin = asyncHandler(async (req, res) => {
  const codes = await PromoCode.find().sort({ createdAt: -1 }).lean();
  res.json(codes);
});

const createPromoCode = asyncHandler(async (req, res) => {
  const { code, description = "", creditAmount, maxUsesTotal = null, maxUsesPerUser = 1, expiresAt = null } = req.body;
  if (!code || typeof code !== "string" || code.trim().length === 0) {
    return res.status(400).json({ message: "Code required" });
  }
  if (typeof creditAmount !== "number" || creditAmount < 0) {
    return res.status(400).json({ message: "creditAmount must be a non-negative number" });
  }
  const created = await PromoCode.create({
    code: code.toUpperCase().trim(),
    description: description.trim(),
    creditAmount,
    maxUsesTotal: maxUsesTotal ?? null,
    maxUsesPerUser: maxUsesPerUser ?? 1,
    expiresAt: expiresAt ? new Date(expiresAt) : null,
    createdBy: req.user._id,
  });
  res.status(201).json(created);
});

const updatePromoCode = asyncHandler(async (req, res) => {
  const { isActive, description, expiresAt, maxUsesTotal } = req.body;
  const patch = {};
  if (typeof isActive === "boolean") patch.isActive = isActive;
  if (typeof description === "string") patch.description = description.trim();
  if (expiresAt !== undefined) patch.expiresAt = expiresAt ? new Date(expiresAt) : null;
  if (maxUsesTotal !== undefined) patch.maxUsesTotal = maxUsesTotal ?? null;
  const updated = await PromoCode.findByIdAndUpdate(req.params.id, { $set: patch }, { new: true }).lean();
  if (!updated) return res.status(404).json({ message: "Not found" });
  res.json(updated);
});

module.exports = { redeemPromoCode, getMyRedemptions, getPromoCodesAdmin, createPromoCode, updatePromoCode };
