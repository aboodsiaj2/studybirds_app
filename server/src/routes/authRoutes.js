const express = require("express");
const {
  register,
  login,
  googleLogin,
  me,
  changePassword,
  deleteAccount,
} = require("../controllers/authController");
const { protect } = require("../middleware/authMiddleware");

const router = express.Router();

router.post("/register", register);
router.post("/login", login);
router.post("/google", googleLogin);
router.get("/me", protect, me);
router.post("/change-password", protect, changePassword);
router.delete("/account", protect, deleteAccount);

module.exports = router;
