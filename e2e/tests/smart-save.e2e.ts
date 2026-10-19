import { expect, type Screen } from 'e2e';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { test, tapVisibleCenter } from './native-actions.js';
import { bundle, iosMajorVersion } from '../support/simulator.js';
import { ABS_PASSWORD, ABS_USERNAME, startFakeAudiobookshelf } from '../support/fake-audiobookshelf.js';

const fixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];
// The app reads transcript files straight from the host; keep them outside the repo.
const transcriptDir = '/private/tmp/unpaged-e2e-smart-save';

function transcriptFile(name: string, text: string): string {
  mkdirSync(transcriptDir, { recursive: true });
  const path = `${transcriptDir}/${name}.txt`;
  writeFileSync(path, text);
  return path;
}

async function smartSave(screen: Screen, timeout = 30_000) {
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByText('Smart Save Moment').first()).toBeVisible();
  // Smart save needs only a loaded track. On a loaded simulator the fixture audio sometimes
  // never starts, so pause only when it is playing.
  if (await screen.getByRole('button', 'Pause playback').count() > 0) {
    await screen.getByTestId('player.playPause').tap();
  }
  await screen.getByTestId('player.saveMoment').tap();
  await expect(screen.getByTestId('moment.name')).toBeVisible({ timeout });
}

/** The sheet opens at its half-height detent; the cast section sits below that fold. */
async function expandSheet(screen: Screen) {
  const grabber = await screen.getByRole('button', 'Sheet Grabber').boundingBox();
  if (!grabber) throw new Error('Sheet grabber has no bounds');
  const x = grabber.x + grabber.width / 2;
  await screen.swipe({ from: { x, y: grabber.y + grabber.height / 2 }, to: { x, y: 80 } });
}

const letterPassage = 'Elizabeth turned the letter over twice before she opened it. Jane watched her from the window. '
  + '"It is from Mr. Darcy," Elizabeth said at last, and her voice was steady. Elizabeth read it slowly.';

// The owner's bug: about half of saves showed "AI detected content likely to be unsafe" over a
// "Saved Moment" name. A declined passage now opens with a usable name and a calm notice.
test('smart save: a declined passage still gets a name and a calm notice', async ({ app, device, screen }) => {
  const args = [...fixture, '-e2e-moment-analysis', 'declined',
    '-e2e-moment-transcript-file', transcriptFile('letter', letterPassage)];
  await device.openApp(bundle, { relaunch: true, launchArguments: [...args, '-e2e-reset-fixture'] });
  await smartSave(screen);
  // Lead character and current chapter. The chapter is wherever the stalled or playing fixture
  // audio left the player.
  await expect(screen.getByTestId('moment.name')).toHaveValue(/^Elizabeth in E2E Chapter \d$/);
  const name = await screen.getByTestId('moment.name').inputValue();
  await expect(screen.getByTestId('moment.notice')).toContainText("Apple Intelligence couldn't summarize this passage");
  await expect(screen.getByText(/unsafe/).first()).toBeHidden();
  await app.screenshot('smart-save-declined-fallback');
  // The fallback fills the cast from the transcript, so the character filter still works.
  await expandSheet(screen);
  await screen.scrollUntilVisible(screen.getByRole('button', 'Remove Elizabeth'));
  await expect(screen.getByRole('button', 'Remove Elizabeth')).toBeVisible();
  await app.screenshot('smart-save-declined-fallback-cast');
  await expect(screen.getByTestId('moment.done').last()).toBeEnabled();
  await tapVisibleCenter(screen.getByTestId('moment.done').last());
  await expect(screen.getByTestId('moment.done')).toBeHidden();

  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByText(name).first());
  await expect(screen.getByText(name).first()).toBeVisible();
});

// Smart save reads the local file, so a streamed book can't be transcribed. It still gets the
// chapter-and-time name, with a notice that says why, instead of a bare "Saved Moment".
test('smart save: a streamed book gets a chapter name and a download notice', {
  timeout: 300_000,
}, async ({ app, device, screen, nativeKeyboard }) => {
  const server = await startFakeAudiobookshelf();
  try {
    const args = ['-e2e-fixture', '-e2e-online', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO',
      '-shelvesSource', 'librivox', '-e2e-moment-analysis', 'declined'];
    await device.openApp(bundle, { relaunch: true, launchArguments: [...args, '-e2e-reset-fixture'] });
    // The first tap selects Shelves; tapping the selected tab opens its source menu.
    const source = screen.getByRole('button', /Audiobookshelf/);
    for (let attempt = 0; attempt < 4 && !(await source.isVisible()); attempt++) {
      await screen.getByTestId('shelvesTab').tap();
      await expect.poll(() => source.isVisible(), { timeout: 3_000 }).toBe(true).catch(() => undefined);
    }
    await source.tap();
    await screen.getByTestId('abs.connect.server').fill(server.serverURL);
    await screen.getByTestId('abs.connect.username').fill(ABS_USERNAME);
    await screen.getByTestId('abs.connect.username').press('Enter');
    await nativeKeyboard.typeFocusedText(ABS_PASSWORD);
    await nativeKeyboard.submitFocused();
    const hobbit = screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien').first();
    await expect(hobbit).toBeVisible({ timeout: 30_000 });
    await tapVisibleCenter(hobbit);
    await screen.getByTestId('abs.detail.add').tap();
    await expect(screen.getByText('In your Library', { exact: true })).toBeVisible({ timeout: 30_000 });
    await screen.getByTestId('abs.detail.play').tap();
    await expect(screen.getByText('Smart Save Moment').first()).toBeVisible({ timeout: 30_000 });
    await screen.getByTestId('player.saveMoment').tap();

    await expect(screen.getByTestId('moment.name')).toHaveValue(/ at \d+:\d\d$/, { timeout: 30_000 });
    await expect(screen.getByTestId('moment.name')).not.toHaveValue('Saved Moment');
    await expect(screen.getByTestId('moment.notice')).toContainText('Smart naming needs a downloaded book');
    await app.screenshot('smart-save-streamed-book');
    await screen.getByRole('button', 'Cancel').tap();
    await expect(screen.getByTestId('moment.name')).toBeHidden();
  } finally {
    await server.close();
  }
});

// Opt in: needs Apple Intelligence on the host Mac (simulators use its model). Passages come from
// E2E_AI_CORPUS (a JSON array of {id, book, moment}) filtered by E2E_AI_IDS, or one built-in
// passage. E2E_AI_RESULTS receives each name the real model produced.
test('smart save: the on-device model names fiction passages', {
  timeout: 1_800_000,
  skip: process.env.E2E_REAL_MODEL === '1' ? false : 'Set E2E_REAL_MODEL=1 to exercise the on-device model',
}, async ({ app, device, screen }) => {
  expect(iosMajorVersion(), 'the on-device model needs iOS 26 or later').toBeGreaterThanOrEqual(26);
  type Passage = { id: string; book: string; moment: string };
  const ids = (process.env.E2E_AI_IDS ?? '').split(',').filter(Boolean);
  const corpus: Passage[] = process.env.E2E_AI_CORPUS
    ? (JSON.parse(readFileSync(process.env.E2E_AI_CORPUS, 'utf8')) as Passage[]).filter((p) => !ids.length || ids.includes(p.id))
    : [{ id: 'letter', book: 'Pride and Prejudice', moment: letterPassage }];
  const results: { id: string; name: string; notice: boolean }[] = [];
  let reset = true;
  for (const passage of corpus) {
    const args = [...fixture, '-e2e-moment-transcript-file', transcriptFile(passage.id, passage.moment)];
    await device.openApp(bundle, { relaunch: true, launchArguments: reset ? [...args, '-e2e-reset-fixture'] : args });
    reset = false;
    await smartSave(screen, 60_000);
    const name = await screen.getByTestId('moment.name').inputValue();
    const notice = await screen.getByTestId('moment.notice').count() > 0;
    results.push({ id: passage.id, name, notice });
    if (results.length === 1) await app.screenshot('smart-save-real-model');
    await screen.getByRole('button', 'Cancel').tap();
    await expect(screen.getByTestId('moment.name')).toBeHidden();
  }
  if (process.env.E2E_AI_RESULTS) writeFileSync(process.env.E2E_AI_RESULTS, JSON.stringify(results, null, 1));
  for (const result of results) {
    expect(result.notice, `${result.id} fell back: ${result.name}`).toBe(false);
    expect(result.name).not.toBe('Saved Moment');
  }
});
