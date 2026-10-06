import { expect } from 'e2e';
import { test, tapVisibleCenter } from './native-actions.js';
import { bundle, grantPrivacy, resetPrivacy, waitUntilRunning } from '../support/simulator.js';

const onboarding = ['-e2e-fixture', '-onboardingComplete', 'NO', '-startOnFreeBooks', 'NO'];

test('allowing both permissions flips the cards and moves on by itself', async ({ device, screen }) => {
  resetPrivacy('all');
  await device.openApp(bundle, { relaunch: true, launchArguments: [...onboarding, '-e2e-reset-fixture'] });
  await screen.getByTestId('onboarding.choice.own').tap();
  await expect(screen.getByText('Two quick permissions.').first()).toBeVisible();

  await screen.getByTestId('onboarding.permission.microphone').tap();
  await device.alert('accept');
  await expect(screen.getByTestId('onboarding.permission.microphone')).toHaveAccessibleName('Microphone allowed');
  await screen.getByTestId('onboarding.permission.speech').tap();
  await device.alert('accept');
  // The second grant schedules the automatic advance to the Playback scene.
  await expect(screen.getByText('Set up listening.').first()).toBeVisible({ timeout: 10_000 });

  await screen.getByTestId('onboarding.page.6').tap();
  await expect(screen.getByTestId('onboarding.summary.1')).toContainText('Allowed');
});

test('a denied permission routes to Settings and a grant there is picked up on return', async ({ device, screen }) => {
  resetPrivacy('all');
  await device.openApp(bundle, { relaunch: true, launchArguments: [...onboarding, '-e2e-reset-fixture'] });
  await screen.getByTestId('onboarding.choice.own').tap();
  await expect(screen.getByText('Two quick permissions.').first()).toBeVisible();
  await screen.getByTestId('onboarding.permission.microphone').tap();
  await device.alert('dismiss');
  await expect(screen.getByTestId('onboarding.permission.microphone')).toHaveAccessibleName('Allow Microphone');
  await expect(screen.getByText('Set up listening.')).toBeHidden();

  // The system prompt cannot appear twice, so the same button now opens the Settings app.
  await screen.getByTestId('onboarding.permission.microphone').tap();
  expect(await waitUntilRunning('com.apple.Preferences')).toBe(true);
  // Changing a permission terminates the app, on a real iPhone as here, so the return trip
  // is a cold start that must read the new grant rather than remember the denial.
  grantPrivacy('microphone');
  await device.openApp(bundle, { relaunch: true, launchArguments: onboarding });
  await screen.getByTestId('onboarding.choice.own').tap();
  await expect(screen.getByText('Two quick permissions.').first()).toBeVisible();
  await expect(screen.getByTestId('onboarding.permission.microphone')).toHaveAccessibleName('Microphone allowed');
  await expect(screen.getByTestId('onboarding.permission.speech')).toHaveAccessibleName('Allow Speech Recognition');

  await screen.getByTestId('onboarding.page.6').tap();
  await expect(screen.getByTestId('onboarding.summary.1')).toContainText('Mic only');
});

test('playback choices in onboarding show in the summary and become the Settings values', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...onboarding, '-e2e-reset-fixture'] });
  await screen.getByTestId('onboarding.choice.own').tap();
  await screen.getByTestId('onboarding.page.2').tap();
  await expect(screen.getByText('Set up listening.').first()).toBeVisible();

  // Defaults first: rewind 1 min, 30s skips, moments at the current position.
  const resume = screen.getByTestId('onboarding.resume');
  await expect(resume).toHaveValue('1 min');
  await expect(screen.getByTestId('onboarding.skipBack.30')).toBeSelected();
  await expect(screen.getByTestId('onboarding.momentOffset')).toHaveText('At the moment');

  // The slider's four stops sit evenly between 17pt insets; tap the second (15s).
  const box = await resume.boundingBox();
  if (!box) throw new Error('Resume slider has no bounds');
  await resume.tap({ position: { x: 17 + (box.width - 34) / 3, y: box.height / 2 } });
  await expect(resume).toHaveValue('15s');

  await tapVisibleCenter(screen.getByTestId('onboarding.skipBack.15'));
  await tapVisibleCenter(screen.getByTestId('onboarding.skipForward.45'));
  await expect(screen.getByTestId('onboarding.skipBack.15')).toBeSelected();
  await expect(screen.getByTestId('onboarding.skipBack.30')).not.toBeSelected();
  await expect(screen.getByTestId('onboarding.skipForward.45')).toBeSelected();

  await expect(screen.getByRole('button', 'Earlier moment offset')).toBeDisabled();
  await screen.getByRole('button', 'Later moment offset').tap();
  await screen.getByRole('button', 'Later moment offset').tap();
  await expect(screen.getByTestId('onboarding.momentOffset')).toHaveText('30s earlier');

  await screen.getByTestId('onboarding.page.6').tap();
  await expect(screen.getByText("You're all set.").first()).toBeVisible();
  await expect(screen.getByTestId('onboarding.summary.0')).toContainText('My books');
  await expect(screen.getByTestId('onboarding.summary.2')).toContainText('15s');
  await expect(screen.getByTestId('onboarding.summary.3')).toContainText('15s / 45s');
  await expect(screen.getByTestId('onboarding.summary.4')).toContainText('30s earlier');
  await screen.getByRole('button', 'Open Library').tap();

  // Relaunch without the onboarding override and read what Settings stored.
  await device.openApp(bundle, { relaunch: true, launchArguments: ['-e2e-fixture'] });
  await screen.getByTestId('settingsButton').tap();
  const expected: Array<[string, string]> = [
    ['On Resume', 'Resume 15 seconds earlier'],
    ['Save Moment Offset', '30 seconds earlier'],
    ['Skip Backward', '15 seconds'],
    ['Skip Forward', '45 seconds'],
  ];
  for (const [title, value] of expected) {
    await screen.scrollUntilVisible(screen.getByTestId(`settings.picker.${title}`));
    await expect(screen.getByTestId(`settings.picker.${title}`)).toHaveValue(value);
  }
});
