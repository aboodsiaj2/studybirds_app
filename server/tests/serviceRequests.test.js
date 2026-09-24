const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');
const { MongoMemoryReplSet } = require(path.join(process.env.STUDY_BIRDS_TEST_TOOLS, 'node_modules/mongodb-memory-server-core'));

test('service-request lifecycle, permissions, deduplication, invoice creation and voiding', async () => {
  process.env.JWT_SECRET = 'service-req-isolated-test';
  const mongo = await MongoMemoryReplSet.create({ replSet: { count: 1, storageEngine: 'wiredTiger' }, instanceOpts: [{ ip: '127.0.0.1' }] });
  let server;
  try {
    await mongoose.connect(mongo.getUri());
    const User = require('../src/models/User');
    const OurService = require('../src/models/OurService');
    const ServiceRequestModel = require('../src/models/ServiceRequest');
    // Ensure the partial-unique index on activeKey is built before the test runs.
    await ServiceRequestModel.createIndexes();

    const student = await User.create({ name: 'Ali Student', email: 'ali@example.test' });
    const student2 = await User.create({ name: 'Sara Student', email: 'sara@example.test' });
    const srStaff = await User.create({ name: 'SR Staff', email: 'sr@example.test', role: 'employee', permissions: ['service-requests'] });
    const otherStaff = await User.create({ name: 'Other Staff', email: 'other@example.test', role: 'employee', permissions: ['applications'] });
    const admin = await User.create({ name: 'Admin', email: 'admin@example.test', role: 'admin' });

    const service = await OurService.create({ title: 'Visa Processing', requestable: true, price: 150, currency: 'USD' });
    const nonRequestableService = await OurService.create({ title: 'Legacy Service', requestable: false });

    server = await new Promise(resolve => { const s = require('../src/app').listen(0, '127.0.0.1', () => resolve(s)); });

    async function call(method, endpoint, user, body, expected = 200) {
      const resp = await fetch(`http://127.0.0.1:${server.address().port}/api${endpoint}`, {
        method,
        headers: {
          'Content-Type': 'application/json',
          ...(user ? { Authorization: `Bearer ${jwt.sign({ userId: user._id }, process.env.JWT_SECRET)}` } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
      });
      const data = await resp.json();
      assert.equal(resp.status, expected, `${method} ${endpoint}: expected ${expected}, got ${resp.status}: ${JSON.stringify(data)}`);
      return data;
    }

    // ---- auth guards ---------------------------------------------------------
    await call('GET', '/students/service-requests', null, null, 401);
    await call('POST', '/students/service-requests', null, {}, 401);
    await call('GET', '/admin/service-requests', null, null, 401);
    await call('GET', '/admin/service-requests', otherStaff, null, 403);

    // ---- non-requestable service returns 409 ---------------------------------
    await call('POST', '/students/service-requests', student, { serviceId: String(nonRequestableService._id) }, 409);

    // ---- invalid serviceId returns 400 --------------------------------------
    await call('POST', '/students/service-requests', student, { serviceId: 'not-an-id' }, 400);
    await call('POST', '/students/service-requests', student, { serviceId: String(new mongoose.Types.ObjectId()) }, 404);

    // ---- create a request (submitted) ----------------------------------------
    const created = await call('POST', '/students/service-requests', student, {
      serviceId: String(service._id),
      notes: 'أحتاج تأشيرة دراسية',
    }, 201);
    assert.equal(created.status, 'submitted');
    assert.equal(created.service.title, 'Visa Processing');
    assert.equal(created.canCancel, true);
    assert.equal(created.canRespond, false);
    assert.ok(!('allowedStatuses' in created), 'student row must not expose allowedStatuses');

    // ---- duplicate active request returns 409 --------------------------------
    await call('POST', '/students/service-requests', student, { serviceId: String(service._id) }, 409);

    // ---- different student can create for the same service -------------------
    const sara = await call('POST', '/students/service-requests', student2, { serviceId: String(service._id) }, 201);
    assert.equal(sara.status, 'submitted');

    // ---- student isolation: student only sees their own ----------------------
    const myList = await call('GET', '/students/service-requests', student);
    assert.equal(myList.length, 1);
    assert.equal(myList[0]._id, created._id);

    // ---- staff sees all; section guard applies --------------------------------
    const adminList = await call('GET', '/admin/service-requests', srStaff);
    assert.equal(adminList.length, 2);
    assert.ok('allowedStatuses' in adminList[0]);
    assert.ok('student' in adminList[0]);

    // ---- status filter works -------------------------------------------------
    const filteredList = await call('GET', '/admin/service-requests?status=submitted', srStaff);
    assert.equal(filteredList.length, 2);
    const wrongFilter = await call('GET', '/admin/service-requests?status=completed', srStaff);
    assert.equal(wrongFilter.length, 0);

    // ---- staff moves to under-review -----------------------------------------
    const underReview = await call('PATCH', `/admin/service-requests/${created._id}`, srStaff, {
      status: 'under-review',
      version: created.__v,
    });
    assert.equal(underReview.status, 'under-review');
    assert.ok(Array.isArray(underReview.allowedStatuses));
    assert.ok(underReview.allowedStatuses.includes('action-required'));

    // ---- version conflict returns 409 ----------------------------------------
    await call('PATCH', `/admin/service-requests/${created._id}`, srStaff, {
      status: 'action-required',
      version: created.__v,          // stale version
      reason: 'Need extra documents',
    }, 409);

    // ---- staff requests action from student (reason required) ----------------
    // Missing reason → 400
    await call('PATCH', `/admin/service-requests/${created._id}`, srStaff, {
      status: 'action-required',
      version: underReview.__v,
    }, 400);

    const actionRequired = await call('PATCH', `/admin/service-requests/${created._id}`, srStaff, {
      status: 'action-required',
      version: underReview.__v,
      reason: 'بحاجة إلى جواز سفرك',
    });
    assert.equal(actionRequired.status, 'action-required');
    assert.equal(actionRequired.reason, 'بحاجة إلى جواز سفرك');

    // ---- student can respond (moves back to under-review) -------------------
    const studentView = await call('GET', `/students/service-requests/${created._id}`, student);
    assert.equal(studentView.canRespond, true);

    const responded = await call('POST', `/students/service-requests/${created._id}/respond`, student, {
      version: studentView.__v,
      reply: 'أرفقت الجواز في القسم المخصص',
    });
    assert.equal(responded.status, 'under-review');
    assert.equal(responded.studentReply, 'أرفقت الجواز في القسم المخصص');
    assert.equal(responded.canRespond, false);

    // ---- student cannot respond when not action-required --------------------
    await call('POST', `/students/service-requests/${created._id}/respond`, student, {
      version: responded.__v,
      reply: 'هل وصلكم؟',
    }, 409);

    // ---- staff issues invoice (awaiting-payment) ----------------------------
    // Missing amount and no price snapshotted yet on this one → 400
    // Note: service.price=150 was snapshotted, so amount defaults to snapshot
    const awaitingPayment = await call('PATCH', `/admin/service-requests/${created._id}`, srStaff, {
      status: 'awaiting-payment',
      version: responded.__v,
    });
    assert.equal(awaitingPayment.status, 'awaiting-payment');
    assert.ok(awaitingPayment.invoice, 'invoice should be created');
    assert.equal(awaitingPayment.invoice.amount, 150);
    assert.equal(awaitingPayment.invoice.status, 'unpaid');
    assert.ok(awaitingPayment.invoice.invoiceNumber.startsWith('SRV-'));

    // ---- duplicate invoice guard: can't issue another -----------------------
    await call('PATCH', `/admin/service-requests/${created._id}`, srStaff, {
      status: 'awaiting-payment',
      version: awaitingPayment.__v,
    }, 409);

    // ---- invalid transition: can't move backwards without going via in-progress
    await call('PATCH', `/admin/service-requests/${created._id}`, srStaff, {
      status: 'under-review',
      version: awaitingPayment.__v,
    }, 409);

    // ---- staff marks in-progress (invoice must be paid first) ---------------
    await call('PATCH', `/admin/service-requests/${created._id}`, srStaff, {
      status: 'in-progress',
      version: awaitingPayment.__v,
    }, 409);

    // Pay the invoice directly in DB, then retry
    const Invoice = require('../src/models/Invoice');
    await Invoice.findByIdAndUpdate(awaitingPayment.invoice._id, { $set: { status: 'paid' } });

    const inProgress = await call('PATCH', `/admin/service-requests/${created._id}`, srStaff, {
      status: 'in-progress',
      version: awaitingPayment.__v,
    });
    assert.equal(inProgress.status, 'in-progress');

    // ---- complete the service -----------------------------------------------
    const completed = await call('PATCH', `/admin/service-requests/${created._id}`, srStaff, {
      status: 'completed',
      version: inProgress.__v,
    });
    assert.equal(completed.status, 'completed');
    assert.equal(completed.allowedStatuses.length, 0, 'terminal: no further moves');

    // ---- cancel path: voiding an unpaid invoice ------------------------------
    const sara2 = await call('GET', `/students/service-requests/${sara._id}`, student2);
    const saraUnderReview = await call('PATCH', `/admin/service-requests/${sara._id}`, srStaff, {
      status: 'under-review',
      version: sara2.__v,
    });
    const saraAwaitingPay = await call('PATCH', `/admin/service-requests/${sara._id}`, srStaff, {
      status: 'awaiting-payment',
      version: saraUnderReview.__v,
      amount: 200,
    });
    assert.ok(saraAwaitingPay.invoice, 'invoice created for Sara');

    const saraStudentView = await call('GET', `/students/service-requests/${sara._id}`, student2);
    assert.equal(saraStudentView.canCancel, true);
    const saraCancelled = await call('POST', `/students/service-requests/${sara._id}/cancel`, student2, {
      version: saraStudentView.__v,
    });
    assert.equal(saraCancelled.status, 'cancelled');

    // invoice should be voided
    const voidedInvoice = await Invoice.findById(saraAwaitingPay.invoice._id).lean();
    assert.equal(voidedInvoice.status, 'rejected', 'voided invoice status must be rejected');

    // ---- assignees endpoint -------------------------------------------------
    const assignees = await call('GET', '/admin/service-requests/assignees', srStaff);
    assert.ok(Array.isArray(assignees));
    const ids = assignees.map(a => a._id);
    assert.ok(ids.includes(String(srStaff._id)), 'srStaff should be in assignees');
    assert.ok(!ids.includes(String(otherStaff._id)), 'otherStaff should not be in assignees');

    // ---- assign endpoint ----------------------------------------------------
    // After completion activeKey is cleared; a new request is now allowed.
    await call('POST', '/students/service-requests', student, { serviceId: String(nonRequestableService._id) }, 409);
    const newReq = await call('POST', '/students/service-requests', student, {
      serviceId: String(service._id),
    }, 201);
    // Can't assign someone who doesn't have the section
    await call('PATCH', `/admin/service-requests/${newReq._id}/assign`, srStaff, {
      assignedTo: String(otherStaff._id),
      version: newReq.__v,
    }, 400);
    const assigned = await call('PATCH', `/admin/service-requests/${newReq._id}/assign`, srStaff, {
      assignedTo: String(srStaff._id),
      version: newReq.__v,
    });
    assert.equal(assigned.assignedTo._id, String(srStaff._id));

  } finally {
    if (server) server.close();
    await mongoose.disconnect();
    await mongo.stop();
  }
});
