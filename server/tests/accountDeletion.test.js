const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');
const { MongoMemoryServer } = require(path.join(process.env.STUDY_BIRDS_TEST_TOOLS, 'node_modules/mongodb-memory-server-core'));

test('student deletes only their account after password and phrase verification', async () => {
  process.env.JWT_SECRET = 'account-deletion-test';
  const mongo = await MongoMemoryServer.create({ instance: { ip: '127.0.0.1' } });
  let server;
  try {
    await mongoose.connect(mongo.getUri());
    const User = require('../src/models/User');
    const StudentProfile = require('../src/models/StudentProfile');
    const Notification = require('../src/models/Notification');
    const { Message, Session } = require('../src/models/MobileWorkspace');
    const student = await User.create({ name: 'Delete Me', email: 'delete@example.test', password: 'Secret123!', role: 'student' });
    const other = await User.create({ name: 'Keep Me', email: 'keep@example.test', password: 'Secret123!', role: 'student' });
    await StudentProfile.create({ user: student._id });
    await Notification.create({ user: student._id, title: 'Private', message: 'Delete this' });
    await Message.create({ sender: student._id, recipient: other._id, body: 'Private message' });
    const token = jwt.sign({ userId: student._id, tokenVersion: 0 }, process.env.JWT_SECRET);
    server = await new Promise((resolve) => { const instance = require('../src/app').listen(0, '127.0.0.1', () => resolve(instance)); });
    const call = async (body, expected) => {
      const response = await fetch(`http://127.0.0.1:${server.address().port}/api/auth/account`, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify(body),
      });
      const data = await response.json();
      assert.equal(response.status, expected, JSON.stringify(data));
      return data;
    };

    await call({ password: 'Secret123!', confirmation: 'delete' }, 400);
    await call({ password: 'wrong', confirmation: 'DELETE' }, 401);
    assert.ok(await User.findById(student._id));

    await call({ password: 'Secret123!', confirmation: 'DELETE' }, 200);
    assert.equal(await User.findById(student._id), null);
    assert.equal(await StudentProfile.countDocuments({ user: student._id }), 0);
    assert.equal(await Notification.countDocuments({ user: student._id }), 0);
    assert.equal(await Message.countDocuments({ $or: [{ sender: student._id }, { recipient: student._id }] }), 0);
    assert.equal(await Session.countDocuments({ user: student._id }), 0);
    assert.ok(await User.findById(other._id));
  } finally {
    if (server) await new Promise((resolve) => server.close(resolve));
    await mongoose.disconnect();
    await mongo.stop();
  }
});
