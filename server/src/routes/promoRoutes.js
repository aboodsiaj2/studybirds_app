const express = require("express");
const { redeemPromoCode, getMyRedemptions } = require("../controllers/promoController");
const { protect, authorize } = require("../middleware/authMiddleware");

const router = express.Router();

router.use(protect, authorize("student"));
router.post("/redeem", redeemPromoCode);
router.get("/my-redemptions", getMyRedemptions);

module.exports = router;
