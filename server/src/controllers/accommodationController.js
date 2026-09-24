const mongoose = require("mongoose");
const asyncHandler = require("../utils/asyncHandler");
const AccommodationListing = require("../models/AccommodationListing");
const AccommodationBooking = require("../models/AccommodationBooking");
const User = require("../models/User");
const { atomicOperation, fail } = require("../utils/atomicOperation");

async function lockListing(id, session) {
  const listing = await AccommodationListing.findOneAndUpdate(
    { _id: id }, { $inc: { bookingRevision: 1 } }, { new: true, session }
  ).lean();
  if (!listing) fail(404, "Listing not found");
  return listing;
}

const LISTING_TYPES = ["single", "shared", "apartment"];
const BOOKING_STATUSES = ["pending", "confirmed", "rejected", "cancelled"];

function normalizeListing(listing) {
  return {
    _id: listing._id, title: listing.title, type: listing.type,
    university: listing.university && (listing.university.name ? { _id: listing.university._id, name: listing.university.name } : listing.university),
    distanceFromCampusKm: listing.distanceFromCampusKm ?? null, amenities: listing.amenities || [],
    price: listing.price, currency: listing.currency, rules: listing.rules || "",
    capacity: listing.capacity, isActive: listing.isActive,
  };
}

function validListingPayload(body) {
  const { title, type, university, distanceFromCampusKm = null, amenities = [], price, currency = "USD", rules = "", capacity, isActive = true } = body;
  if (typeof title !== "string" || !title.trim() || title.length > 200) return null;
  if (!LISTING_TYPES.includes(type)) return null;
  if (!mongoose.isValidObjectId(university)) return null;
  if (distanceFromCampusKm !== null && (typeof distanceFromCampusKm !== "number" || distanceFromCampusKm < 0)) return null;
  if (!Array.isArray(amenities) || amenities.length > 30 || !amenities.every((a) => typeof a === "string" && a.length <= 100)) return null;
  if (typeof price !== "number" || price < 0) return null;
  if (typeof currency !== "string" || currency.length > 10) return null;
  if (typeof rules !== "string" || rules.length > 2000) return null;
  if (typeof capacity !== "number" || !Number.isInteger(capacity) || capacity < 0) return null;
  if (typeof isActive !== "boolean") return null;
  return { title: title.trim(), type, university, distanceFromCampusKm, amenities, price, currency: currency.trim(), rules: rules.trim(), capacity, isActive };
}

// ---- Staff: listing catalog management (mounted under /admin, auto-gated
// by the 'housing' employee section via authorizeAdminSection) ------------

const getAccommodationListingsAdmin = asyncHandler(async (req, res) => {
  const listings = await AccommodationListing.find().populate("university", "name").sort({ createdAt: -1 }).lean();
  res.json(listings.map(normalizeListing));
});

const createAccommodationListing = asyncHandler(async (req, res) => {
  const payload = validListingPayload(req.body);
  if (!payload) return res.status(400).json({ message: "Invalid listing" });
  const created = await AccommodationListing.create(payload);
  const listing = await AccommodationListing.findById(created._id).populate("university", "name").lean();
  res.status(201).json(normalizeListing(listing));
});

const updateAccommodationListing = asyncHandler(async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return res.status(404).json({ message: "Listing not found" });
  const payload = validListingPayload(req.body);
  if (!payload) return res.status(400).json({ message: "Invalid listing" });
  const listing = await atomicOperation(res, async session => {
    await lockListing(req.params.id, session);
    const occupied = await AccommodationBooking.countDocuments({ listing: req.params.id, status: 'confirmed' }).session(session);
    if (payload.capacity < occupied) fail(409, "Capacity cannot be lower than confirmed bookings");
    return AccommodationListing.findByIdAndUpdate(req.params.id, payload, { new: true, runValidators: true, session }).populate("university", "name").lean();
  });
  res.json(normalizeListing(listing));
});

const deleteAccommodationListing = asyncHandler(async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return res.status(404).json({ message: "Listing not found" });
  await atomicOperation(res, async session => {
    await lockListing(req.params.id, session);
    if (await AccommodationBooking.exists({ listing: req.params.id }).session(session)) {
      fail(409, "This listing has booking history. Deactivate it instead of deleting it.");
    }
    await AccommodationListing.deleteOne({ _id: req.params.id }, { session });
  });
  res.json({ message: "Listing deleted" });
});

// ---- Staff: booking review (mounted under /admin, 'housing' section) ----

const getAccommodationBookingsAdmin = asyncHandler(async (req, res) => {
  const bookings = await AccommodationBooking.find()
    .populate("student", "name")
    .populate({ path: "listing", select: "title type university price currency", populate: { path: "university", select: "name" } })
    .sort({ createdAt: -1 }).limit(500).lean();
  res.json(bookings);
});

const updateAccommodationBookingStatus = asyncHandler(async (req, res) => {
  const { status, staffNote = "", version } = req.body;
  if (!mongoose.isValidObjectId(req.params.id) || !["confirmed", "rejected", "cancelled"].includes(status)
    || !Number.isInteger(version) || version < 0 || typeof staffNote !== "string" || staffNote.length > 2000) {
    return res.status(400).json({ message: "Invalid booking update" });
  }
  const result = await atomicOperation(res, async session => {
  const booking = await AccommodationBooking.findById(req.params.id).session(session).lean();
  if (!booking) fail(404, "Booking not found");
  if (booking.__v !== version) fail(409, "Booking changed. Refresh and retry.");
  if (booking.status !== "pending" && !(booking.status === "confirmed" && status === "cancelled")) {
    fail(409, "This booking can no longer be updated");
  }
  const listing = await lockListing(booking.listing, session);
  if (status === 'confirmed') {
    if (!listing.isActive) fail(409, "Listing is not available");
    // There is no checkout date in this model: every confirmed booking holds
    // one place until cancelled. Do not guess non-overlapping stays by start date.
    const occupied = await AccommodationBooking.countDocuments({ listing: listing._id, status: 'confirmed' }).session(session);
    if (occupied >= listing.capacity) fail(409, "No housing capacity remains");
  }
  const now = new Date();
  const updated = await AccommodationBooking.findOneAndUpdate({ _id: booking._id, __v: version, status: booking.status }, {
    $set: { status, staffNote: staffNote.trim() }, $inc: { __v: 1 },
    $push: { history: { status, changedBy: req.user._id, changedAt: now } },
  }, { new: true, runValidators: true, session }).lean();
  if (!updated) fail(409, "Booking changed. Refresh and retry.");
  return updated;
  });
  res.json(result);
});

// ---- Any authenticated user: browse the catalog --------------------------

const getAccommodationListingsPublic = asyncHandler(async (req, res) => {
  const query = { isActive: true };
  if (req.query.university && mongoose.isValidObjectId(req.query.university)) query.university = req.query.university;
  if (req.query.type && LISTING_TYPES.includes(req.query.type)) query.type = req.query.type;
  const listings = await AccommodationListing.find(query).populate("university", "name").sort({ price: 1 }).limit(200).lean();
  res.json(listings.map(normalizeListing));
});

// ---- Student: book and manage their own request --------------------------

const createAccommodationBooking = asyncHandler(async (req, res) => {
  const { listingId, moveInDate = null, notes = "" } = req.body;
  if (!mongoose.isValidObjectId(listingId) || typeof notes !== "string" || notes.length > 2000) {
    return res.status(400).json({ message: "Invalid booking request" });
  }
  const move = moveInDate === null ? null : typeof moveInDate === "string" ? new Date(moveInDate) : new Date(NaN);
  if (move && !Number.isFinite(move.getTime())) return res.status(400).json({ message: "Invalid move-in date" });
  const booking = await atomicOperation(res, async session => {
  const student = await User.updateOne({ _id: req.user._id }, { $inc: { housingRevision: 1 } }, { session });
  if (!student.matchedCount) fail(404, "Student not found");
  const listing = await lockListing(listingId, session);
  if (!listing.isActive) fail(404, "Listing not available");
  const existing = await AccommodationBooking.exists({ student: req.user._id, status: { $in: ["pending", "confirmed"] } }).session(session);
  if (existing) fail(409, "You already have an active housing request. Cancel it before booking another.");
  const [created] = await AccommodationBooking.create([{
    student: req.user._id, listing: listingId, moveInDate: move, notes: notes.trim(),
    history: [{ status: "pending", changedBy: req.user._id, changedAt: new Date() }],
  }], { session });
  return created;
  });
  res.status(201).json(booking.toObject());
});

const getMyAccommodationBookings = asyncHandler(async (req, res) => {
  const bookings = await AccommodationBooking.find({ student: req.user._id })
    .populate({ path: "listing", populate: { path: "university", select: "name" } })
    .sort({ createdAt: -1 }).lean();
  res.json(bookings);
});

const cancelAccommodationBooking = asyncHandler(async (req, res) => {
  const { version } = req.body;
  if (!mongoose.isValidObjectId(req.params.id) || !Number.isInteger(version) || version < 0) {
    return res.status(400).json({ message: "Invalid request" });
  }
  const result = await atomicOperation(res, async session => {
  const booking = await AccommodationBooking.findOne({ _id: req.params.id, student: req.user._id }).session(session).lean();
  if (!booking) fail(404, "Booking not found");
  if (booking.__v !== version) fail(409, "Booking changed. Refresh and retry.");
  if (!["pending", "confirmed"].includes(booking.status)) fail(409, "This booking can no longer be cancelled");
  await lockListing(booking.listing, session);
  const updated = await AccommodationBooking.findOneAndUpdate({ _id: booking._id, __v: version, status: booking.status }, {
    $set: { status: "cancelled" }, $inc: { __v: 1 },
    $push: { history: { status: "cancelled", changedBy: req.user._id, changedAt: new Date() } },
  }, { new: true, session }).lean();
  if (!updated) fail(409, "Booking changed. Refresh and retry.");
  return updated;
  });
  res.json(result);
});

module.exports = {
  getAccommodationListingsAdmin, createAccommodationListing, updateAccommodationListing, deleteAccommodationListing,
  getAccommodationBookingsAdmin, updateAccommodationBookingStatus,
  getAccommodationListingsPublic, createAccommodationBooking, getMyAccommodationBookings, cancelAccommodationBooking,
  LISTING_TYPES, BOOKING_STATUSES,
};
