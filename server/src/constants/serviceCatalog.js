// Service catalog and service-request lifecycle (PRD 35, 36, 114).
//
// A student requests a published service; staff with the 'service-requests'
// section move the request through these statuses. The server is the only
// place that decides which move is allowed, and sends the allowed moves with
// every staff row so the website and the app never drift from it.

const SERVICE_CATEGORIES = Object.freeze([
  "accommodation", "insurance", "visa", "translation", "equivalency",
  "registration", "airport", "banking", "sim", "residence", "other",
]);

const SERVICE_REQUEST_STATUSES = Object.freeze([
  "submitted", "under-review", "action-required", "awaiting-payment",
  "in-progress", "completed", "rejected", "cancelled",
]);

const ACTIVE_SERVICE_REQUEST_STATUSES = Object.freeze(
  SERVICE_REQUEST_STATUSES.filter((status) => !["completed", "rejected", "cancelled"].includes(status))
);

const STAFF_TRANSITIONS = Object.freeze({
  submitted: ["under-review", "action-required", "awaiting-payment", "in-progress", "rejected", "cancelled"],
  "under-review": ["action-required", "awaiting-payment", "in-progress", "rejected", "cancelled"],
  "action-required": ["under-review", "awaiting-payment", "rejected", "cancelled"],
  "awaiting-payment": ["in-progress", "cancelled"],
  "in-progress": ["action-required", "completed", "cancelled"],
  completed: [],
  rejected: [],
  cancelled: [],
});

// The student sees the reason for these, so staff must write one.
const STATUSES_REQUIRING_REASON = Object.freeze(["action-required", "rejected", "cancelled"]);

const STUDENT_CANCELLABLE = Object.freeze(["submitted", "under-review", "action-required", "awaiting-payment"]);

const textList = (value) => Array.isArray(value)
  && value.length <= 30
  && value.every((item) => typeof item === "string" && item.trim() && item.length <= 300);

// Request-related service fields. Returns { fields } or { error } — never
// silently drops an invalid value, so staff learn what was rejected.
function validateServiceRequestFields(body, current = {}) {
  const pickValue = (key, fallback) => (body[key] === undefined ? current[key] ?? fallback : body[key]);
  const category = pickValue("category", "other");
  const requestable = pickValue("requestable", true);
  const price = pickValue("price", null);
  const currency = pickValue("currency", "USD");
  const requirements = pickValue("requirements", []);
  const requiredDocuments = pickValue("requiredDocuments", []);
  const estimatedDuration = pickValue("estimatedDuration", "");
  const owner = pickValue("owner", null);

  if (!SERVICE_CATEGORIES.includes(category)) return { error: "Invalid service category" };
  if (typeof requestable !== "boolean") return { error: "requestable must be true or false" };
  if (price !== null && (typeof price !== "number" || !Number.isFinite(price) || price < 0)) {
    return { error: "Price must be a positive number, or empty when set after review" };
  }
  if (typeof currency !== "string" || !currency.trim() || currency.length > 10) return { error: "Invalid currency" };
  if (!textList(requirements)) return { error: "Requirements must be a list of short texts" };
  if (!textList(requiredDocuments)) return { error: "Required documents must be a list of short texts" };
  if (typeof estimatedDuration !== "string" || estimatedDuration.length > 120) return { error: "Invalid estimated duration" };

  return {
    fields: {
      category,
      requestable,
      price,
      currency: currency.trim().toUpperCase(),
      requirements: requirements.map((item) => item.trim()),
      requiredDocuments: requiredDocuments.map((item) => item.trim()),
      estimatedDuration: estimatedDuration.trim(),
      owner: owner || null,
    },
  };
}

module.exports = {
  SERVICE_CATEGORIES,
  SERVICE_REQUEST_STATUSES,
  ACTIVE_SERVICE_REQUEST_STATUSES,
  STAFF_TRANSITIONS,
  STATUSES_REQUIRING_REASON,
  STUDENT_CANCELLABLE,
  validateServiceRequestFields,
};
