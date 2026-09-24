const mongoose = require("mongoose");
const asyncHandler = require("../utils/asyncHandler");
const AlumniProfile = require("../models/AlumniProfile");

function sanitize(profile, includePrivate = false) {
  const base = {
    _id: profile._id,
    graduationYear: profile.graduationYear,
    field: profile.field,
    university: profile.university,
    currentCountry: profile.currentCountry,
    currentPosition: profile.currentPosition,
    employer: profile.employer,
    bio: profile.bio,
    linkedInUrl: profile.linkedInUrl,
    isVerified: profile.isVerified,
    createdAt: profile.createdAt,
  };
  if (includePrivate) {
    base.user = profile.user;
    base.isPublic = profile.isPublic;
  }
  return base;
}

// ---- Student: get/update own profile -------------------------------------

const getMyAlumniProfile = asyncHandler(async (req, res) => {
  const profile = await AlumniProfile.findOne({ user: req.user._id })
    .populate("university", "name")
    .lean();
  res.json(profile || null);
});

const upsertMyAlumniProfile = asyncHandler(async (req, res) => {
  const { graduationYear, field, universityId, currentCountry, currentPosition, employer, bio, linkedInUrl, isPublic } = req.body;
  const patch = {};
  if (graduationYear != null) {
    if (!Number.isInteger(Number(graduationYear)) || graduationYear < 1990) {
      return res.status(400).json({ message: "Invalid graduation year" });
    }
    patch.graduationYear = Number(graduationYear);
  }
  if (typeof field === "string") patch.field = field.trim().slice(0, 200);
  if (universityId != null) {
    if (!mongoose.isValidObjectId(universityId)) return res.status(400).json({ message: "Invalid university" });
    patch.university = universityId;
  }
  if (typeof currentCountry === "string") patch.currentCountry = currentCountry.trim().slice(0, 100);
  if (typeof currentPosition === "string") patch.currentPosition = currentPosition.trim().slice(0, 200);
  if (typeof employer === "string") patch.employer = employer.trim().slice(0, 200);
  if (typeof bio === "string") patch.bio = bio.trim().slice(0, 1000);
  if (typeof linkedInUrl === "string") patch.linkedInUrl = linkedInUrl.trim().slice(0, 500);
  if (typeof isPublic === "boolean") patch.isPublic = isPublic;

  const profile = await AlumniProfile.findOneAndUpdate(
    { user: req.user._id },
    { $set: patch },
    { new: true, upsert: true, setDefaultsOnInsert: true }
  ).populate("university", "name").lean();

  res.json(sanitize(profile, true));
});

// ---- Public: browse alumni community ------------------------------------

const listAlumni = asyncHandler(async (req, res) => {
  const query = { isPublic: true };
  if (req.query.field) query.field = { $regex: req.query.field, $options: "i" };
  if (req.query.country) query.currentCountry = { $regex: req.query.country, $options: "i" };
  const profiles = await AlumniProfile.find(query)
    .populate("user", "name")
    .populate("university", "name")
    .sort({ isVerified: -1, createdAt: -1 })
    .limit(100)
    .lean();
  res.json(profiles.map((p) => ({ ...sanitize(p), name: p.user?.name })));
});

// ---- Admin: list and manage alumni ---------------------------------------

const listAlumniAdmin = asyncHandler(async (req, res) => {
  const profiles = await AlumniProfile.find()
    .populate("user", "name email")
    .populate("university", "name")
    .sort({ createdAt: -1 })
    .lean();
  res.json(profiles.map((p) => ({ ...sanitize(p, true), name: p.user?.name, email: p.user?.email })));
});

const updateAlumniAdmin = asyncHandler(async (req, res) => {
  const { isVerified, isPublic } = req.body;
  const patch = {};
  if (typeof isVerified === "boolean") patch.isVerified = isVerified;
  if (typeof isPublic === "boolean") patch.isPublic = isPublic;
  const updated = await AlumniProfile.findByIdAndUpdate(req.params.id, { $set: patch }, { new: true })
    .populate("user", "name email")
    .populate("university", "name")
    .lean();
  if (!updated) return res.status(404).json({ message: "Profile not found" });
  res.json({ ...sanitize(updated, true), name: updated.user?.name, email: updated.user?.email });
});

module.exports = { getMyAlumniProfile, upsertMyAlumniProfile, listAlumni, listAlumniAdmin, updateAlumniAdmin };
