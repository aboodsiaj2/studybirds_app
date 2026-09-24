const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');
const { MongoMemoryServer } = require(path.join(process.env.STUDY_BIRDS_TEST_TOOLS, 'node_modules/mongodb-memory-server-core'));

test('student profile stores guardian, emergency, study preferences and budget', async () => {
  process.env.JWT_SECRET = 'student-profile-fields';
  const mongo = await MongoMemoryServer.create({ instance: { ip: '127.0.0.1' } });
  let server;
  try {
    await mongoose.connect(mongo.getUri());
    const User = require('../src/models/User');
    const student = await User.create({ name: 'Student', email: 'profile@example.test' });
    server = await new Promise(resolve => { const s = require('../src/app').listen(0, '127.0.0.1', () => resolve(s)); });
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/students/profile`, {
      method: 'PUT', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${jwt.sign({ userId: student._id }, process.env.JWT_SECRET)}` },
      body: JSON.stringify({
        guardianContact: { name: 'Ahmed', relationship: 'father', phone: '+90555', email: 'FATHER@EXAMPLE.TEST' },
        emergencyContact: { name: 'Sara', relationship: 'sister', phone: '+96279' },
        preferredFields: ['Medicine', 'Engineering'], preferredDegreeLevel: 'bachelor',
        studyBudget: { min: 5000, max: 10000, currency: 'usd' },
      }),
    });
    const profile = await response.json();
    assert.equal(response.status, 200, JSON.stringify(profile));
    assert.equal(profile.guardianContact.email, 'father@example.test');
    assert.equal(profile.emergencyContact.phone, '+96279');
    assert.deepEqual(profile.preferredFields, ['Medicine', 'Engineering']);
    assert.equal(profile.studyBudget.currency, 'USD');
    assert.equal(profile.studyBudget.max, 10000);
  } finally {
    if (server) await new Promise(resolve => server.close(resolve));
    await mongoose.disconnect(); await mongo.stop();
  }
});
