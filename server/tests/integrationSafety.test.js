const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');
const { MongoMemoryReplSet } = require(path.join(process.env.STUDY_BIRDS_TEST_TOOLS, 'node_modules/mongodb-memory-server-core'));

test('concurrent wallet spends, rollback, housing capacity and duplicate requests are safe', async () => {
  process.env.JWT_SECRET = 'integration-safety-isolated-test';
  const mongo = await MongoMemoryReplSet.create({ replSet: { count: 1, storageEngine: 'wiredTiger' }, instanceOpts: [{ ip: '127.0.0.1' }] });
  let server;
  try {
    await mongoose.connect(mongo.getUri());
    const User = require('../src/models/User');
    const Invoice = require('../src/models/Invoice');
    const Entry = require('../src/models/StudentWalletEntry');
    const University = require('../src/models/University');
    const Listing = require('../src/models/AccommodationListing');
    const Booking = require('../src/models/AccommodationBooking');
    await Promise.all([User.init(), Invoice.init(), Entry.init(), Listing.init(), Booking.init()]);
    const a = await User.create({ name: 'A', email: 'a@safety.test' });
    const b = await User.create({ name: 'B', email: 'b@safety.test' });
    const c = await User.create({ name: 'C', email: 'c@safety.test' });
    const staff = await User.create({ name: 'Staff', email: 'staff@safety.test', role: 'employee', permissions: ['housing', 'student-financials'] });
    server = await new Promise(resolve => { const s = require('../src/app').listen(0, '127.0.0.1', () => resolve(s)); });
    async function call(method, endpoint, user, body) {
      const response = await fetch(`http://127.0.0.1:${server.address().port}/api${endpoint}`, {
        method, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${jwt.sign({ userId: user._id }, process.env.JWT_SECRET)}` },
        body: body ? JSON.stringify(body) : undefined,
      });
      return { status: response.status, data: await response.json() };
    }
    const credit = amount => call('POST', '/admin/student-financials/wallet-entries', staff, { studentId: a._id, direction: 'credit', amount, notes: 'test credit' });
    const balance = async () => (await call('GET', '/students/wallet', a)).data.balance;
    const redeem = invoice => call('POST', '/students/wallet/redeem', a, { invoiceId: invoice._id, amount: 10 });
    const invoices = await Invoice.create([1,2,3,4].map(i => ({ student: a._id, invoiceNumber: `SAFETY-${i}`, description: 'Test', amount: 10 })));
    assert.equal((await credit(10)).status, 201);
    const spends = await Promise.all(invoices.slice(0,2).map(redeem));
    assert.deepEqual(spends.map(r => r.status).sort(), [200,409]);
    assert.equal(await balance(), 0);
    assert.equal(await Invoice.countDocuments({ student: a._id, status: 'paid' }), 1);
    assert.equal(await Entry.countDocuments({ student: a._id, direction: 'debit' }), 1);

    // Staff debits contend on the same guard as student redemption.
    await credit(10);
    const mixed = await Promise.all([
      redeem(invoices[2]),
      call('POST', '/admin/student-financials/wallet-entries', staff, { studentId: a._id, direction: 'debit', amount: 10, notes: 'test debit' }),
    ]);
    assert.equal(mixed.filter(r => r.status === 409).length, 1);
    assert.equal(mixed.filter(r => r.status === 200 || r.status === 201).length, 1);
    assert.equal(await balance(), 0);

    // Ledger failure must roll back the already-written invoice.
    await credit(10);
    const originalCreate = Entry.create;
    Entry.create = async function (rows, ...args) {
      if (Array.isArray(rows) && rows.some(row => row.kind === 'redemption')) throw new Error('injected ledger failure');
      return originalCreate.call(this, rows, ...args);
    };
    try { assert.equal((await redeem(invoices[3])).status, 500); }
    finally { Entry.create = originalCreate; }
    const unchanged = await Invoice.findById(invoices[3]._id).lean();
    assert.equal(unchanged.status, 'unpaid');
    assert.equal(unchanged.walletCreditApplied, 0);
    assert.equal(await balance(), 10);

    const university = await University.create({ name: 'Safety University', country: new mongoose.Types.ObjectId(), city: 'City' });
    const payload = { title: 'One place', type: 'single', university: String(university._id), price: 100, capacity: 1, isActive: true };
    const listing = await Listing.create(payload);
    const listing2 = await Listing.create({ ...payload, title: 'Other place' });
    const bookingResults = await Promise.all([a,b].map(user => call('POST', '/accommodation/bookings', user, { listingId: listing._id, moveInDate: '2099-09-01T00:00:00.000Z' })));
    assert.deepEqual(bookingResults.map(r => r.status), [201,201]);
    const confirmations = await Promise.all(bookingResults.map(r => call('PATCH', `/admin/accommodation-bookings/${r.data._id}`, staff, { status: 'confirmed', version: 0 })));
    assert.deepEqual(confirmations.map(r => r.status).sort(), [200,409]);
    assert.equal(await Booking.countDocuments({ listing: listing._id, status: 'confirmed' }), 1);
    assert.equal((await call('PUT', `/admin/accommodation-listings/${listing._id}`, staff, { ...payload, capacity: 0 })).status, 409);
    assert.equal((await call('DELETE', `/admin/accommodation-listings/${listing._id}`, staff)).status, 409);

    const confirmed = confirmations.find(r => r.status === 200).data;
    const waiting = bookingResults.find(r => r.data._id !== confirmed._id).data;
    const owner = String(confirmed.student) === String(a._id) ? a : b;
    assert.equal((await call('POST', `/accommodation/bookings/${confirmed._id}/cancel`, owner, { version: confirmed.__v })).status, 200);
    assert.equal((await call('PATCH', `/admin/accommodation-bookings/${waiting._id}`, staff, { status: 'confirmed', version: 0 })).status, 200);
    assert.equal(await Booking.countDocuments({ listing: listing._id, status: 'confirmed' }), 1);

    // Different listings must not allow two active requests for the same student.
    const duplicate = await Promise.all([listing,listing2].map(row => call('POST', '/accommodation/bookings', c, { listingId: row._id })));
    assert.deepEqual(duplicate.map(r => r.status).sort(), [201,409]);
    assert.equal(await Booking.countDocuments({ student: c._id, status: { $in: ['pending','confirmed'] } }), 1);
  } finally {
    if (server) await new Promise(resolve => server.close(resolve));
    await mongoose.disconnect();
    await mongo.stop();
  }
});
