const mongoose = require("mongoose");
const { SERVICE_REQUEST_STATUSES } = require("../constants/serviceCatalog");

const historySchema = new mongoose.Schema(
  {
    status: { type: String, enum: SERVICE_REQUEST_STATUSES, required: true },
    note: { type: String, default: "" },
    changedBy: { type: mongoose.Schema.Types.ObjectId, ref: "User" },
    changedAt: { type: Date, default: Date.now },
  },
  { _id: false }
);

// A student's request for a published service (PRD 35–36). The service's
// title and price are copied at request time so later catalog edits don't
// rewrite what the student asked for.
const serviceRequestSchema = new mongoose.Schema(
  {
    student: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true, index: true },
    service: { type: mongoose.Schema.Types.ObjectId, ref: "OurService", required: true },
    serviceSnapshot: {
      title: { type: String, required: true },
      slug: String,
      category: String,
      price: { type: Number, default: null },
      currency: { type: String, default: "USD" },
    },
    notes: { type: String, default: "" },
    status: { type: String, enum: SERVICE_REQUEST_STATUSES, default: "submitted", index: true },
    // Why the request needs action, was declined or was cancelled.
    reason: { type: String, default: "" },
    staffNote: { type: String, default: "" },
    studentReply: { type: String, default: "" },
    assignedTo: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null, index: true },
    invoice: { type: mongoose.Schema.Types.ObjectId, ref: "Invoice", default: null },
    // "<student>:<service>" while the request is open, removed once it ends:
    // the partial unique index allows one open request per service.
    activeKey: { type: String },
    history: { type: [historySchema], default: [] },
  },
  { timestamps: true }
);

serviceRequestSchema.index({ activeKey: 1 }, { unique: true, partialFilterExpression: { activeKey: { $type: "string" } } });
serviceRequestSchema.index({ status: 1, updatedAt: -1 });

module.exports = mongoose.model("ServiceRequest", serviceRequestSchema);
