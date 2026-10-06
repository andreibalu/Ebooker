import { expect, type Locator } from 'e2e';
import { test as base } from '@e2e-dev/mobile';
import { createAgentDeviceClient } from 'agent-device';
import { NATIVE_WORKER_SESSION } from '../session.js';
import { setTimeout as delay } from 'node:timers/promises';

// Secure fields mask their value, and locator typing refocuses an invalid AX
// reference on this simulator. Type into the already focused native field using
// the same pinned backend/client path as the engine's keyboard.type operation.
export const test = base.extend<{ nativeKeyboard: {
  typeFocusedDummyCredential: () => Promise<void>;
  typeFocusedText: (text: string) => Promise<void>;
  submitFocused: () => Promise<void>;
} }>({
  nativeKeyboard: async (_fixtures, use) => {
    const client = createAgentDeviceClient({ session: NATIVE_WORKER_SESSION });
    await use({
      typeFocusedDummyCredential: async () => {
        await client.interactions.type({ text: 'not-a-real-credential' });
      },
      typeFocusedText: async (text) => {
        await client.interactions.type({ text });
      },
      submitFocused: async () => {
        await client.command.keyboard({ action: 'enter' });
      },
    });
  },
});

/** Expanding the native sheet avoids the slow clipped EQ accessibility tree. */
export async function expandEqualizerSheet(options: { allowVisibleControls?: boolean } = {}): Promise<void> {
  const client = createAgentDeviceClient({ session: NATIVE_WORKER_SESSION });
  const snapshot = await client.capture.snapshot();
  const grabber = snapshot.nodes.find((node) => node.label === 'Sheet Grabber' && node.type === 'Button');
  const box = grabber?.rect;
  if (!box || !grabber.enabled || box.width <= 0 || box.height <= 0) {
    throw new Error('Equalizer sheet has no visible native grabber bounds');
  }
  if (grabber.value == null && options.allowVisibleControls) {
    const root = (snapshot.nodes.find((node) => node.type === 'Application') ?? snapshot.nodes[0])?.rect;
    const required = [
      snapshot.nodes.find((node) => node.identifier === 'equalizer.enabled'),
      snapshot.nodes.find((node) => node.identifier === 'equalizer.preset.voiceBoost'),
    ];
    if (root && required.every((node) => node?.rect && node.rect.width > 0 && node.rect.height > 0 &&
      node.rect.x >= root.x && node.rect.y >= root.y &&
      node.rect.x + node.rect.width <= root.x + root.width &&
      node.rect.y + node.rect.height <= root.y + root.height)) return;
  }
  const isExpanded = (nodes: typeof snapshot.nodes): boolean => {
    const handle = nodes.find((node) => node.label === 'Sheet Grabber' && node.type === 'Button');
    if (handle?.value === 'Expanded') return true;
    // iOS 18 omits the detent value. Its expanded sheet is identifiable from
    // the native grabber at the top quarter of the current application bounds.
    // The private-AX backend exposes the application root as Other on iOS 18.
    const app = (nodes.find((node) => node.type === 'Application') ?? nodes[0])?.rect;
    return handle?.value == null && !!handle?.rect && !!app &&
      handle.rect.y < app.y + app.height / 4;
  };
  if (isExpanded(snapshot.nodes)) return;
  // The semantic wrapper falsely reports covered; this is the observed native
  // grabber center, whose actual native action was independently verified.
  const point = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  if (grabber.value == null) {
    // iOS 18's grabber has no detent value and a tap does not expand it.
    // Drag that observed native handle into the top eighth of the root bounds.
    const root = (snapshot.nodes.find((node) => node.type === 'Application') ?? snapshot.nodes[0])?.rect;
    if (!root) throw new Error('Equalizer native sheet has no application bounds for expansion');
    await client.interactions.pan({
      x: point.x, y: point.y, dx: 0,
      dy: root.y + root.height / 8 - point.y, durationMs: 600,
    });
  } else {
    await client.interactions.press(point);
  }
  // Native sheet spring settling can finish after the gesture command returns.
  const deadline = Date.now() + 3_000;
  let expanded = await client.capture.snapshot();
  while (!isExpanded(expanded.nodes) && Date.now() < deadline) {
    await delay(100);
    expanded = await client.capture.snapshot();
  }
  if (!isExpanded(expanded.nodes)) {
    const after = expanded.nodes.find((node) => node.label === 'Sheet Grabber')?.rect;
    throw new Error(`Equalizer native sheet did not expand: before=${JSON.stringify(box)} after=${JSON.stringify(after)}`);
  }
}

/**
 * The simulator AX ref hit test falsely reports uncovered Settings controls as
 * covered; direct XCTest presses at their current bounds were verified. Use the
 * documented locator position action, deriving the point from a fresh box.
 */
export async function tapVisibleCenter(target: Locator): Promise<void> {
  await expect(target).toBeVisible();
  const box = await target.boundingBox();
  if (!box || box.width <= 0 || box.height <= 0) throw new Error('Visible native control has no actionable bounds');
  await target.tap({ position: { x: box.width / 2, y: box.height / 2 } });
}

/**
 * Long-presses near the top edge of `target`. The mini player overlays the bottom of the last
 * library row, and the locator long-press refuses a target whose center it covers.
 */
export async function longPressVisibleTop(target: Locator): Promise<void> {
  await expect(target).toBeVisible();
  const box = await target.boundingBox();
  if (!box || box.width <= 0 || box.height <= 0) throw new Error('Visible native control has no actionable bounds');
  const client = createAgentDeviceClient({ session: NATIVE_WORKER_SESSION });
  await client.interactions.longPress({ x: box.x + box.width / 2, y: box.y + Math.min(40, box.height / 4), durationMs: 1_000 });
}
