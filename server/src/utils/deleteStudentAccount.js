const AccommodationBooking = require('../models/AccommodationBooking');
const AgencyRequest = require('../models/AgencyRequest');
const Application = require('../models/Application');
const ArrivalServiceRequest = require('../models/ArrivalServiceRequest');
const CommunityComment = require('../models/CommunityComment');
const CommunityPost = require('../models/CommunityPost');
const CommunityReport = require('../models/CommunityReport');
const CommunitySuspension = require('../models/CommunitySuspension');
const { Booking: ConsultationBooking } = require('../models/Consultation');
const Document = require('../models/Document');
const FavoriteItem = require('../models/FavoriteItem');
const { Credential: IdentityCredential, Challenge: IdentityChallenge } = require('../models/IdentityCredential');
const Invoice = require('../models/Invoice');
const Notification = require('../models/Notification');
const OrientationTestResult = require('../models/OrientationTestResult');
const ParentLink = require('../models/ParentLink');
const PaymentProof = require('../models/PaymentProof');
const PushToken = require('../models/PushToken');
const ServiceOrder = require('../models/ServiceOrder');
const StudentProfile = require('../models/StudentProfile');
const StudentReferral = require('../models/StudentReferral');
const StudentWalletEntry = require('../models/StudentWalletEntry');
const SupportTicket = require('../models/SupportTicket');
const User = require('../models/User');
const { Access, Task, Message, Decision, Preferences, Credit, EmailCode, Session } = require('../models/MobileWorkspace');

async function deleteStudentAccount(userId) {
  const [posts, comments, applications] = await Promise.all([
    CommunityPost.find({ author: userId }).select('_id').lean(),
    CommunityComment.find({ author: userId }).select('_id post').lean(),
    Application.find({ student: userId }).select('_id').lean(),
  ]);
  const postIds = posts.map((item) => item._id);
  const commentIds = comments.map((item) => item._id);
  const applicationIds = applications.map((item) => item._id);

  await Promise.all([
    CommunityReport.deleteMany({ $or: [{ reporter: userId }, { post: { $in: postIds } }, { target: { $in: commentIds } }] }),
    CommunityComment.deleteMany({ $or: [{ author: userId }, { post: { $in: postIds } }] }),
    CommunityPost.deleteMany({ author: userId }),
    Decision.deleteMany({ application: { $in: applicationIds } }),
    Document.deleteMany({ student: userId }),
    PaymentProof.deleteMany({ student: userId }),
    Invoice.deleteMany({ student: userId }),
    Application.deleteMany({ student: userId }),
    AccommodationBooking.deleteMany({ student: userId }),
    AgencyRequest.deleteMany({ student: userId }),
    ArrivalServiceRequest.deleteMany({ student: userId }),
    ConsultationBooking.deleteMany({ student: userId }),
    FavoriteItem.deleteMany({ student: userId }),
    Notification.deleteMany({ user: userId }),
    OrientationTestResult.deleteMany({ student: userId }),
    ParentLink.deleteMany({ $or: [{ parent: userId }, { student: userId }] }),
    PushToken.deleteMany({ user: userId }),
    ServiceOrder.deleteMany({ student: userId }),
    StudentProfile.deleteMany({ user: userId }),
    StudentReferral.deleteMany({ $or: [{ referrer: userId }, { referredUser: userId }] }),
    StudentWalletEntry.deleteMany({ student: userId }),
    SupportTicket.deleteMany({ $or: [{ user: userId }, { agent: userId }] }),
    CommunitySuspension.deleteMany({ user: userId }),
    IdentityCredential.deleteMany({ user: userId }),
    IdentityChallenge.deleteMany({ user: userId }),
    Access.deleteMany({ $or: [{ user: userId }, { students: userId }] }),
    Task.deleteMany({ $or: [{ assignedTo: userId }, { student: userId }, { createdBy: userId }] }),
    Message.deleteMany({ $or: [{ sender: userId }, { recipient: userId }] }),
    Preferences.deleteMany({ $or: [{ user: userId }, { referredBy: userId }] }),
    Credit.deleteMany({ $or: [{ user: userId }, { createdBy: userId }] }),
    EmailCode.deleteMany({ user: userId }),
    Session.deleteMany({ user: userId }),
  ]);

  await User.deleteOne({ _id: userId, role: 'student' });
}

module.exports = deleteStudentAccount;
