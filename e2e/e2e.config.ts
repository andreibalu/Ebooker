import type { E2EConfig } from 'e2e';
import { execFileSync } from 'node:child_process';
import { mobile } from '@e2e-dev/mobile';
import { MOBILE_SESSION, MOBILE_WORKERS } from './session.js';

// Explicit selection prevents prepare/warmup touching an existing booted device.
const device = process.env.E2E_SIMULATOR_UDID;
if (!device) throw new Error('Set E2E_SIMULATOR_UDID to a dedicated Unpaged e2e simulator UDID.');
let inventory: { devices: Record<string, { udid: string; name: string }[]> };
try {
  inventory = JSON.parse(execFileSync('xcrun', ['simctl', 'list', 'devices', 'available', '-j'], { encoding: 'utf8', timeout: 15_000 }));
} catch (error) {
  throw new Error('Could not read CoreSimulator inventory. Verify Xcode/simulator service access; a sandbox may require scoped approval.', { cause: error });
}
const selected = Object.values(inventory.devices).flat().find((entry) => entry.udid === device);
if (!selected) throw new Error(`E2E_SIMULATOR_UDID ${device} does not identify an available simulator.`);
if (!selected.name.startsWith('Unpaged e2e')) {
  throw new Error(`Refusing simulator "${selected.name}": use a dedicated simulator whose name starts with Unpaged e2e.`);
}


export default {
  projectId: 'unpaged-ios-offline',
  tests: 'tests/**/*.e2e.ts',
  targets: [{
    name: 'ios',
    engine: mobile({ platform: 'ios', device, session: MOBILE_SESSION, settle: 500, transition: 800 }),
    app: {
      bundleId: 'andreibaludev.Pageless',
      identity: 'unpaged-debug-offline-fixture-v1',
      ...(process.env.E2E_APP_PATH ? { appPath: process.env.E2E_APP_PATH } : {}),
      launchArguments: ['-e2e-fixture'],
      environment: 'test',
    },
  }],
  workers: MOBILE_WORKERS,
  retries: 0,
  timeout: 180_000,
  launchTimeout: 180_000,
  actionTimeout: 30_000,
  assertionTimeout: 10_000,
  cleanupTimeout: 30_000,
  cache: 'off',
  trace: 'off',
  video: 'off',
  reporters: ['list', 'junit', 'markdown'],
} satisfies E2EConfig;
