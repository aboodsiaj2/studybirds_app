const mongoose = require("mongoose");
const asyncHandler = require("../utils/asyncHandler");
const OurService = require("../models/OurService");
const ServiceRequest = require("../models/ServiceRequest");
const Invoice = require("../models/Invoice");
const User = require("../models/User");
const Notification = require("../models/Notification");
const { atomicOperation, fail } = require("../utils/atomicOperation");
const { hasSection } = require("../middleware/employeeAccess");
const { serviceRequestStatusInfo, serviceRequestStatusNotice } = require("../constants/statusCatalog");
const {
  SERVICE_REQUEST_STATUSES, STAFF_TRANSITIONS, STATUSES_REQUIRING_REASON, STUDENT_CANCELLABLE,
} = require("../constants/serviceCatalog");

const SECTION = "service-requests";
const INVOICE_FIELDS = "invoiceNumber description amount status walletCreditApplied dueDate";
const isTerminal = (status) => STAFF_TRANSITIONS[status]?.length === 0;
// An invoice can be voided with its request only while nothing was paid on it.
const invoiceVoidable = (invoice) => !invoice || (invoice.status === "unpaid" && !(invoice.walletCreditApplied > 0));

// Why a staff move is not allowed right now, or null when it is. The same
// rules produce `allowedStatuses`, so clients only offer moves that succeed.
function moveProblem(request, invoice, status) {
  if (!(STAFF_TRANSITIONS[request.status] || []).includes(status)) {
    return `This request can't move from ${request.status} to ${status}`;
  }
  if (status === "awaiting-payment" && invoice) return "An invoice was already issued for this request";
  if (status === "in-progress") {
    if (invoice && invoice.status !== "paid") return "The service invoice must be paid before work starts";
    if (!invoice && request.serviceSnapshot?.price > 0) return "Issue the service invoice before starting paid work";
  }
  if (["cancelled", "rejected"].includes(status) && !invoiceVoidable(invoice)) {
    return "The invoice already has payments. Settle it in Student Financials first.";
  }
  return null;
}

const allowedStatuses = (request) => (STAFF_TRANSITIONS[request.status] || [])
  .filter((status) => !moveProblem(request, request.invoice, status));

function serialize(request, { staff = false } = {}) {
  const invoice = request.invoice && request.invoice.invoiceNumber ? {
    _id: request.invoice._id, invoiceNumber: request.invoice.invoiceNumber, description: request.invoice.description,
    amount: request.invoice.amount, status: request.invoice.status,
    walletCreditApplied: request.invoice.walletCreditApplied || 0, dueDate: request.invoice.dueDate || null,
  } : null;
  const row = {
    _id: request._id,
    __v: request.__v,
    service: { _id: request.service?._id || request.service, ...request.serviceSnapshot },
    notes: request.notes,
    status: request.status,
    statusInfo: serviceRequestStatusInfo(request),
    reason: request.reason || "",
    staffNote: request.staffNote || "",
    studentReply: request.studentReply || "",
    assignedTo: request.assignedTo?.name ? { _id: request.assignedTo._id, name: request.assignedTo.name } : null,
    invoice,
    history: (request.history || []).map(({ status, note, changedAt }) => ({ status, note, changedAt })),
    createdAt: request.createdAt,
    updatedAt: request.updatedAt,
  };
  if (staff) {
    row.student = request.student?.name ? { _id: request.student._id, name: request.student.name, email: request.student.email } : null;
    row.allowedStatuses = allowedStatuses(request);
  } else {
    row.canCancel = STUDENT_CANCELLABLE.includes(request.status) && invoiceVoidable(invoice);
    row.canRespond = request.status === "action-required";
  }
  return row;
}

const populated = (query) => query
  .populate("assignedTo", "name")
  .populate("invoice", INVOICE_FIELDS)
  .lean();

async function loadForStaff(id) {
  return populated(ServiceRequest.findById(id).populate("student", "name email"));
}

// Best-effort: the change is committed; a failed notice must not turn it into an error.
async function notify(user, notice) {
  if (!user) return;
  try {
    await Notification.create({ user, ...notice });
  } catch (error) {
    console.error("[service-requests] notification failed", error.message);
  }
}

async function voidInvoice(invoice, byUser, note, session) {
  if (!invoice) return;
  const voided = await Invoice.findOneAndUpdate(
    { _id: invoice._id, status: "unpaid", walletCreditApplied: invoice.walletCreditApplied || 0 },
    { $set: { status: "rejected", adminNote: note, reviewedAt: new Date(), reviewedBy: byUser } },
    { new: true, session }
  );
  if (!voided || voided.walletCreditApplied > 0) {
    fail(409, "The invoice already has payments. Settle it in Student Financials first.");
  }
}

const validText = (value, max = 2000) => value === undefined || (typeof value === "string" && value.length <= max);
const validVersion = (version) => Number.isInteger(version) && version >= 0;

// ---- Student --------------------------------------------------------------

const createServiceRequest = asyncHandler(async (req, res) => {
  const { serviceId, notes = "" } = req.body;
  if (!mongoose.isValidObjectId(serviceId) || !validText(notes)) {
    return res.status(400).json({ message: "Invalid service request" });
  }
  const service = await OurService.findById(serviceId).lean();
  if (!service) return res.status(404).json({ message: "Service not found" });
  if (service.requestable === false) return res.status(409).json({ message: "This service can't be requested online" });

  // New requests go to the service's responsible staff member while they still have access.
  const owner = service.owner ? await User.findById(service.owner).select("role permissions").lean() : null;
  const assignedTo = owner && hasSection(owner, SECTION) ? owner._id : null;

  let created;
  try {
    created = await ServiceRequest.create({
      student: req.user._id,
      service: service._id,
      serviceSnapshot: {
        title: service.title, slug: service.slug, category: service.category || "other",
        price: typeof service.price === "number" ? service.price : null, currency: service.currency || "USD",
      },
      notes: notes.trim(),
      assignedTo,
      activeKey: `${req.user._id}:${service._id}`,
      history: [{ status: "submitted", note: notes.trim(), changedBy: req.user._id }],
    });
  } catch (error) {
    if (error.code === 11000) return res.status(409).json({ message: "You already have an open request for this service." });
    throw error;
  }
  await notify(assignedTo, {
    title: `طلب خدمة جديد: ${service.title}`,
    message: `${req.user.name || "طالب"} طلب هذه الخدمة وتم إسنادها إليك.`,
    type: "info", link: "/admin/service-requests",
  });
  res.status(201).json(serialize(await populated(ServiceRequest.findById(created._id))));
});

const getMyServiceRequests = asyncHandler(async (req, res) => {
  const rows = await populated(ServiceRequest.find({ student: req.user._id }).sort({ createdAt: -1 }).limit(200));
  res.json(rows.map((row) => serialize(row)));
});

const getMyServiceRequest = asyncHandler(async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return res.status(404).json({ message: "Request not found" });
  const row = await populated(ServiceRequest.findOne({ _id: req.params.id, student: req.user._id }));
  if (!row) return res.status(404).json({ message: "Request not found" });
  res.json(serialize(row));
});

const cancelMyServiceRequest = asyncHandler(async (req, res) => {
  const { version } = req.body;
  if (!mongoose.isValidObjectId(req.params.id) || !validVersion(version)) {
    return res.status(400).json({ message: "Invalid request" });
  }
  const id = await atomicOperation(res, async (session) => {
    const request = await ServiceRequest.findOne({ _id: req.params.id, student: req.user._id }).session(session).lean();
    if (!request) fail(404, "Request not found");
    if (request.__v !== version) fail(409, "Request changed. Refresh and retry.");
    if (!STUDENT_CANCELLABLE.includes(request.status)) fail(409, "This request can no longer be cancelled");
    const invoice = request.invoice ? await Invoice.findById(request.invoice).session(session).lean() : null;
    if (!invoiceVoidable(invoice)) fail(409, "This request has a payment on its invoice. Contact the team to cancel it.");
    await voidInvoice(invoice, req.user._id, "Voided: the student cancelled the service request", session);
    const updated = await ServiceRequest.findOneAndUpdate(
      { _id: request._id, __v: version, status: request.status },
      {
        $set: { status: "cancelled", reason: "" }, $unset: { activeKey: 1 }, $inc: { __v: 1 },
        $push: { history: { status: "cancelled", note: "Cancelled by the student", changedBy: req.user._id, changedAt: new Date() } },
      },
      { new: true, session }
    );
    if (!updated) fail(409, "Request changed. Refresh and retry.");
    return updated._id;
  });
  const row = await populated(ServiceRequest.findById(id));
  await notify(row.assignedTo?._id, {
    title: `أُلغي طلب خدمة: ${row.serviceSnapshot.title}`, message: "ألغى الطالب هذا الطلب.",
    type: "info", link: "/admin/service-requests",
  });
  res.json(serialize(row));
});

const respondToServiceRequest = asyncHandler(async (req, res) => {
  const { version, reply } = req.body;
  if (!mongoose.isValidObjectId(req.params.id) || !validVersion(version)
    || typeof reply !== "string" || !reply.trim() || reply.length > 2000) {
    return res.status(400).json({ message: "Write your reply before sending" });
  }
  const updated = await ServiceRequest.findOneAndUpdate(
    { _id: req.params.id, student: req.user._id, __v: version, status: "action-required" },
    {
      $set: { status: "under-review", studentReply: reply.trim() }, $inc: { __v: 1 },
      $push: { history: { status: "under-review", note: reply.trim(), changedBy: req.user._id, changedAt: new Date() } },
    },
    { new: true }
  );
  if (!updated) {
    const exists = await ServiceRequest.exists({ _id: req.params.id, student: req.user._id });
    return res.status(exists ? 409 : 404).json({ message: exists ? "Request changed. Refresh and retry." : "Request not found" });
  }
  const row = await populated(ServiceRequest.findById(updated._id));
  await notify(row.assignedTo?._id, {
    title: `رد الطالب على طلب: ${row.serviceSnapshot.title}`, message: reply.trim().slice(0, 300),
    type: "info", link: "/admin/service-requests",
  });
  res.json(serialize(row));
});

// ---- Staff (mounted under /admin, gated by the 'service-requests' section) --

const getServiceRequestsAdmin = asyncHandler(async (req, res) => {
  const query = {};
  if (SERVICE_REQUEST_STATUSES.includes(req.query.status)) query.status = req.query.status;
  if (req.query.assigned === "me") query.assignedTo = req.user._id;
  if (req.query.assigned === "unassigned") query.assignedTo = null;
  const rows = await populated(ServiceRequest.find(query).populate("student", "name email").sort({ updatedAt: -1 }).limit(500));
  res.json(rows.map((row) => serialize(row, { staff: true })));
});

const getServiceRequestAssignees = asyncHandler(async (req, res) => {
  const staff = await User.find({ $or: [{ role: "admin" }, { role: "employee", permissions: SECTION }] })
    .select("name email role").sort({ name: 1 }).lean();
  res.json(staff.map(({ _id, name, email, role }) => ({ _id, name, email, role })));
});

const updateServiceRequestStatus = asyncHandler(async (req, res) => {
  const { status, version, reason = "", staffNote, amount, dueDate } = req.body;
  if (!mongoose.isValidObjectId(req.params.id) || !SERVICE_REQUEST_STATUSES.includes(status) || !validVersion(version)
    || !validText(reason) || !validText(staffNote)) {
    return res.status(400).json({ message: "Invalid service request update" });
  }
  if (STATUSES_REQUIRING_REASON.includes(status) && !reason.trim()) {
    return res.status(400).json({ message: "Write the reason the student will see" });
  }
  if (amount !== undefined && (typeof amount !== "number" || !Number.isFinite(amount) || amount <= 0)) {
    return res.status(400).json({ message: "Amount must be a positive number" });
  }
  const due = dueDate ? new Date(dueDate) : null;
  if (due && !Number.isFinite(due.getTime())) return res.status(400).json({ message: "Invalid due date" });

  const id = await atomicOperation(res, async (session) => {
    const request = await ServiceRequest.findById(req.params.id).session(session).lean();
    if (!request) fail(404, "Request not found");
    if (request.__v !== version) fail(409, "Request changed. Refresh and retry.");
    const invoice = request.invoice ? await Invoice.findById(request.invoice).session(session).lean() : null;
    const problem = moveProblem(request, invoice, status);
    if (problem) fail(409, problem);

    const set = { status, reason: STATUSES_REQUIRING_REASON.includes(status) ? reason.trim() : "" };
    if (staffNote !== undefined) set.staffNote = staffNote.trim();
    if (status === "awaiting-payment") {
      const total = amount ?? request.serviceSnapshot?.price;
      if (!(total > 0)) fail(400, "Set the amount the student has to pay");
      const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, "");
      const [created] = await Invoice.create([{
        student: request.student,
        invoiceNumber: `SRV-${stamp}-${String(request._id).slice(-6).toUpperCase()}`,
        description: `${request.serviceSnapshot.title} — طلب خدمة`,
        amount: total, dueDate: due, category: "service",
      }], { session });
      set.invoice = created._id;
    }
    if (["cancelled", "rejected"].includes(status)) {
      await voidInvoice(invoice, req.user._id, `Voided: service request ${status}`, session);
    }
    const updated = await ServiceRequest.findOneAndUpdate(
      { _id: request._id, __v: version, status: request.status },
      {
        $set: set, ...(isTerminal(status) ? { $unset: { activeKey: 1 } } : {}), $inc: { __v: 1 },
        $push: { history: { status, note: set.reason || (staffNote || "").trim(), changedBy: req.user._id, changedAt: new Date() } },
      },
      { new: true, session }
    );
    if (!updated) fail(409, "Request changed. Refresh and retry.");
    return updated._id;
  });
  const row = await loadForStaff(id);
  await notify(row.student?._id, { ...serviceRequestStatusNotice(row, row.serviceSnapshot.title), link: "/student/service-requests" });
  res.json(serialize(row, { staff: true }));
});

const assignServiceRequest = asyncHandler(async (req, res) => {
  const { assignedTo = null, version } = req.body;
  if (!mongoose.isValidObjectId(req.params.id) || !validVersion(version)
    || (assignedTo !== null && !mongoose.isValidObjectId(assignedTo))) {
    return res.status(400).json({ message: "Invalid assignment" });
  }
  if (assignedTo) {
    const assignee = await User.findById(assignedTo).select("role permissions").lean();
    if (!assignee || !hasSection(assignee, SECTION)) {
      return res.status(400).json({ message: "This person can't handle service requests" });
    }
  }
  const updated = await ServiceRequest.findOneAndUpdate(
    { _id: req.params.id, __v: version },
    { $set: { assignedTo }, $inc: { __v: 1 } },
    { new: true }
  );
  if (!updated) {
    const exists = await ServiceRequest.exists({ _id: req.params.id });
    return res.status(exists ? 409 : 404).json({ message: exists ? "Request changed. Refresh and retry." : "Request not found" });
  }
  const row = await loadForStaff(updated._id);
  if (assignedTo && String(assignedTo) !== String(req.user._id)) {
    await notify(assignedTo, {
      title: `أُسند إليك طلب خدمة: ${row.serviceSnapshot.title}`, message: `طلب ${row.student?.name || "طالب"}.`,
      type: "info", link: "/admin/service-requests",
    });
  }
  res.json(serialize(row, { staff: true }));
});

module.exports = {
  createServiceRequest, getMyServiceRequests, getMyServiceRequest, cancelMyServiceRequest, respondToServiceRequest,
  getServiceRequestsAdmin, getServiceRequestAssignees, updateServiceRequestStatus, assignServiceRequest,
  moveProblem,
};
