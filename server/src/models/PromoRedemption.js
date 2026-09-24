const mongoose = require("mongoose");

const promoRedemptionSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true },
    promoCode: { type: mongoose.Schema.Types.ObjectId, ref: "PromoCode", required: true },
    creditAmount: { type: Number, required: true, min: 0 },
  },
  { timestamps: true }
);

// One redemption per user per code — prevents double redemption at DB level.
promoRedemptionSchema.index({ user: 1, promoCode: 1 }, { unique: true });

module.exports = mongoose.model("PromoRedemption", promoRedemptionSchema);
