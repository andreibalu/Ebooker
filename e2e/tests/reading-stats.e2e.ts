import { expect } from 'e2e';
import { test, tapVisibleCenter } from './native-actions.js';
import { bundle } from '../support/simulator.js';

const fixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];

function localDayKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

test('reading activity card shows streak grace copy when the latest session was yesterday', async ({ device, screen }) => {
  await device.openApp(bundle, {
    relaunch: true,
    launchArguments: [...fixture, '-e2e-reset-fixture', '-e2e-reading-streak-yesterday'],
  });
  await expect(screen.getByTestId('readingActivity')).toBeVisible();
  await expect(screen.getByTestId('readingActivity')).toContainText('3-day streak · listen today');
});

test('Settings Reading Activity opens stats with a Settings back button', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('settingsButton').tap();
  const row = screen.getByTestId('settings.readingActivity');
  await screen.scrollUntilVisible(row);
  await tapVisibleCenter(row);
  await expect(screen.getByText(/^READING · /).first()).toBeVisible();
  await expect(screen.getByRole('button', 'Settings').last()).toBeVisible();
  await tapVisibleCenter(screen.getByRole('button', 'Settings').last());
  await expect(screen.getByTestId('settings.readingActivity')).toBeVisible();
  await tapVisibleCenter(screen.getByRole('button', 'Done'));
});

test('heatmap tap shows day detail, goal and palette persist across relaunch, and share opens', {
  timeout: 180_000,
}, async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('readingActivity').tap();
  await expect(screen.getByText(/^READING · /).first()).toBeVisible();

  const todayCell = screen.getByTestId(`readingStats.heatmap.${localDayKey(new Date())}`);
  await tapVisibleCenter(todayCell);
  await expect(screen.getByTestId('readingStats.dayDetail')).toBeVisible();
  await expect(screen.getByTestId('readingStats.dayDetail')).toContainText('42m');
  await tapVisibleCenter(todayCell);
  await expect(screen.getByTestId('readingStats.dayDetail')).toBeHidden();

  const goal30 = screen.getByTestId('readingStats.goal.30');
  await screen.scrollUntilVisible(goal30);
  await tapVisibleCenter(goal30);
  await expect(screen.getByTestId('readingStats.goalProgress')).toBeVisible();

  const monoPalette = screen.getByTestId('readingStats.palette.mono');
  await screen.scrollUntilVisible(monoPalette);
  await tapVisibleCenter(monoPalette);
  await expect(monoPalette).toBeSelected();

  const shareButton = screen.getByTestId('readingStats.share');
  await expect(shareButton).toBeVisible();
  await tapVisibleCenter(shareButton);
  const shareSheet = screen.getByTestId('ActivityListView');
  await expect(shareSheet).toBeVisible();
  const dismissRegion = screen.getByTestId('PopoverDismissRegion');
  const dismissBox = await dismissRegion.boundingBox();
  if (dismissBox) {
    await dismissRegion.tap({ position: { x: dismissBox.width / 2, y: 80 } });
  }
  await expect(shareSheet).toBeHidden();

  await tapVisibleCenter(screen.getByRole('button', 'Library').last());
  await expect(screen.getByTestId('readingActivity')).toContainText('30m');

  // Relaunch without -e2e-reset-fixture to verify persisted goal and palette.
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await expect(screen.getByTestId('readingActivity')).toContainText('30m');
  await screen.getByTestId('readingActivity').tap();
  await expect(screen.getByTestId('readingStats.goalProgress')).toBeVisible();
  const monoAfterRelaunch = screen.getByTestId('readingStats.palette.mono');
  await screen.scrollUntilVisible(monoAfterRelaunch);
  await expect(monoAfterRelaunch).toBeSelected();
});
