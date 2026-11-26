import { expect, type Screen } from 'e2e';
import { test, tapVisibleCenter, expectShareSheetThenDismiss, expandSheet } from './native-actions.js';
import { execFileSync } from 'node:child_process';
import { bundle, udid } from '../support/simulator.js';

const fixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];

async function openMoments(screen: Screen) {
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByText('E2E Second Moment').first());
}

/** The second fixture book is not a favorite, so it lists only under the Library tab. */
async function openAnotherBook(screen: Screen) {
  await screen.getByTestId('libraryTab').tap();
  await screen.getByTestId('book.card.E2E-Another-Book').tap();
}

async function rowTop(screen: Screen, label: string): Promise<number> {
  const box = await screen.getByText(label).first().boundingBox();
  if (!box) throw new Error(`${label} has no bounds`);
  return box.y;
}

async function filterBy(screen: Screen, option: string) {
  await screen.scrollUntilVisible(screen.getByLabel('Filter moments').first());
  await screen.getByLabel('Filter moments').first().tap();
  // The category, character and mood sections together overrun the half-height detent, so the
  // mood buttons start below the fold.
  await expandSheet(screen);
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
  // Wait out the dismissal: a scroll during it lands on the closing form, which can't move.
  await expect(screen.getByTestId('moment.done')).toBeHidden();

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

// The second fixture moment carries every field (quote, mood, cast, categories, an AI-named flag,
// a transcript); the first has only a note and one category.
test('book moment rows show the quote and a metadata strip, never the transcript', async ({ device, screen, app }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await openMoments(screen);
  const quote = screen.getByTestId('moment.quote.E2E Second Moment');
  await expect(quote).toBeVisible();
  await expect(quote).toContainText('Every harbour keeps a light for strangers.');
  const meta = screen.getByTestId('moment.meta.E2E Second Moment');
  await expect(meta).toBeVisible();
  await expect(meta).toContainText('Peaceful');
  await expect(meta).toContainText('Marlow');
  // The strip is one line: it can't grow with its content.
  const strip = await meta.boundingBox();
  if (!strip) throw new Error('Metadata strip has no bounds');
  expect(strip.height).toBeLessThan(60);
  // Spoken words stay in the edit sheet and the search results.
  await expect(screen.getByText(/lighthouse/).first()).toBeHidden();
  // A sparse moment grows no quote line and no mood.
  await expect(screen.getByTestId('moment.quote.E2E First Moment')).toBeHidden();
  await expect(screen.getByTestId('moment.meta.E2E First Moment')).toContainText('Dialogue');
  await expect(screen.getByTestId('moment.meta.E2E First Moment')).not.toContainText('Peaceful');
  await app.screenshot('moments-inline-metadata');
});

test('a moment with no quote, mood, cast or category adds no quote line or strip', async ({ device, screen }) => {
  // The moment-search fixture adds a plain "E2E Café" moment to the second book.
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture', '-e2e-moment-search'] });
  await openAnotherBook(screen);
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByText('E2E Café').first());
  await expect(screen.getByTestId('moment.quote.E2E Café')).toBeHidden();
  await expect(screen.getByTestId('moment.meta.E2E Café')).toBeHidden();
  // The same book's cast moment does get a strip.
  await expect(screen.getByTestId('moment.meta.E2E Arrival')).toContainText('Ariadne');
});

test('the edit sheet has a collapsed Transcript disclosure that expands to selectable text', async ({ device, screen, app }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await openMoments(screen);
  await tapVisibleCenter(screen.getByText('E2E Second Moment').first());
  await expandSheet(screen);
  // A disclosure label's id reaches both its button and its text, so take the first node.
  const disclosure = screen.getByTestId('moment.transcript').first();
  await screen.scrollUntilVisible(disclosure);
  // Collapsed until asked for.
  const text = screen.getByTestId('moment.transcript.text');
  await expect(text).toBeHidden();
  await tapVisibleCenter(disclosure);
  await screen.scrollUntilVisible(text);
  await expect(text).toBeVisible();
  await expect(text).toContainText('old lighthouse keeper waved us in');
  const copy = screen.getByTestId('moment.transcript.copy');
  await screen.scrollUntilVisible(copy);
  await expect(copy).toBeVisible();
  await tapVisibleCenter(copy);
  await expect(screen.getByRole('button', 'Copied')).toBeVisible();
  expect(execFileSync('xcrun', ['simctl', 'pbpaste', udid()], { encoding: 'utf8', timeout: 30_000 }))
    .toContain('old lighthouse keeper waved us in');
  await app.screenshot('moments-transcript-disclosure');
  await screen.getByRole('button', 'Cancel').tap();
  await expect(screen.getByTestId('moment.done')).toBeHidden();

  // A moment saved without a transcript shows no disclosure.
  await tapVisibleCenter(screen.getByText('E2E First Moment').first());
  await expandSheet(screen);
  await screen.scrollUntilVisible(screen.getByPlaceholder('Add a quote (optional)'));
  await expect(screen.getByTestId('moment.transcript')).toBeHidden();
  await screen.getByRole('button', 'Cancel').tap();
});

test('Share Moment opens the share sheet from the context menu and from the edit sheet', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await openMoments(screen);
  await screen.getByText('E2E Second Moment').first().longPress();
  await screen.getByRole('button', 'Share Moment').tap();
  await expectShareSheetThenDismiss(screen);

  // Editing an existing moment: the toolbar share button.
  await tapVisibleCenter(screen.getByText('E2E Second Moment').first());
  const share = screen.getByTestId('moment.share');
  await expect(share).toBeVisible();
  await tapVisibleCenter(share);
  await expectShareSheetThenDismiss(screen);
  // Dismissing the share sheet leaves the edit sheet open.
  await expect(screen.getByTestId('moment.done')).toBeVisible();
  await screen.getByRole('button', 'Cancel').tap();
  await expect(screen.getByTestId('moment.done')).toBeHidden();
});

test('Export Moments shares the book, and only a book with moments offers it', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  // The control sits at the top of the expanded moments list.
  await screen.getByText(/^\d+ moments?$/).first().tap();
  const exportButton = screen.getByTestId('audiobookDetail.exportMoments');
  await screen.scrollUntilVisible(exportButton);
  await expect(exportButton).toContainText('Export Moments…');
  await tapVisibleCenter(exportButton);
  await expectShareSheetThenDismiss(screen);

  // The default fixture's second book has no moments. Its page has the moments header but no export.
  await tapVisibleCenter(screen.getByTestId('BackButton').first());
  await openAnotherBook(screen);
  await expect(screen.getByTestId('book.progressSummary')).toBeVisible();
  await expect(screen.getByTestId('audiobookDetail.exportMoments')).toBeHidden();
});
