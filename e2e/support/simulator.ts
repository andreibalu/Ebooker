import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

// Host-side simulator controls the mobile engine does not expose. e2e.config.ts has already
// refused any simulator whose name does not start with "Unpaged e2e".
export const udid = (): string => {
  const value = process.env.E2E_SIMULATOR_UDID;
  if (!value) throw new Error('Set E2E_SIMULATOR_UDID');
  return value;
};

export const bundle = 'andreibaludev.Pageless';
const repoRoot = fileURLToPath(new URL('../..', import.meta.url));

function simctl(...args: string[]): string {
  return execFileSync('xcrun', ['simctl', ...args], { encoding: 'utf8', timeout: 60_000 });
}

/** Resets a TCC service so the next request shows the real system prompt. */
export function resetPrivacy(service: 'microphone' | 'speech-recognition' | 'photos' | 'all'): void {
  simctl('privacy', udid(), 'reset', service, bundle);
}

/** Grants a TCC service outside the app, as a person would in the Settings app. */
export function grantPrivacy(service: 'microphone' | 'speech-recognition' | 'photos'): void {
  simctl('privacy', udid(), 'grant', service, bundle);
}

/**
 * True when a process whose launchd label contains `fragment` is running on the simulator.
 * `device.foregroundApp()` answers from the session, so this is how a test proves that a link
 * really launched Safari or that a denied permission really opened the Settings app.
 */
export function isRunning(fragment: string): boolean {
  return simctl('spawn', udid(), 'launchctl', 'list').split('\n').some((line) => line.includes(fragment));
}

export async function waitUntilRunning(fragment: string, timeoutMs = 15_000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (isRunning(fragment)) return true;
    await delay(300);
  }
  return isRunning(fragment);
}

/** The app's data container on the host, for checking what really is on disk. */
export function appDataPath(): string {
  return simctl('get_app_container', udid(), bundle, 'data').trim();
}

export function terminate(bundleID: string): void {
  try {
    execFileSync('xcrun', ['simctl', 'terminate', udid(), bundleID], { stdio: 'ignore', timeout: 60_000 });
  } catch { /* not running */ }
}

/** Adds a photo to the simulator library for PhotosPicker flows. */
export function addMedia(path: string): void {
  simctl('addmedia', udid(), path);
}

/** Changes only the dedicated simulator's system appearance. */
export function setSystemAppearance(mode: 'light' | 'dark'): void {
  simctl('ui', udid(), 'appearance', mode);
}

/**
 * Clears storekitd's in-memory local StoreKit ledger by running the hosted
 * `StoreKitLedgerReset` test from the build `scripts/build-install.sh` produced.
 * `failPurchases` also arms a simulated network failure for every purchase until the next reset.
 */
export function resetStoreKitLedger(options: { failPurchases?: boolean } = {}): void {
  const buildDir = process.env.E2E_BUILD_DIR;
  if (!buildDir) throw new Error('Set E2E_BUILD_DIR to the build-install.sh scratch directory');
  const products = join(buildDir, 'dd', 'Build', 'Products');
  const xctestrun = existsSync(products)
    ? readdirSync(products).find((name) => name.endsWith('.xctestrun'))
    : undefined;
  if (!xctestrun) throw new Error(`No .xctestrun in ${products}; rerun scripts/build-install.sh`);
  execFileSync('xcodebuild', [
    'test-without-building',
    '-xctestrun', join(products, xctestrun),
    '-destination', `platform=iOS Simulator,id=${udid()}`,
    // Parallel testing runs on a clone and shuts this simulator down: the clone's ledger
    // would be cleared and the e2e session would lose its device.
    '-parallel-testing-enabled', 'NO',
    '-only-testing:PagelessTests/StoreKitLedgerReset',
  ], {
    cwd: repoRoot, stdio: 'ignore', timeout: 300_000,
    // xcodebuild hands TEST_RUNNER_-prefixed variables to the test process without the prefix.
    env: { ...process.env, TEST_RUNNER_E2E_STOREKIT_FAIL: options.failPurchases ? '1' : '0' },
  });
  terminate(bundle);
}

/** Opens a URL on the simulator, as tapping a link or a notification would. */
export function openURL(url: string): void {
  simctl('openurl', udid(), url);
}

/**
 * Writes a Boolean into the app's own defaults, as an App Intent running out of process does.
 * It names the container's plist by path. `defaults write <bundle id>` would write the
 * simulator-wide domain instead, where the app reads the key but can never remove it.
 */
export function writeAppBool(key: string, value: boolean): void {
  const plist = join(appDataPath(), 'Library', 'Preferences', `${bundle}.plist`);
  simctl('spawn', udid(), 'defaults', 'write', plist, key, '-bool', value ? 'YES' : 'NO');
}

/** True when the app's container defaults hold `key`, or the simulator-wide domain does. */
export function appDefaultExists(key: string): boolean {
  const plist = join(appDataPath(), 'Library', 'Preferences', `${bundle}.plist`);
  for (const domain of [plist, bundle]) {
    try {
      simctl('spawn', udid(), 'defaults', 'read', domain, key);
      return true;
    } catch { /* not in this domain */ }
  }
  return false;
}
