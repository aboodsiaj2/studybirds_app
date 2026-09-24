const mongoose = require("mongoose");
const slugify = require("slugify");
const { SERVICE_CATEGORIES } = require("../constants/serviceCatalog");

const ourServiceSchema = new mongoose.Schema(
  {
    slug: {
      type: String,
      unique: true,
      sparse: true,
      trim: true,
    },
    title: {
      type: String,
      required: true,
      trim: true,
    },
    image: {
      type: String,
      default: "",
    },
    detailTitle: {
      type: String,
      default: "",
      trim: true,
    },
    detailBody: {
      type: String,
      default: "",
      trim: true,
    },
    detailImage: {
      type: String,
      default: "",
    },
    featured: {
      type: Boolean,
      default: true,
    },
    sortOrder: {
      type: Number,
      default: 0,
    },
    country: {
      type: mongoose.Schema.Types.ObjectId,
      ref: "Country",
      default: null,
    },
    // Request details (PRD 35–36, 114). price null = set by staff after review.
    category: { type: String, enum: SERVICE_CATEGORIES, default: "other" },
    requestable: { type: Boolean, default: true },
    price: { type: Number, min: 0, default: null },
    currency: { type: String, trim: true, default: "USD" },
    requirements: { type: [String], default: [] },
    requiredDocuments: { type: [String], default: [] },
    estimatedDuration: { type: String, trim: true, default: "" },
    // Responsible staff member; new requests are assigned to them.
    owner: { type: mongoose.Schema.Types.ObjectId, ref: "User", default: null },
  },
  { timestamps: true }
);

ourServiceSchema.pre("validate", function ourServicePreValidate(next) {
  if (this.title && (!this.slug || this.isModified("title"))) {
    this.slug = slugify(this.title, { lower: true, strict: true }) || `service-${this._id}`;
  }

  next();
});

ourServiceSchema.index({ featured: -1, sortOrder: 1, createdAt: -1 });
ourServiceSchema.index({ updatedAt: -1 });

module.exports = mongoose.model("OurService", ourServiceSchema);
