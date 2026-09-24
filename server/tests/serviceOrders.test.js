const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');
const { MongoMemoryServer } = require(path.join(process.env.STUDY_BIRDS_TEST_TOOLS, 'node_modules/mongodb-memory-server-core'));

test('service orders are owned, versioned and managed by services staff', async () => {
  process.env.JWT_SECRET = 'service-orders-test';
  const mongo = await MongoMemoryServer.create({ instance: { ip: '127.0.0.1' } });
  let server;
  try {
    await mongoose.connect(mongo.getUri());
    const User = require('../src/models/User');
    const OurService = require('../src/models/OurService');
    const student = await User.create({ name: 'Student', email: 'student@service.test' });
    const other = await User.create({ name: 'Other', email: 'other@service.test' });
    const staff = await User.create({ name: 'Services', email: 'staff@service.test', role: 'employee', permissions: ['services'] });
    const service = await OurService.create({ title: 'Translation' });
    server = await new Promise(resolve => { const s = require('../src/app').listen(0, '127.0.0.1', () => resolve(s)); });
    async function call(method, endpoint, user, body, expected = 200) {
      const response = await fetch(`http://127.0.0.1:${server.address().port}/api${endpoint}`, { method, headers: { 'Content-Type': 'application/json', ...(user ? { Authorization: `Bearer ${jwt.sign({ userId: user._id }, process.env.JWT_SECRET)}` } : {}) }, body: body ? JSON.stringify(body) : undefined });
      const data = await response.json(); assert.equal(response.status, expected, JSON.stringify(data)); return data;
    }
    await call('POST', '/service-orders', null, { serviceId: service._id }, 401);
    const order = await call('POST', '/service-orders', student, { serviceId: service._id, notes: 'Two pages' }, 201);
    assert.equal(order.service.title, 'Translation');
    await call('POST', '/service-orders', student, { serviceId: service._id }, 409);
    assert.equal((await call('GET', '/service-orders/mine', other)).length, 0);
    const rows = await call('GET', '/admin/service-orders', staff);
    assert.equal(rows.length, 1);
    const updated = await call('PATCH', `/admin/service-orders/${order._id}`, staff, { status: 'awaiting-payment', staffNote: 'Quote ready', quotedPrice: 25, currency: 'USD', version: 0 });
    assert.equal(updated.quotedPrice, 25);
    await call('POST', `/service-orders/${order._id}/cancel`, student, { version: 0 }, 409);
    const cancelled = await call('POST', `/service-orders/${order._id}/cancel`, student, { version: 1 });
    assert.equal(cancelled.status, 'cancelled');
  } finally {
    if (server) await new Promise(resolve => server.close(resolve));
    await mongoose.disconnect(); await mongo.stop();
  }
});
