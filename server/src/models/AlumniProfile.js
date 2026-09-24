const mongoose = require("mongoose");

const alumniProfileSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: "User", required: true, unique: true },
    graduationYear: { type: Number, min: 1990, max: 2100 },
    field: { type: String, trim: true, maxlength: 200 },
    university: { type: mongoose.Schema.Types.ObjectId, ref: "University" },
    currentCountry: { type: String, trim: true, maxlength: 100 },
    currentPosition: { type: String, trim: true, maxlength: 200 },
    employer: { type: String, trim: true, maxlength: 200 },
    bio: { type: String, trim: true, maxlength: 1000 },
    linkedInUrl: { type: String, trim: true, maxlength: 500 },
    isPublic: { type: Boolean, default: true },
    isVerified: { type: Boolean, default: false },
  },
  { timestamps: true }
);

alumniProfileSchema.index({ isPublic: 1, isVerified: 1, createdAt: -1 });

module.exports = mongoose.model("AlumniProfile", alumniProfileSchema);
