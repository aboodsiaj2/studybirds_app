const required = ['MONGODB_URI', 'JWT_SECRET', 'CLIENT_URL'];

function fail(message) {
  console.error(`[configuration] ${message}`);
  process.exitCode = 1;
}

if (process.env.NODE_ENV === 'production') {
  for (const key of required) {
    if (!String(process.env[key] || '').trim()) fail(`${key} is required in production.`);
  }

  const mongo = String(process.env.MONGODB_URI || '');
  if (mongo && !/^mongodb(?:\+srv)?:\/\//.test(mongo)) {
    fail('MONGODB_URI must use mongodb:// or mongodb+srv://.');
  }

  const secret = String(process.env.JWT_SECRET || '');
  if (secret && secret.length < 32) fail('JWT_SECRET must contain at least 32 characters.');

  const clientUrl = String(process.env.CLIENT_URL || '');
  try {
    const parsed = new URL(clientUrl);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password) {
      fail('CLIENT_URL must be a public HTTPS origin without credentials.');
    }
  } catch {
    if (clientUrl) fail('CLIENT_URL must be a valid absolute URL.');
  }
}

if (!process.exitCode) console.log('[configuration] Environment validation passed.');
