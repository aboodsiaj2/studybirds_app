const mongoose = require('mongoose');

function fail(status, message) {
  const error = new Error(message);
  error.httpStatus = status;
  throw error;
}

// Never fall back to separate writes when the database lacks transactions.
async function atomicOperation(res, work) {
  try {
    return await mongoose.connection.transaction(work, {
      readConcern: { level: 'snapshot' }, writeConcern: { w: 'majority' },
    });
  } catch (error) {
    if (error.code === 20) {
      res.status(503);
      throw new Error('This operation requires a transaction-capable database.');
    }
    if (error.httpStatus) res.status(error.httpStatus);
    throw error;
  }
}

module.exports = { atomicOperation, fail };
