const express = require("express");
const { getMyAlumniProfile, upsertMyAlumniProfile, listAlumni } = require("../controllers/alumniController");
const { protect, authorize } = require("../middleware/authMiddleware");

const router = express.Router();

// Public browse (authenticated students can also browse)
router.use(protect);
router.get("/", listAlumni);

// Own profile
router.get("/me", authorize("student"), getMyAlumniProfile);
router.put("/me", authorize("student"), upsertMyAlumniProfile);

module.exports = router;
