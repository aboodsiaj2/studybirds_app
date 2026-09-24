const express = require("express");
const {
  getProfile,
  updateProfile,
  uploadDocument,
  getDocuments,
  getApplications,
  getDashboardOverview,
  getAgencyRequest,
  createAgencyRequest,
  getStudentNotifications,
  markStudentNotificationAsRead,
  getStudentSupportTickets,
  createStudentSupportTicket,
  getStudentKnowledgeBase,
  getStudentFinancials,
  uploadPaymentProof,
  getArrivalServiceRequest,
  upsertArrivalServiceRequest,
  getStudentFavorites,
  toggleStudentFavorite,
  removeStudentFavorite,
  getOrientationTestResult,
  submitOrientationTest,
} = require("../controllers/studentController");
const { getMyWallet, redeemWalletCredit } = require("../controllers/studentWalletController");
const {
  createServiceRequest, getMyServiceRequests, getMyServiceRequest,
  cancelMyServiceRequest, respondToServiceRequest,
} = require("../controllers/serviceRequestController");
const { protect, authorize } = require("../middleware/authMiddleware");
const upload = require("../middleware/uploadMiddleware");

const router = express.Router();

router.use(protect);
router.get("/profile", getProfile);
router.put("/profile", authorize("student", "partner"), updateProfile);
router.use(authorize("student"));
router.get("/agency-request", getAgencyRequest);
router.post("/agency-request", createAgencyRequest);
router.get("/overview", getDashboardOverview);
router.post("/documents", upload.single("file"), uploadDocument);
router.get("/documents", getDocuments);
router.get("/applications", getApplications);
router.get("/notifications", getStudentNotifications);
router.patch("/notifications/:id/read", markStudentNotificationAsRead);
router.get("/support-tickets", getStudentSupportTickets);
router.post("/support-tickets", upload.single("file"), createStudentSupportTicket);
router.get("/knowledge-base", getStudentKnowledgeBase);
router.get("/financials", getStudentFinancials);
router.post("/financials/invoices/:id/payment-proof", upload.single("file"), uploadPaymentProof);
router.get("/arrival-services", getArrivalServiceRequest);
router.put("/arrival-services", upsertArrivalServiceRequest);
router.get("/favorites", getStudentFavorites);
router.post("/favorites/toggle", toggleStudentFavorite);
router.delete("/favorites/:id", removeStudentFavorite);
router.get("/orientation-test", getOrientationTestResult);
router.post("/orientation-test", submitOrientationTest);
router.get("/wallet", getMyWallet);
router.post("/wallet/redeem", redeemWalletCredit);
router.get("/service-requests", getMyServiceRequests);
router.post("/service-requests", createServiceRequest);
router.get("/service-requests/:id", getMyServiceRequest);
router.post("/service-requests/:id/cancel", cancelMyServiceRequest);
router.post("/service-requests/:id/respond", respondToServiceRequest);

module.exports = router;
