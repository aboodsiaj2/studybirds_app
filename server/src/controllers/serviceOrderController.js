const mongoose = require('mongoose');
const asyncHandler = require('../utils/asyncHandler');
const ServiceOrder = require('../models/ServiceOrder');
const OurService = require('../models/OurService');
const Notification = require('../models/Notification');

const STAFF_STATUSES = ['in-progress', 'awaiting-payment', 'completed', 'rejected', 'cancelled'];

const createOrder = asyncHandler(async (req, res) => {
  const { serviceId, notes = '' } = req.body;
  if (!mongoose.isValidObjectId(serviceId) || typeof notes !== 'string' || notes.length > 2000) {
    return res.status(400).json({ message: 'Invalid service order' });
  }
  const service = await OurService.findById(serviceId).lean();
  if (!service) return res.status(404).json({ message: 'Service not found' });
  const existing = await ServiceOrder.exists({ student: req.user._id, service: serviceId, status: { $in: ['submitted', 'in-progress', 'awaiting-payment'] } });
  if (existing) return res.status(409).json({ message: 'You already have an active request for this service' });
  const order = await ServiceOrder.create({ student: req.user._id, service: serviceId, notes: notes.trim(), history: [{ status: 'submitted', changedBy: req.user._id }] });
  res.status(201).json(await ServiceOrder.findById(order._id).populate('service', 'title slug detailTitle').lean());
});

const getMine = asyncHandler(async (req, res) => {
  res.json(await ServiceOrder.find({ student: req.user._id }).populate('service', 'title slug detailTitle').sort({ createdAt: -1 }).lean());
});

const cancelMine = asyncHandler(async (req, res) => {
  const { version } = req.body;
  if (!mongoose.isValidObjectId(req.params.id) || !Number.isInteger(version) || version < 0) return res.status(400).json({ message: 'Invalid request' });
  const order = await ServiceOrder.findOneAndUpdate({ _id: req.params.id, student: req.user._id, __v: version, status: { $in: ['submitted', 'in-progress', 'awaiting-payment'] } }, { $set: { status: 'cancelled' }, $inc: { __v: 1 }, $push: { history: { status: 'cancelled', changedBy: req.user._id } } }, { new: true }).lean();
  if (!order) return res.status(409).json({ message: 'Service order changed. Refresh and retry.' });
  res.json(order);
});

const listAdmin = asyncHandler(async (_req, res) => {
  res.json(await ServiceOrder.find().populate('student', 'name email').populate('service', 'title slug').sort({ createdAt: -1 }).limit(500).lean());
});

const updateAdmin = asyncHandler(async (req, res) => {
  const { status, staffNote = '', quotedPrice = null, currency = '', version } = req.body;
  if (!mongoose.isValidObjectId(req.params.id) || !STAFF_STATUSES.includes(status) || !Number.isInteger(version) || version < 0 || typeof staffNote !== 'string' || staffNote.length > 2000 || (quotedPrice !== null && (typeof quotedPrice !== 'number' || quotedPrice < 0)) || typeof currency !== 'string' || currency.length > 10) return res.status(400).json({ message: 'Invalid service order update' });
  const order = await ServiceOrder.findOneAndUpdate({ _id: req.params.id, __v: version, status: { $nin: ['completed', 'rejected', 'cancelled'] } }, { $set: { status, staffNote: staffNote.trim(), quotedPrice, currency: currency.trim() }, $inc: { __v: 1 }, $push: { history: { status, changedBy: req.user._id } } }, { new: true }).populate('student', 'name email').populate('service', 'title slug').lean();
  if (!order) return res.status(409).json({ message: 'Service order changed. Refresh and retry.' });
  await Notification.create({ user: order.student._id, title: 'Service request updated', message: `Your service request is now ${status}.`, type: 'info', link: '/student/service-orders' });
  res.json(order);
});

module.exports = { createOrder, getMine, cancelMine, listAdmin, updateAdmin };
