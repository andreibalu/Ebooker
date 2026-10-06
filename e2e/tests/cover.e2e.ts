import { expect } from 'e2e';
import { createAgentDeviceClient } from 'agent-device';
import { test, tapVisibleCenter } from './native-actions.js';
import { NATIVE_WORKER_SESSION } from '../session.js';
import { addMedia, bundle } from '../support/simulator.js';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const fixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];
/** A 600x400 red|blue split: wider than the square crop, so cropping has something to cut. */
const photo = fileURLToPath(new URL('../fixtures/cover.png', import.meta.url));
const generatedCover = 'Cover for E2E The Listening Book';

/**
 * PhotosPicker runs out of process, so its grid is outside the app's accessibility tree. The
 * newest photo is the top-left cell on the 402x874 "Unpaged e2e" simulator; the photo added at
 * the start of the test is always the newest.
 */
async function pickNewestPhoto(): Promise<void> {
  await delay(3_000);
  await createAgentDeviceClient({ session: NATIVE_WORKER_SESSION }).interactions.press({ x: 67, y: 368 });
}

test('a picked and cropped cover photo replaces the generated cover, survives relaunch, and can be removed', async ({ device, screen }) => {
  addMedia(photo);
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await expect(screen.getByText(generatedCover).first()).toBeVisible();

  // Cancelling the crop keeps the generated cover.
  await screen.getByRole('button', 'Change cover').tap();
  await pickNewestPhoto();
  await expect(screen.getByText('Pinch to zoom  ·  Drag to reposition').first()).toBeVisible({ timeout: 15_000 });
  await screen.getByRole('button', 'Cancel').tap();
  await expect(screen.getByText(generatedCover).first()).toBeVisible();

  await screen.getByRole('button', 'Change cover').tap();
  await pickNewestPhoto();
  await tapVisibleCenter(screen.getByRole('button', 'Use Photo'));
  await expect(screen.getByRole('button', 'Use Photo')).toBeHidden();
  await expect(screen.getByText(generatedCover).first()).toBeHidden();

  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await expect(screen.getByRole('button', 'Change cover')).toBeVisible();
  await expect(screen.getByText(generatedCover).first()).toBeHidden();

  await screen.getByRole('button', 'Change cover').longPress();
  await screen.getByRole('button', 'Remove cover').tap();
  await expect(screen.getByText(generatedCover).first()).toBeVisible();
});
