const mongoose = require("mongoose");
const asyncHandler = require("../utils/asyncHandler");
const StudentReferral = require("../models/StudentReferral");
const StudentWalletEntry = require("../models/StudentWalletEntry");
const Invoice = require("../models/Invoice");
const User = require("../models/User");
const { atomicOperation, fail } = require("../utils/atomicOperation");
const { ensureReferralCode, getWalletBalance } = require("../utils/studentWallet");

// ---- Student: their own wallet ------------------------------------------

const getMyWallet = asyncHandler(async (req, res) => {
  const [referralCode, balance, referrals, transactions] = await Promise.all([
    ensureReferralCode(req.user._id),
    getWalletBalance(req.user._id),
    StudentReferral.find({ referrer: req.user._id }).populate("referredUser", "name").sort({ createdAt: -1 }).lean(),
    StudentWalletEntry.find({ student: req.user._id }).sort({ createdAt: -1 }).limit(100).lean(),
  ]);
  res.json({
    referralCode, balance,
    referrals: referrals.map((r) => ({ _id: r._id, name: r.referredUser?.name || "طالب", status: r.status, createdAt: r.createdAt, qualifiedAt: r.qualifiedAt })),
    transactions,
  });
});

const redeemWalletCredit = asyncHandler(async (req, res) => {
  const { invoiceId, amount } = req.body;
  if (!mongoose.isValidObjectId(invoiceId) || typeof amount !== "number" || !Number.isFinite(amount) || amount <= 0) {
    return res.status(400).json({ message: "Invalid redemption request" });
  }
  const result = await atomicOperation(res, async session => {
  // All debits write the same student first. Mongo retries competing transactions
  // with a fresh snapshot before they may read and spend the balance.
  const owner = await User.updateOne({ _id: req.user._id }, { $inc: { walletRevision: 1 } }, { session });
  if (!owner.matchedCount) fail(404, "Student not found");
  const invoice = await Invoice.findOne({ _id: invoiceId, student: req.user._id }).session(session);
  if (!invoice) fail(404, "Invoice not found");
  if (invoice.status !== "unpaid") fail(409, "This invoice can no longer accept credit");
  const remaining = invoice.amount - invoice.walletCreditApplied;
  if (amount > remaining) fail(400, "Amount exceeds what is still owed on this invoice");
  const balance = await getWalletBalance(req.user._id, session);
  if (amount > balance) fail(409, "Insufficient wallet balance");

  const updated = await Invoice.findOneAndUpdate(
    { _id: invoice._id, status: "unpaid", walletCreditApplied: invoice.walletCreditApplied },
    { $inc: { walletCreditApplied: amount }, $set: amount >= remaining ? { status: "paid", reviewedAt: new Date() } : {} },
    { new: true, session }
  );
  if (!updated) fail(409, "Invoice changed. Refresh and retry.");
  await StudentWalletEntry.create([{ student: req.user._id, direction: "debit", kind: "redemption", amount, relatedInvoice: invoice._id, notes: `سداد جزئي/كامل لفاتورة ${invoice.invoiceNumber}` }], { session });
  return { invoice: updated, balance: await getWalletBalance(req.user._id, session) };
  });
  res.json(result);
});

// ---- Staff: manual adjustments (mounted under /admin/student-financials,
// gated by the existing 'student-financials' section) --------------------

const getWalletEntriesAdmin = asyncHandler(async (req, res) => {
  const query = {};
  if (req.query.student && mongoose.isValidObjectId(req.query.student)) query.student = req.query.student;
  const entries = await StudentWalletEntry.find(query).populate("student", "name email").populate("createdBy", "name").sort({ createdAt: -1 }).limit(300).lean();
  res.json(entries);
});

const createWalletAdjustmentAdmin = asyncHandler(async (req, res) => {
  const { studentId, direction, amount, notes = "" } = req.body;
  if (!mongoose.isValidObjectId(studentId) || !["credit", "debit"].includes(direction)
    || typeof amount !== "number" || !Number.isFinite(amount) || amount <= 0
    || typeof notes !== "string" || !notes.trim() || notes.length > 500) {
    return res.status(400).json({ message: "Invalid wallet adjustment" });
  }
  const entry = await atomicOperation(res, async session => {
    const owner = await User.updateOne({ _id: studentId, role: 'student' }, { $inc: { walletRevision: 1 } }, { session });
    if (!owner.matchedCount) fail(404, "Student not found");
    if (direction === "debit" && amount > (await getWalletBalance(studentId, session))) {
      fail(409, "Adjustment would leave a negative balance");
    }
    const [created] = await StudentWalletEntry.create([{ student: studentId, direction, kind: "adjustment", amount, notes: notes.trim(), createdBy: req.user._id }], { session });
    return created;
  });
  res.status(201).json(entry);
});

module.exports = { getMyWallet, redeemWalletCredit, getWalletEntriesAdmin, createWalletAdjustmentAdmin };
