import { expect, type Screen } from 'e2e';
import { createAgentDeviceClient } from 'agent-device';
import { afterEach, type Device } from '@e2e-dev/mobile';
import { test, tapVisibleCenter } from './native-actions.js';
import { NATIVE_WORKER_SESSION } from '../session.js';
import { bundle, resetStoreKitLedger } from '../support/simulator.js';
import { setTimeout as delay } from 'node:timers/promises';

// Real purchases against the local StoreKit configuration (Products.storekit), through the real
// system payment sheet. Every test starts from an empty ledger: storekitd keeps transactions in
// memory across launches, so without the reset a Plus trial from one test leaks into the next.
// Clear it after each test as well, so a test run on its own leaves no Plus trial for other files.
afterEach(() => resetStoreKitLedger());

const fixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];

/**
 * The payment sheet belongs to a system process, so its buttons are outside the app's
 * accessibility tree. These are its points on the iPhone 18 Pro "Unpaged e2e" simulator
 * (402x874): the confirm button sits at the same spot on every sheet; the close button moves
 * with the sheet's height. The system "You're all set." alert after it is a normal alert.
 */
const sheet = {
  confirm: { x: 201, y: 811 },
  closeSubscription: { x: 44, y: 376 },
  closeCoffee: { x: 44, y: 418 },
};

async function pressSheet(point: { x: number; y: number }): Promise<void> {
  // The sheet slides up after the tap that requested it; give it time to settle.
  await delay(4_000);
  await createAgentDeviceClient({ session: NATIVE_WORKER_SESSION }).interactions.press(point);
}

/**
 * Confirms StoreKit's "You're all set." alert. `device.alert('accept')` activates its OK once but
 * this alert ignores that activation, so tap the OK button itself and wait for the alert to go:
 * a leftover alert blocks every later launch on the simulator.
 */
async function confirmPurchaseAlert(screen: Screen): Promise<void> {
  await expect(screen.getByText('You’re all set.').first()).toBeVisible({ timeout: 20_000 });
  await tapVisibleCenter(screen.getByRole('button', 'OK'));
  await expect(screen.getByText('You’re all set.')).toBeHidden({ timeout: 10_000 });
}

/** Opens the Unpaged Plus hub from the library header's Plus button. */
async function openPlusCard(device: Device, screen: Screen, extra: string[] = []) {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, ...extra] });
  await screen.getByTestId('plusButton').tap();
  await expect(screen.getByText('Unpaged Plus').first()).toBeVisible();
}

test('a Plus trial bought through the payment sheet unlocks Plus and survives relaunch', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  resetStoreKitLedger();
  await openPlusCard(device, screen, ['-e2e-reset-fixture']);
  await expect(screen.getByRole('button', 'Monthly, $2.99, 1 week free')).toBeVisible();
  await screen.scrollUntilVisible(screen.getByRole('button', 'Try 1 week free'));
  await tapVisibleCenter(screen.getByRole('button', 'Try 1 week free'));
  await pressSheet(sheet.confirm);
  await confirmPurchaseAlert(screen);
  await expect(screen.getByText('7 days remaining').first()).toBeVisible({ timeout: 30_000 });
  await expect(screen.getByText('Unpaged Plus', { exact: true }).first()).toBeVisible();
  await expect(screen.getByRole('button', 'Try 1 week free')).toBeHidden();

  await openPlusCard(device, screen);
  await expect(screen.getByText('7 days remaining').first()).toBeVisible({ timeout: 30_000 });
});

test('closing the payment sheet leaves Plus locked and shows no error', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  resetStoreKitLedger();
  await openPlusCard(device, screen, ['-e2e-reset-fixture']);
  await screen.scrollUntilVisible(screen.getByRole('button', 'Try 1 week free'));
  await tapVisibleCenter(screen.getByRole('button', 'Try 1 week free'));
  await pressSheet(sheet.closeSubscription);
  await expect(screen.getByRole('button', 'Try 1 week free')).toBeEnabled({ timeout: 15_000 });
  // A user cancel is not an error: the "Unpaged Plus" alert must not appear.
  await expect(screen.getByRole('button', 'OK')).toBeHidden();
  await expect(screen.getByText(/days? remaining/)).toBeHidden();
});

test('a failed purchase reports an error and leaves Plus locked', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  resetStoreKitLedger({ failPurchases: true });
  try {
    await openPlusCard(device, screen, ['-e2e-reset-fixture']);
    await screen.scrollUntilVisible(screen.getByRole('button', 'Try 1 week free'));
    await tapVisibleCenter(screen.getByRole('button', 'Try 1 week free'));
    // The armed network failure fails before the payment sheet on iOS 27, and StoreKit's own
    // "Unable to Complete Request" reads fine. iOS 18 shows the sheet first, fails once it is
    // confirmed and describes the failure only as an NSURLErrorDomain code, so the app words it.
    const message = /^(Unable to Complete Request|Couldn’t reach the App Store\. .*)$/;
    const failure = screen.getByText(message).first();
    const failedBeforeSheet = await failure.waitFor({ state: 'visible', timeout: 6_000 }).then(() => true, () => false);
    if (!failedBeforeSheet) await pressSheet(sheet.confirm);
    await expect(failure).toBeVisible({ timeout: 20_000 });
    await expect(screen.getByText(/NSURLErrorDomain/)).toBeHidden();
    await tapVisibleCenter(screen.getByRole('button', 'OK'));
    await expect(screen.getByText(message)).toBeHidden();
    await expect(screen.getByRole('button', 'Try 1 week free')).toBeEnabled();
    await expect(screen.getByText(/days? remaining/)).toBeHidden();
  } finally {
    resetStoreKitLedger();
  }
});

test('restore with nothing to restore signs in and keeps Plus locked without an error', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  resetStoreKitLedger();
  await openPlusCard(device, screen, ['-e2e-reset-fixture']);
  await screen.scrollUntilVisible(screen.getByText('Restore purchases').first());
  await tapVisibleCenter(screen.getByText('Restore purchases').first());
  // AppStore.sync() asks for the Apple Account; local StoreKit simulates that prompt.
  await expect(screen.getByText('Sign in with Apple Account').first()).toBeVisible({ timeout: 20_000 });
  await tapVisibleCenter(screen.getByRole('button', 'OK'));
  await expect(screen.getByText('Sign in with Apple Account')).toBeHidden({ timeout: 10_000 });
  await delay(3_000);
  await expect(screen.getByRole('button', 'OK')).toBeHidden();
  await expect(screen.getByRole('button', 'Try 1 week free')).toBeVisible();
});

test('cancelling the restore sign-in is not reported as an error', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  resetStoreKitLedger();
  await openPlusCard(device, screen, ['-e2e-reset-fixture']);
  await screen.scrollUntilVisible(screen.getByText('Restore purchases').first());
  await tapVisibleCenter(screen.getByText('Restore purchases').first());
  await expect(screen.getByText('Sign in with Apple Account').first()).toBeVisible({ timeout: 20_000 });
  await tapVisibleCenter(screen.getByRole('button', 'Cancel'));
  await expect(screen.getByText('Sign in with Apple Account')).toBeHidden({ timeout: 10_000 });
  // Before the userCancelled fix this raised the "Unpaged Plus" error alert.
  await delay(3_000);
  await expect(screen.getByRole('button', 'OK')).toBeHidden();
  await expect(screen.getByRole('button', 'Try 1 week free')).toBeVisible();
});

test('a coffee tip can be cancelled, then bought, and unlocks nothing', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  resetStoreKitLedger();
  // The coffee tip lives in Settings (Support), not in the Plus hub.
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('settingsButton').tap();
  await screen.scrollUntilVisible(screen.getByText('Buy me a coffee').first());
  await tapVisibleCenter(screen.getByText('Buy me a coffee').first());
  const buy = screen.getByRole('button', /^Buy a coffee — /);
  await expect(buy).toBeEnabled({ timeout: 15_000 });

  await tapVisibleCenter(buy);
  await pressSheet(sheet.closeCoffee);
  await expect(screen.getByText('Purchase cancelled.').first()).toBeVisible({ timeout: 15_000 });

  await tapVisibleCenter(buy);
  await pressSheet(sheet.confirm);
  await confirmPurchaseAlert(screen);
  await expect(screen.getByText('Thank you for the coffee.').first()).toBeVisible({ timeout: 30_000 });

  // A tip is support only: Plus stays on offer.
  await openPlusCard(device, screen);
  await screen.scrollUntilVisible(screen.getByRole('button', 'Try 1 week free'));
});

test('AI settings stay reachable from the Plus hub without a purchase (Apple 3.1.1), and iCloud is not sold there', async ({ device, screen }) => {
  resetStoreKitLedger();
  await openPlusCard(device, screen, ['-e2e-reset-fixture']);
  // iCloud sync is free: the hub neither lists it as a Plus feature nor links to its settings.
  await expect(screen.getByText(/iCloud/)).toBeHidden();
  await expect(screen.getByRole('button', /^iCloud Sync, /)).toBeHidden();
  const link = screen.getByRole('button', /^Apple Intelligence, /);
  // iOS 26 formats the same trial as "7 days".
  const purchase = screen.getByRole('button', /^Try (1 week|7 days) free$/);
  await screen.scrollUntilVisible(purchase);
  if (await screen.getByTestId('plus.unsupportedDeviceNote').isVisible()) {
    // An iPhone that can't run Apple Intelligence still offers Plus, with a note and no AI link.
    await expect(link).toBeHidden();
    return;
  }
  await screen.scrollUntilVisible(link);
  await tapVisibleCenter(link);
  await expect(screen.getByText('AI Features', { exact: true }).first()).toBeVisible();
  await tapVisibleCenter(screen.getByRole('button', 'Settings'));
  await expect(screen.getByRole('button', 'Settings')).toBeHidden();
});

test('on an iPhone without Apple Intelligence, Plus says so above the plans before any purchase', async ({ device, screen, app }) => {
  resetStoreKitLedger();
  await openPlusCard(device, screen, ['-e2e-reset-fixture', '-e2e-ai-unsupported-device']);
  const note = screen.getByTestId('plus.unsupportedDeviceNote');
  await expect(note).toBeVisible();
  await expect(note).toContainText('Requires an iPhone with Apple Intelligence');
  // Reachable for App Review (3.1.1), and the notice comes first.
  const purchase = screen.getByRole('button', /^Try (1 week|7 days) free$/);
  await screen.scrollUntilVisible(purchase);
  const [noteBox, purchaseBox] = [await note.boundingBox(), await purchase.boundingBox()];
  if (!noteBox || !purchaseBox) throw new Error('Plus card has no bounds');
  expect(noteBox.y + noteBox.height).toBeLessThan(purchaseBox.y);
  await expect(screen.getByRole('button', /^Apple Intelligence, /)).toBeHidden();
  await app.screenshot('plus-unsupported-device');
});
