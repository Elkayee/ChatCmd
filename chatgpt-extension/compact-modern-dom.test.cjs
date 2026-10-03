'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { contentFixture } = require('./compact-test-content.cjs');
const { workerFixture } = require('./compact-test-worker.cjs');
const { job, BODY } = require('./compact-test-fixtures.cjs');

function modernUser(env, text, { searchKey = 'fallback-turn-0:0:user', messageIds = 'handoff-user', nested = false } = {}) {
  const outer = env.w.document.createElement('section');
  outer.dataset.chatgptSearchUnitKey = searchKey;
  if (messageIds) outer.dataset.chatgptSearchMessageIds = messageIds;
  const node = nested ? env.w.document.createElement('div') : outer;
  if (nested) {
    node.dataset.messageAuthorRole = 'user';
    outer.append(node);
  }
  node.textContent = text;
  env.w.document.querySelector('main').append(outer);
  return outer;
}

function modernAnswer(env, text = BODY, { searchKey = 'fallback-turn-1:2:assistant', messageIds = 'handoff-answer', style = 'assistant-message' } = {}) {
  const outer = env.w.document.createElement('section');
  outer.dataset.chatgptSearchUnitKey = searchKey;
  if (messageIds) outer.dataset.chatgptSearchMessageIds = messageIds;
  const node = env.w.document.createElement('div');
  if (style) node.dataset.markdownTextStyle = style;
  else node.className = 'markdown';
  node.textContent = text;
  outer.append(node);
  env.w.document.querySelector('main').append(outer);
  return node;
}

test('exact modern-DOM handoff advances worker to opening_new_chat and preserves BODY without extra send', async (t) => {
  const worker = await workerFixture(t);
  const value = worker.seed(job({ phase: 'writing_handoff' }), { sourceSend: 'dispatched-unresolved' });
  const page = contentFixture(t);

  modernUser(page, page.protocol.handoffPrompt(value));
  modernAnswer(page, BODY + '\n' + page.protocol.marker('HANDOFF-END', value.id));
  page.settled(value);

  worker.shared.tabs = [{ id: 1, url: value.oldConversationUrl }];
  worker.shared.route = async (_tabId, message) => {
    if (message.type === 'chatcmd-compact-locate') return { ok: true, markerFound: false };
    return page.message(message.type.replace('chatcmd-compact-', ''), message.job, message.kind, message.documentToken);
  };

  await worker.tick();

  assert.equal(worker.serverJob().handoffText, BODY, 'complete handoff must be saved');
  assert.equal(worker.serverJob().phase, 'opening_new_chat');
  assert.equal(worker.sends('HANDOFF').length, 0, 'no extra send dispatched');
  assert.equal(page.state.clicks, 0);
});

test('modern RESUME turns support locate and probe without resending', async (t) => {
  const page = contentFixture(t, { url: 'https://chatgpt.com/c/new-dest' });
  const value = job({ newConversationId: 'new-dest' });

  modernUser(page, page.protocol.resumePrompt(value), {
    searchKey: 'dest-turn-0:0:user',
    messageIds: 'resume-user-msg',
  });

  const locate = await page.message('locate', value, 'RESUME');
  assert.equal(locate.ok, true);
  assert.equal(locate.markerFound, true);

  const probe = page.probe(value, 'RESUME');
  assert.equal(probe.markerFound, true);
  assert.equal(probe.superseded, false);
  assert.equal(probe.userMessageId, 'resume-user-msg');
});

test('wrong full prompt under modern user root does not confer ownership', (t) => {
  const page = contentFixture(t);
  const value = job();

  modernUser(page, page.protocol.marker('HANDOFF', value.id) + '\nAltered instructions that do not match canonical handoff prompt.');
  modernAnswer(page, BODY + '\n' + page.protocol.marker('HANDOFF-END', value.id));

  const result = page.settled(value);
  assert.equal(result.markerFound, false);
  assert.equal(result.handoffText, null);
});

test('wrong job id under modern user root does not match', (t) => {
  const page = contentFixture(t);
  const value = job();
  const other = { ...value, id: 'other-job-1234' };

  modernUser(page, page.protocol.handoffPrompt(other));
  modernAnswer(page, BODY + '\n' + page.protocol.marker('HANDOFF-END', value.id));

  const result = page.settled(value);
  assert.equal(result.markerFound, false);
  assert.equal(result.handoffText, null);
});

test('mixed modern and legacy duplicate turns fail closed', (t) => {
  const page = contentFixture(t);
  const value = job();

  page.user(page.protocol.handoffPrompt(value), 'legacy-user-id');
  modernUser(page, page.protocol.handoffPrompt(value), {
    searchKey: 'turn-1:0:user',
    messageIds: 'modern-user-id',
  });

  assert.throws(() => page.probe(value), /nhiều tin nhắn|duplicate/i);
});

test('nested mixed wrappers count as one turn and capture successfully', (t) => {
  const page = contentFixture(t);
  const value = job();

  modernUser(page, page.protocol.handoffPrompt(value), {
    searchKey: 'nested-turn-0:0:user',
    messageIds: 'nested-user-id',
    nested: true,
  });
  modernAnswer(page, BODY + '\n' + page.protocol.marker('HANDOFF-END', value.id));

  const result = page.settled(value);
  assert.equal(result.markerFound, true);
  assert.equal(result.handoffText, BODY);
});

test('later modern user turn supersedes owned handoff', (t) => {
  const page = contentFixture(t);
  const value = job();

  modernUser(page, page.protocol.handoffPrompt(value), { searchKey: 'turn-0:0:user' });
  modernAnswer(page, BODY + '\n' + page.protocol.marker('HANDOFF-END', value.id));
  modernUser(page, 'A follow-up question after the handoff was requested.', { searchKey: 'turn-2:0:user' });

  const result = page.settled(value);
  assert.equal(result.markerFound, true);
  assert.equal(result.superseded, true);
  assert.equal(result.handoffText, null);
});

test('compact protocol 3 is treated as stale and protocol 4 as healthy in contentScriptAlive and recovery', async (t) => {
  const worker = await workerFixture(t);
  const value = worker.seed(job({ phase: 'writing_handoff' }), { sourceSend: 'dispatched-unresolved' });
  const page = contentFixture(t);

  modernUser(page, page.protocol.handoffPrompt(value));
  modernAnswer(page, BODY + '\n' + page.protocol.marker('HANDOFF-END', value.id));
  page.settled(value);

  worker.shared.tabs = [{ id: 1, url: value.oldConversationUrl }];

  // Protocol 3 (stale tab) must fail alive check and trigger script injection
  worker.shared.contentHealth = {
    ok: true, kind: 'chatgpt', compactProtocol: 3,
    captureProtocol: 2, clockProtocol: 1, renderProtocol: 1, captureReady: true,
  };

  let reinjected = false;
  worker.shared.onInject = async (tabId) => {
    assert.equal(tabId, 1);
    reinjected = true;
    worker.shared.contentHealth = {
      ok: true, kind: 'chatgpt', compactProtocol: 4,
      captureProtocol: 2, clockProtocol: 1, renderProtocol: 1, captureReady: true,
    };
  };

  worker.shared.route = async (_tabId, message) => {
    if (message.type === 'chatcmd-compact-locate') return { ok: true, markerFound: false };
    return page.message(message.type.replace('chatcmd-compact-', ''), message.job, message.kind, message.documentToken);
  };

  await worker.tick();

  assert.equal(reinjected, true, 'stale protocol 3 tab must trigger reinjection');
  assert.equal(worker.serverJob().handoffText, BODY, 'handoff captured after reinjection');
  assert.equal(worker.serverJob().phase, 'opening_new_chat');
  assert.equal(worker.sends('HANDOFF').length, 0, 'no extra send dispatched on recovery');
});
