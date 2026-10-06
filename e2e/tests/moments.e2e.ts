import { expect, type Screen } from 'e2e';
import { test, tapVisibleCenter } from './native-actions.js';
import { bundle } from '../support/simulator.js';

const fixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];

async function openMoments(screen: Screen) {
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByText('E2E Second Moment').first());
}

async function rowTop(screen: Screen, label: string): Promise<number> {
  const box = await screen.getByText(label).first().boundingBox();
  if (!box) throw new Error(`${label} has no bounds`);
  return box.y;
}

/** Edit and filter sheets open at their half-height detent, where the edit form does not scroll. */
async function expandSheet(screen: Screen) {
  const grabber = await screen.getByRole('button', 'Sheet Grabber').boundingBox();
  if (!grabber) throw new Error('Sheet grabber has no bounds');
  const x = grabber.x + grabber.width / 2;
  await screen.swipe({ from: { x, y: grabber.y + grabber.height / 2 }, to: { x, y: 80 } });
}

async function filterBy(screen: Screen, option: string) {
  await screen.scrollUntilVisible(screen.getByLabel('Filter moments').first());
  await screen.getByLabel('Filter moments').first().tap();
  await screen.getByRole('button', option).tap();
  await closeFilterSheet(screen);
}

/** Wait out the dismissal, or the next open lands on the closing sheet. */
async function closeFilterSheet(screen: Screen) {
  await screen.getByRole('button', 'Done').tap();
  await expect(screen.getByText('Filter Moments')).toBeHidden();
}

async function clearFilters(screen: Screen) {
  await screen.getByLabel('Filter moments').first().tap();
  // With category, character and mood sections, Clear All sits below the half-height fold;
  // a tap there would land on the dimmed backdrop and only dismiss the sheet.
  await expandSheet(screen);
  await screen.getByRole('button', 'Clear All').tap();
  await closeFilterSheet(screen);
}

test('quote, mood and cast survive relaunch and drive the character and mood filters', async ({ device, screen, nativeKeyboard }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await openMoments(screen);
  await tapVisibleCenter(screen.getByText('E2E First Moment').first());
  await expandSheet(screen);
  await screen.scrollUntilVisible(screen.getByText('Add mood').first());
  await screen.getByText('Add mood').first().tap();
  await screen.getByRole('button', 'Tense').tap();
  await screen.scrollUntilVisible(screen.getByPlaceholder('Add character'));
  // Focus first: the keyboard scrolls the form when it appears, which drops a tap-and-type.
  await screen.getByPlaceholder('Add character').tap();
  await expect(screen.getByTestId('inputView')).toBeVisible();
  await nativeKeyboard.typeFocusedText('Elizabeth');
  await expect(screen.getByPlaceholder('Add character')).toHaveValue('Elizabeth');
  await screen.getByPlaceholder('Add character').press('Enter');
  await expect(screen.getByRole('button', 'Remove Elizabeth')).toBeVisible();
  // The quote field is multi-line (Return adds a newline), so fill it last and save from the
  // toolbar, which stays above the keyboard.
  await screen.scrollUntilVisible(screen.getByPlaceholder('Add a quote (optional)'));
  await screen.getByPlaceholder('Add a quote (optional)').fill('It is a truth universally acknowledged.');
  await screen.getByTestId('moment.done').tap();

  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await openMoments(screen);
  await tapVisibleCenter(screen.getByText('E2E First Moment').first());
  await expandSheet(screen);
  // Form order is name, note, quote; the saved quote is the third field's value.
  await expect(screen.getByRole('textbox').nth(2)).toHaveValue('It is a truth universally acknowledged.');
  await expect(screen.getByRole('button', 'Remove Tense')).toBeVisible();
  await screen.scrollUntilVisible(screen.getByRole('button', 'Remove Elizabeth'));
  await screen.getByRole('button', 'Cancel').tap();

  await filterBy(screen, 'Elizabeth');
  // The active-filter chip shows the name as typed, not the lower-cased match key.
  await expect(screen.getByText('Elizabeth', { exact: true }).first()).toBeVisible();
  await expect(screen.getByText('E2E First Moment').first()).toBeVisible();
  await expect(screen.getByText('E2E Second Moment').first()).toBeHidden();
  await clearFilters(screen);
  await expect(screen.getByText('E2E Second Moment').first()).toBeVisible();

  await filterBy(screen, 'Tense');
  await expect(screen.getByText('E2E First Moment').first()).toBeVisible();
  await expect(screen.getByText('E2E Second Moment').first()).toBeHidden();
  await clearFilters(screen);
  await expect(screen.getByText('E2E Second Moment').first()).toBeVisible();
});

test('pinning moves a moment to the top and survives relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await openMoments(screen);
  // Newest first: the second fixture moment starts above the first.
  expect(await rowTop(screen, 'E2E Second Moment')).toBeLessThan(await rowTop(screen, 'E2E First Moment'));
  const pins = screen.getByLabel('Pin moment');
  await pins.last().tap();
  await expect(screen.getByLabel('Unpin moment')).toBeVisible();
  expect(await rowTop(screen, 'E2E First Moment')).toBeLessThan(await rowTop(screen, 'E2E Second Moment'));

  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await openMoments(screen);
  await expect(screen.getByLabel('Unpin moment')).toBeVisible();
  expect(await rowTop(screen, 'E2E First Moment')).toBeLessThan(await rowTop(screen, 'E2E Second Moment'));
  await screen.getByLabel('Unpin moment').tap();
  await expect(screen.getByLabel('Unpin moment')).toBeHidden();
  expect(await rowTop(screen, 'E2E Second Moment')).toBeLessThan(await rowTop(screen, 'E2E First Moment'));
});

test('swiping a moment left reveals Delete, and the delete survives relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await openMoments(screen);
  const row = await screen.getByText('E2E Second Moment').first().boundingBox();
  if (!row) throw new Error('Moment row has no bounds');
  const y = row.y + row.height / 2;
  await screen.swipe({ from: { x: 330, y }, to: { x: 120, y } });
  await tapVisibleCenter(screen.getByLabel('Delete moment').first());
  await expect(screen.getByText('E2E Second Moment').first()).toBeHidden();
  await expect(screen.getByText('E2E First Moment').first()).toBeVisible();

  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByText('E2E First Moment').first());
  await expect(screen.getByText('E2E Second Moment').first()).toBeHidden();
});
