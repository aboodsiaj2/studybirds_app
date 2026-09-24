const mongoose = require('mongoose');

const serviceOrderSchema = new mongoose.Schema({
  student: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  service: { type: mongoose.Schema.Types.ObjectId, ref: 'OurService', required: true },
  status: { type: String, enum: ['submitted', 'in-progress', 'awaiting-payment', 'completed', 'rejected', 'cancelled'], default: 'submitted', index: true },
  notes: { type: String, default: '', trim: true },
  staffNote: { type: String, default: '', trim: true },
  quotedPrice: { type: Number, min: 0, default: null },
  currency: { type: String, trim: true, default: '' },
  history: [{ status: String, changedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }, changedAt: { type: Date, default: Date.now } }],
}, { timestamps: true });

serviceOrderSchema.index({ student: 1, createdAt: -1 });
module.exports = mongoose.model('ServiceOrder', serviceOrderSchema);
