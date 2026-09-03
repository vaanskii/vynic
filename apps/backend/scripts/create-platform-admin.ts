/**
 * Creates the first Vynic platform administrator.
 *
 *   npm run platform-admin:create -- --email you@example.com --name "Your Name"
 *
 * The password is never a command-line argument: arguments land in shell
 * history and in the process table. It is read from the terminal with echo
 * disabled, or from PLATFORM_ADMIN_PASSWORD for a non-interactive run.
 *
 * Bootstrap only. There is no Admin Panel yet, so the first administrator has to
 * come from somewhere, and a seeded default password would be a worse hole than
 * the missing boundary this closes. Requiring shell access to the server is an
 * authorization boundary that already exists. Once one administrator exists, the
 * control-plane API is the way to manage the platform.
 *
 * Refuses to touch an existing account. Silently resetting a password from a
 * script is how an account gets taken over by whoever can run it twice.
 */
import { PrismaService } from '../src/prisma.service';
import * as argon2 from 'argon2';

const MIN_PASSWORD_LENGTH = 12;

const ENTER = ['\r', '\n'];
const END_OF_TEXT = '\u0003';
const BACKSPACE = ['\u0008', '\u007f'];

function arg(name: string): string | undefined {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1) return undefined;
  return process.argv[index + 1];
}

/** Reads a line from the terminal without echoing it. */
function readSecret(prompt: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const stdin = process.stdin;
    if (!stdin.isTTY) {
      reject(
        new Error(
          'No terminal available. Set PLATFORM_ADMIN_PASSWORD for a non-interactive run.',
        ),
      );
      return;
    }

    process.stdout.write(prompt);
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');

    let value = '';
    const finish = (result: string) => {
      stdin.setRawMode(false);
      stdin.pause();
      stdin.removeListener('data', onData);
      process.stdout.write('\n');
      resolve(result);
    };

    const onData = (chunk: string) => {
      for (const char of chunk) {
        if (ENTER.includes(char)) {
          finish(value);
          return;
        }
        if (char === END_OF_TEXT) {
          stdin.setRawMode(false);
          stdin.pause();
          process.stdout.write('\n');
          process.exit(130);
        }
        if (BACKSPACE.includes(char)) {
          value = value.slice(0, -1);
          continue;
        }
        value += char;
      }
    };
    stdin.on('data', onData);
  });
}

async function resolvePassword(): Promise<string> {
  const fromEnv = process.env.PLATFORM_ADMIN_PASSWORD;
  if (fromEnv && fromEnv.length > 0) return fromEnv;

  const password = await readSecret('Password: ');
  const confirmation = await readSecret('Confirm password: ');
  if (password !== confirmation) {
    throw new Error('The two passwords do not match.');
  }
  return password;
}

async function main(): Promise<void> {
  const email = (arg('email') ?? '').trim().toLowerCase();
  const displayName = (arg('name') ?? '').trim();

  if (!email || !displayName) {
    console.error(
      'Usage: create-platform-admin.ts --email <email> --name "<display name>"',
    );
    process.exitCode = 1;
    return;
  }

  const password = await resolvePassword();
  if (password.length < MIN_PASSWORD_LENGTH) {
    console.error(
      `The password must be at least ${MIN_PASSWORD_LENGTH} characters.`,
    );
    process.exitCode = 1;
    return;
  }

  const prisma = new PrismaService();
  await prisma.$connect();
  try {
    const existing = await prisma.platformUser.findUnique({
      where: { email },
      select: { id: true },
    });
    if (existing) {
      console.error(
        `A platform administrator already exists for ${email}. ` +
          'This script will not change an existing account.',
      );
      process.exitCode = 1;
      return;
    }

    const created = await prisma.platformUser.create({
      data: {
        email,
        displayName,
        passwordHash: await argon2.hash(password, { type: argon2.argon2id }),
      },
      select: { id: true, email: true, displayName: true, role: true },
    });

    // Never the password, never the hash.
    console.log('');
    console.log('Platform administrator created.');
    console.log(`  id    ${created.id}`);
    console.log(`  email ${created.email}`);
    console.log(`  name  ${created.displayName}`);
    console.log(`  role  ${created.role}`);
    console.log('');
    console.log('Sign in with POST /platform/auth/login.');
    console.log('');
  } finally {
    await prisma.$disconnect();
  }
}

void main().catch((error: Error) => {
  console.error(error.message);
  process.exitCode = 1;
});
