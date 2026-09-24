const router = require('express').Router();
const { protect, authorize } = require('../middleware/authMiddleware');
const { createOrder, getMine, cancelMine } = require('../controllers/serviceOrderController');
router.use(protect, authorize('student'));
router.get('/mine', getMine);
router.post('/', createOrder);
router.post('/:id/cancel', cancelMine);
module.exports = router;
