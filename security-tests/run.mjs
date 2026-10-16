// Security-rule tests for firestore.rules and storage.rules.
//
// Run from anywhere:
//   npm --prefix security-tests install
//   npm --prefix security-tests test
//
// The project id starts with "demo-", so the emulator needs no Firebase login and
// touches no real data. Every case below asserts what firestore.rules promises:
// participants only, self-authored messages, forward-only status, sender-only
// delete, and validated fields/sizes.
//
// Needs a JDK (the Firestore emulator is a Java jar). firebase-tools 15 wants
// Java 21, so this package pins 13.x, which still runs on Java 17.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  arrayUnion,
  collection,
  deleteDoc,
  doc,
  getCountFromServer,
  getDoc,
  getDocs,
  increment,
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  startAt,
  endAt,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';
import { getDownloadURL, ref, uploadBytes } from 'firebase/storage';

const ALICE = 'alice';
const BOB = 'bob';
const MALLORY = 'mallory';

const conversationId = (a, b) => {
  const members = [a, b].sort();
  return `${members[0].length}_${members[0]}${members[1]}`;
};
const CONVERSATION = conversationId(ALICE, BOB);

// A thread that does not exist yet, used by the create tests.
const newId = conversationId(ALICE, MALLORY);

const validMessage = {
  senderId: ALICE,
  recipientId: BOB,
  clientId: 'msg1',
  content: 'ahlan',
  mediaUrl: null,
  createdAt: Timestamp.now(),
  status: 'sent',
};

const profile = (uid) => ({
  id: uid,
  username: uid,
  usernameLowercase: uid,
  fullName: `Test ${uid}`,
  avatarUrl: null,
  bio: '',
  ageGroup: 'adult',
  createdAt: Timestamp.now(),
});

// Everyone the earlier sections seed was born in 1990, so they are all adults.

let passed = 0;
const failures = [];

async function check(name, body) {
  try {
    await body();
    passed += 1;
    console.log(`  ok   ${name}`);
  } catch (error) {
    failures.push(`${name}: ${error?.message ?? error}`);
    console.log(`  FAIL ${name}`);
    console.log(`       ${error?.message ?? error}`);
  }
}

const testEnv = await initializeTestEnvironment({
  projectId: 'demo-mixsay',
  firestore: {
    // Resolved from this file, so the working directory does not matter.
    rules: readFileSync(fileURLToPath(new URL('../firestore.rules', import.meta.url)), 'utf8'),
    host: '127.0.0.1',
    port: 8080,
  },
  storage: {
    rules: readFileSync(fileURLToPath(new URL('../storage.rules', import.meta.url)), 'utf8'),
    host: '127.0.0.1',
    port: 9199,
  },
});

/** A verified, eligible account. email_verified is a token claim in real life. */
const user = (uid) => testEnv.authenticatedContext(uid, { email_verified: true });
const db = (uid) => user(uid).firestore();

/** Seeds data that the rules themselves would not let a client write. */
async function seed() {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const store = context.firestore();
    const members = [ALICE, BOB];
    for (const uid of [...members, MALLORY]) {
      await setDoc(doc(store, 'users', uid), {
        birthDate: Timestamp.fromDate(new Date('1990-05-05')),
        createdAt: Timestamp.now(),
      });
      await setDoc(doc(store, 'publicProfiles', uid), profile(uid));
    }
    await setDoc(doc(store, 'conversations', CONVERSATION), {
      members,
      participants: {
        [ALICE]: {
          username: ALICE,
          fullName: `Test ${ALICE}`,
          avatarUrl: null,
        },
        [BOB]: {
          username: BOB,
          fullName: `Test ${BOB}`,
          avatarUrl: null,
        },
      },
      lastMessageContent: 'ahlan',
      lastMessageAt: Timestamp.now(),
      unreadCounts: { [ALICE]: 0, [BOB]: 1 },
      createdAt: Timestamp.now(),
    });
    await setDoc(doc(store, 'conversations', CONVERSATION, 'messages', 'msg1'), {
      ...validMessage,
    });
    await setDoc(doc(store, 'conversations', CONVERSATION, 'messages', 'msg2'), {
      ...validMessage,
      senderId: BOB,
      recipientId: ALICE,
      clientId: 'msg2',
      status: 'delivered',
    });
    await setDoc(doc(store, 'posts', 'post1'), {
      authorId: ALICE,
      username: ALICE,
      fullName: `Test ${ALICE}`,
      avatarUrl: null,
      caption: 'hello',
      mediaUrl: null,
      mediaType: 'none',
      likesCount: 1,
      commentsCount: 0,
      createdAt: Timestamp.now(),
    });
    await setDoc(doc(store, 'notifications', 'note1'), {
      recipientId: ALICE,
      actorId: BOB,
      type: 'like',
      postId: 'post1',
      isRead: false,
      createdAt: Timestamp.now(),
    });
    await setDoc(doc(store, 'usernames', ALICE), { uid: ALICE });
  });
}

const messageRef = (uid, messageId) =>
  doc(db(uid), 'conversations', CONVERSATION, 'messages', messageId);

await seed();

console.log('\nidentity and eligibility');
await check('anonymous reads are refused', async () => {
  await assertFails(getDoc(doc(testEnv.unauthenticatedContext().firestore(), 'conversations', CONVERSATION)));
});
await check('an unverified account is refused', async () => {
  const context = testEnv.authenticatedContext(ALICE, { email_verified: false });
  await assertFails(getDoc(doc(context.firestore(), 'conversations', CONVERSATION)));
});
await check('a user without a users/ document is refused', async () => {
  await assertFails(getDoc(messageRef(MALLORY, 'msg1')));
});
await check('a member can read their conversation', async () => {
  await assertSucceeds(getDoc(doc(db(ALICE), 'conversations', CONVERSATION)));
});
await check('an outsider cannot read the conversation', async () => {
  await assertFails(getDoc(doc(db(MALLORY), 'conversations', CONVERSATION)));
});

console.log('\nconversation list paging');
await check('a member can list their conversations with limit(50)', async () => {
  await assertSucceeds(
    getDocs(
      query(
        collection(db(ALICE), 'conversations'),
        where('members', 'array-contains', ALICE),
        limit(50),
      ),
    ),
  );
});
await check('listing more than 50 conversations is refused', async () => {
  await assertFails(
    getDocs(
      query(
        collection(db(ALICE), 'conversations'),
        where('members', 'array-contains', ALICE),
        limit(51),
      ),
    ),
  );
});
await check('listing conversations without a limit is refused', async () => {
  await assertFails(
    getDocs(
      query(
        collection(db(ALICE), 'conversations'),
        where('members', 'array-contains', ALICE),
      ),
    ),
  );
});
await check('an outsider cannot list other people threads', async () => {
  // Rules are not filters: a query that reaches documents the caller may not
  // read is refused outright, so a stranger cannot page through threads.
  await assertFails(
    getDocs(query(collection(db(MALLORY), 'conversations'), limit(50))),
  );
});
await check('an outsider filtering by their own membership gets nothing', async () => {
  const snapshot = await assertSucceeds(
    getDocs(
      query(
        collection(db(MALLORY), 'conversations'),
        where('members', 'array-contains', MALLORY),
        limit(50),
      ),
    ),
  );
  if (snapshot.size !== 0) {
    throw new Error(`A stranger was handed ${snapshot.size} thread(s).`);
  }
});

console.log('\nmessages: read');
await check('a participant can read the thread', async () => {
  await assertSucceeds(getDoc(messageRef(ALICE, 'msg1')));
});
await check('a participant can list the thread with limit(100)', async () => {
  await assertSucceeds(
    getDocs(
      query(collection(db(BOB), 'conversations', CONVERSATION, 'messages'), limit(100)),
    ),
  );
});
await check('listing a thread without a limit is refused', async () => {
  await assertFails(
    getDocs(query(collection(db(BOB), 'conversations', CONVERSATION, 'messages'))),
  );
});
await check('listing more than 100 messages is refused', async () => {
  await assertFails(
    getDocs(
      query(collection(db(BOB), 'conversations', CONVERSATION, 'messages'), limit(101)),
    ),
  );
});
await check('a non-participant cannot read the thread', async () => {
  await assertFails(getDoc(messageRef(MALLORY, 'msg1')));
});

console.log('\nmessages: create');
await check('the sender can create a well-formed message', async () => {
  await assertSucceeds(
    setDoc(messageRef(ALICE, 'msg9'), { ...validMessage, clientId: 'msg9' }),
  );
});
await check('writing as somebody else is refused', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'msg9'), {
      ...validMessage,
      clientId: 'msg9',
      senderId: BOB,
    }),
  );
});
await check('a message addressed to the sender is refused', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'msg9'), {
      ...validMessage,
      clientId: 'msg9',
      recipientId: ALICE,
    }),
  );
});
await check('a message without recipientId is refused', async () => {
  const { recipientId, ...withoutRecipient } = validMessage;
  await assertFails(
    setDoc(messageRef(ALICE, 'msg9'), {
      ...withoutRecipient,
      clientId: 'msg9',
    }),
  );
});
await check('a document id that is not the clientId is refused', async () => {
  await assertFails(setDoc(messageRef(ALICE, 'msg9'), validMessage));
});
await check('content longer than 4000 characters is refused', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'msg9'), {
      ...validMessage,
      clientId: 'msg9',
      content: 'a'.repeat(4001),
    }),
  );
});
await check('an empty message without media is refused', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'msg9'), {
      ...validMessage,
      clientId: 'msg9',
      content: '',
    }),
  );
});
await check('an unknown field is refused', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'msg9'), {
      ...validMessage,
      clientId: 'msg9',
      editedAt: Timestamp.now(),
    }),
  );
});
await check('creating a message that is already read is refused', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'msg9'), {
      ...validMessage,
      clientId: 'msg9',
      status: 'read',
    }),
  );
});
await check('a non-participant cannot write into the thread', async () => {
  await assertFails(
    setDoc(messageRef(MALLORY, 'msg9'), {
      ...validMessage,
      clientId: 'msg9',
      senderId: MALLORY,
      recipientId: ALICE,
    }),
  );
});

await seed();
console.log('\nmessages: status transitions');
await check('the receiver may mark sent -> delivered', async () => {
  await assertSucceeds(updateDoc(messageRef(BOB, 'msg1'), { status: 'delivered' }));
});
await check('the receiver may mark sent -> read', async () => {
  await assertSucceeds(updateDoc(messageRef(BOB, 'msg1'), { status: 'read' }));
});
await check('the receiver may mark delivered -> read', async () => {
  await assertSucceeds(updateDoc(messageRef(ALICE, 'msg2'), { status: 'read' }));
});
await check('the sender cannot change the status of their own message', async () => {
  await assertFails(updateDoc(messageRef(ALICE, 'msg1'), { status: 'read' }));
});
await check('status cannot move backwards', async () => {
  await assertFails(updateDoc(messageRef(ALICE, 'msg2'), { status: 'sent' }));
});
await check('status cannot jump to an unknown value', async () => {
  await assertFails(updateDoc(messageRef(BOB, 'msg1'), { status: 'archived' }));
});
await check('message content cannot be edited', async () => {
  await assertFails(updateDoc(messageRef(BOB, 'msg1'), { content: 'rewritten' }));
});
await check('an outsider cannot mark anything read', async () => {
  await assertFails(updateDoc(messageRef(MALLORY, 'msg1'), { status: 'read' }));
});

await seed();
console.log('\nmessages: delete');
await check('the sender can delete their own message', async () => {
  await assertSucceeds(deleteDoc(messageRef(ALICE, 'msg1')));
});
await check('the receiver cannot delete a message they did not send', async () => {
  // msg2 is bob's message; alice only receives it.
  await assertFails(deleteDoc(messageRef(ALICE, 'msg2')));
});
await check('an outsider cannot delete it', async () => {
  await assertFails(deleteDoc(messageRef(MALLORY, 'msg2')));
});

await seed();
console.log('\nmessages: typed payloads');
const ownPath = (uid, name) => `chats/${CONVERSATION}/${uid}/${name}`;
const withType = (messageId, type, extra) => ({
  ...validMessage,
  clientId: messageId,
  content: '',
  type,
  ...extra,
});
// Each accepted write needs its own document id: the first check in a seeded
// generation creates it, and a later setDoc on the same id would be tested as
// an update instead of a create.
await check('an image message pointing at the sender own upload is accepted', async () => {
  await assertSucceeds(
    setDoc(
      messageRef(ALICE, 'm-image'),
      withType('m-image', 'image', { mediaUrl: ownPath(ALICE, 'm-image.jpg') }),
    ),
  );
});
await check('an image message pointing at another sender folder is refused', async () => {
  await assertFails(
    setDoc(
      messageRef(ALICE, 'm-image-others'),
      withType('m-image-others', 'image', {
        mediaUrl: ownPath(BOB, 'm-image-others.jpg'),
      }),
    ),
  );
});
await check('a video message is accepted', async () => {
  await assertSucceeds(
    setDoc(
      messageRef(ALICE, 'm-video'),
      withType('m-video', 'video', {
        mediaUrl: ownPath(ALICE, 'm-video.mp4'),
        thumbUrl: ownPath(ALICE, 'm-video_thumb.jpg'),
        durationMs: 42,
        fileSize: 8 * 1024 * 1024,
      }),
    ),
  );
});
await check('a voice message is accepted', async () => {
  await assertSucceeds(
    setDoc(
      messageRef(ALICE, 'm-voice'),
      withType('m-voice', 'voice', {
        mediaUrl: ownPath(ALICE, 'm-voice.m4a'),
        durationMs: 4000,
        fileSize: 200 * 1024,
      }),
    ),
  );
});
await check('a file message is accepted', async () => {
  await assertSucceeds(
    setDoc(
      messageRef(ALICE, 'm-file'),
      withType('m-file', 'file', {
        mediaUrl: ownPath(ALICE, 'report.pdf'),
        fileName: 'report.pdf',
        fileSize: 1024 * 1024,
      }),
    ),
  );
});
await check('a bundled sticker is accepted without any upload', async () => {
  await assertSucceeds(
    setDoc(
      messageRef(ALICE, 'm-sticker'),
      withType('m-sticker', 'sticker', { stickerId: 'starter:cat' }),
    ),
  );
});
await check('a sticker with no id is refused', async () => {
  await assertFails(
    setDoc(
      messageRef(ALICE, 'm-sticker-bare'),
      withType('m-sticker-bare', 'sticker'),
    ),
  );
});
await check('a gif may only point at an external url', async () => {
  await assertSucceeds(
    setDoc(
      messageRef(ALICE, 'm-gif'),
      withType('m-gif', 'gif', { mediaUrl: 'https://tenor.example/cat.gif' }),
    ),
  );
  await assertFails(
    setDoc(
      messageRef(ALICE, 'm-gif-local'),
      withType('m-gif-local', 'gif', { mediaUrl: ownPath(ALICE, 'cat.gif') }),
    ),
  );
});
await check('an unknown message type is refused', async () => {
  await assertFails(
    setDoc(
      messageRef(ALICE, 'm-unknown'),
      withType('m-unknown', 'location', { mediaUrl: null }),
    ),
  );
});
await check('a text message carrying media is refused', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'm-text-media'), {
      ...validMessage,
      clientId: 'm-text-media',
      mediaUrl: ownPath(ALICE, 'm-text-media.jpg'),
    }),
  );
});
await check('a file over its per-type ceiling is refused', async () => {
  await assertFails(
    setDoc(
      messageRef(ALICE, 'm-voice-heavy'),
      withType('m-voice-heavy', 'voice', {
        mediaUrl: ownPath(ALICE, 'm-voice-heavy.m4a'),
        fileSize: 9 * 1024 * 1024,
      }),
    ),
  );
});
await check('a voice message longer than ten minutes is refused', async () => {
  await assertFails(
    setDoc(
      messageRef(ALICE, 'm-voice-long'),
      withType('m-voice-long', 'voice', {
        mediaUrl: ownPath(ALICE, 'm-voice-long.m4a'),
        durationMs: 900000,
      }),
    ),
  );
});

await seed();
console.log('\nmessages: forwarded copies');
// A forward is a copy of the payload with no file of its own, so the only thing
// it adds to a document is the label. These checks hold that line: the label is
// accepted where a copy is honest, and buys nothing where it is not.
await check('a forwarded text copy is accepted', async () => {
  await assertSucceeds(
    setDoc(messageRef(ALICE, 'f-text'), {
      ...validMessage,
      clientId: 'f-text',
      forwarded: true,
    }),
  );
});
await check('a forwarded sticker still travels by reference', async () => {
  await assertSucceeds(
    setDoc(
      messageRef(ALICE, 'f-sticker'),
      {
        ...withType('f-sticker', 'sticker', { stickerId: 'starter:cat' }),
        forwarded: true,
      },
    ),
  );
});
await check('a forwarded gif keeps its external url', async () => {
  await assertSucceeds(
    setDoc(
      messageRef(ALICE, 'f-gif'),
      {
        ...withType('f-gif', 'gif', {
          mediaUrl: 'https://tenor.example/cat.gif',
        }),
        forwarded: true,
      },
    ),
  );
});
await check('claiming to be a copy does not open another chat folder', async () => {
  await assertFails(
    setDoc(
      messageRef(ALICE, 'f-steal'),
      {
        ...withType('f-steal', 'image', {
          mediaUrl: `chats/${newId}/${ALICE}/f-steal.jpg`,
        }),
        forwarded: true,
      },
    ),
  );
});
await check('a forwarded label that is not a boolean is refused', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'f-word'), {
      ...validMessage,
      clientId: 'f-word',
      forwarded: 'yes',
    }),
  );
});
await check('the forwarded label cannot be stuck on afterwards', async () => {
  await assertFails(
    updateDoc(messageRef(ALICE, 'msg1'), { forwarded: true }),
  );
});

await seed();
console.log('\nmessages: replies and hiding');
await check('a reply quoting a message is accepted', async () => {
  await assertSucceeds(
    setDoc(messageRef(ALICE, 'msg9'), {
      ...validMessage,
      clientId: 'msg9',
      replyTo: { messageId: 'msg2', senderId: BOB, content: 'ahlan', type: 'text' },
    }),
  );
});
await check('a reply quote longer than 300 characters is refused', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'msg10'), {
      ...validMessage,
      clientId: 'msg10',
      replyTo: {
        messageId: 'msg2',
        senderId: BOB,
        content: 'a'.repeat(301),
        type: 'text',
      },
    }),
  );
});
await check('a reply without a type is refused', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'msg11'), {
      ...validMessage,
      clientId: 'msg11',
      replyTo: { messageId: 'msg2', senderId: BOB, content: 'ahlan' },
    }),
  );
});
await check('a reply naming an unknown message type is refused', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'msg12'), {
      ...validMessage,
      clientId: 'msg12',
      replyTo: { messageId: 'msg2', senderId: BOB, content: 'ahlan', type: 'voice_note' },
    }),
  );
});
await check('either member can hide a message from themself', async () => {
  await assertSucceeds(
    updateDoc(messageRef(ALICE, 'msg1'), {
      deletedFor: arrayUnion(ALICE),
    }),
  );
  await assertSucceeds(
    updateDoc(messageRef(BOB, 'msg1'), { deletedFor: arrayUnion(BOB) }),
  );
});
await check('hiding a message cannot hide it from somebody else', async () => {
  await assertFails(
    updateDoc(messageRef(ALICE, 'msg1'), { deletedFor: arrayUnion(BOB) }),
  );
  await assertFails(
    updateDoc(messageRef(ALICE, 'msg1'), { deletedFor: arrayUnion(MALLORY) }),
  );
});
await check('hiding a message cannot undo an earlier hide', async () => {
  // ALICE has already hidden msg1, so a second hide for her is a no-op and is
  // refused; so is any write that drops a hide or swaps in the other member.
  await assertFails(
    updateDoc(messageRef(ALICE, 'msg1'), { deletedFor: arrayUnion(ALICE) }),
  );
  await assertSucceeds(
    updateDoc(messageRef(ALICE, 'msg2'), { deletedFor: arrayUnion(ALICE) }),
  );
  await assertFails(updateDoc(messageRef(ALICE, 'msg2'), { deletedFor: [] }));
  await assertFails(
    updateDoc(messageRef(ALICE, 'msg2'), { deletedFor: [BOB] }),
  );
});
await check('hiding and read receipts are separate writes', async () => {
  // The rules let one write change either the status or the hide list, never
  // both, so ChatRepository marks read and hides for me as two updates.
  await assertSucceeds(
    setDoc(messageRef(ALICE, 'msg17'), {
      ...validMessage,
      clientId: 'msg17',
    }),
  );
  await assertFails(
    updateDoc(messageRef(BOB, 'msg17'), {
      status: 'delivered',
      deletedFor: arrayUnion(BOB),
    }),
  );
  await assertSucceeds(
    updateDoc(messageRef(BOB, 'msg17'), { status: 'delivered' }),
  );
  await assertSucceeds(
    updateDoc(messageRef(BOB, 'msg17'), { deletedFor: arrayUnion(BOB) }),
  );
});
await check('the sender can delete a message for everyone', async () => {
  await assertSucceeds(
    updateDoc(messageRef(ALICE, 'msg1'), { deletedForEveryone: true }),
  );
});
await check('the receiver cannot delete for everyone', async () => {
  await assertFails(
    updateDoc(messageRef(BOB, 'msg1'), { deletedForEveryone: true }),
  );
});
await check('delete for everyone cannot be written twice or combined', async () => {
  // The previous check already hid msg1 from everyone.
  await assertFails(
    updateDoc(messageRef(ALICE, 'msg1'), { deletedForEveryone: true }),
  );
  await assertFails(
    updateDoc(messageRef(ALICE, 'msg2'), {
      deletedForEveryone: true,
      content: 'rewritten',
    }),
  );
  // BOB owns msg2, so he gets exactly one such write.
  await assertSucceeds(
    updateDoc(messageRef(BOB, 'msg2'), { deletedForEveryone: true }),
  );
  await assertFails(
    updateDoc(messageRef(BOB, 'msg2'), { deletedForEveryone: true }),
  );
});
await check('a new message cannot be born deleted for everyone', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'msg13'), {
      ...validMessage,
      clientId: 'msg13',
      deletedForEveryone: true,
    }),
  );
});
await check('a new message cannot arrive already hidden', async () => {
  await assertFails(
    setDoc(messageRef(ALICE, 'msg14'), {
      ...validMessage,
      clientId: 'msg14',
      deletedFor: [MALLORY],
    }),
  );
  await assertFails(
    setDoc(messageRef(ALICE, 'msg15'), {
      ...validMessage,
      clientId: 'msg15',
      deletedFor: [ALICE],
    }),
  );
  await assertFails(
    setDoc(messageRef(ALICE, 'msg16'), {
      ...validMessage,
      clientId: 'msg16',
      deletedFor: [BOB],
    }),
  );
});

await seed();
console.log('\nconversations: typing and preview metadata');
const conversationRef = (uid) => doc(db(uid), 'conversations', CONVERSATION);
await check('a member can set their own typing flag', async () => {
  await assertSucceeds(updateDoc(conversationRef(ALICE), { 'typing.alice': true }));
});
await check('a member cannot set the other side typing flag', async () => {
  await assertSucceeds(updateDoc(conversationRef(ALICE), { 'typing.alice': true }));
  await assertFails(updateDoc(conversationRef(ALICE), { 'typing.bob': true }));
});
await check('typing may only hold booleans', async () => {
  await assertFails(updateDoc(conversationRef(ALICE), { 'typing.alice': 'yes' }));
});
await check('typing may not name a stranger', async () => {
  await assertFails(updateDoc(conversationRef(ALICE), { 'typing.mallory': true }));
});
await check('an outsider cannot write typing at all', async () => {
  await assertFails(updateDoc(conversationRef(MALLORY), { 'typing.mallory': true }));
});
await check('the preview may record the message type and its author', async () => {
  await assertSucceeds(
    updateDoc(conversationRef(ALICE), {
      lastMessageContent: null,
      lastMessageAt: Timestamp.now(),
      lastMessageType: 'image',
      lastSenderId: ALICE,
    }),
  );
});
await check('an unknown preview type is refused', async () => {
  await assertFails(
    updateDoc(conversationRef(ALICE), { lastMessageType: 'audio_link' }),
  );
});
await check('the preview author must be a member', async () => {
  await assertFails(
    updateDoc(conversationRef(ALICE), { lastSenderId: MALLORY }),
  );
});
await check('a new conversation may start with an empty typing map', async () => {
  await assertSucceeds(
    setDoc(doc(db(ALICE), 'conversations', newId), {
      members: [ALICE, MALLORY].sort(),
      participants: {
        [ALICE]: { username: ALICE, fullName: `Test ${ALICE}`, avatarUrl: null },
        [MALLORY]: {
          username: MALLORY,
          fullName: `Test ${MALLORY}`,
          avatarUrl: null,
        },
      },
      lastMessageContent: null,
      lastMessageAt: null,
      unreadCounts: { [ALICE]: 0, [MALLORY]: 0 },
      typing: { [ALICE]: false, [MALLORY]: false },
      createdAt: Timestamp.now(),
    }),
  );
});
await check('a new conversation cannot claim a message already arrived', async () => {
  await assertFails(
    setDoc(doc(db(ALICE), 'conversations', newId), {
      members: [ALICE, MALLORY].sort(),
      participants: {
        [ALICE]: { username: ALICE, fullName: `Test ${ALICE}`, avatarUrl: null },
        [MALLORY]: {
          username: MALLORY,
          fullName: `Test ${MALLORY}`,
          avatarUrl: null,
        },
      },
      lastMessageContent: null,
      lastMessageAt: null,
      lastMessageType: 'image',
      unreadCounts: { [ALICE]: 0, [MALLORY]: 0 },
      createdAt: Timestamp.now(),
    }),
  );
});

await seed();
console.log('\nconversation counters');
await check('a member can raise the other side by one', async () => {
  await assertSucceeds(
    updateDoc(doc(db(ALICE), 'conversations', CONVERSATION), {
      'unreadCounts.bob': 2,
      lastMessageContent: 'hi',
      lastMessageAt: Timestamp.now(),
    }),
  );
});
await check('raising the other side by two is refused', async () => {
  await assertFails(
    updateDoc(doc(db(ALICE), 'conversations', CONVERSATION), {
      'unreadCounts.bob': 5,
    }),
  );
});
await check('a member can zero their own counter', async () => {
  await assertSucceeds(
    updateDoc(doc(db(BOB), 'conversations', CONVERSATION), {
      'unreadCounts.bob': 0,
    }),
  );
});
await check('a member cannot raise their own counter', async () => {
  await assertFails(
    updateDoc(doc(db(ALICE), 'conversations', CONVERSATION), {
      'unreadCounts.alice': 3,
    }),
  );
});
await check('members cannot be rewritten', async () => {
  await assertFails(
    updateDoc(doc(db(ALICE), 'conversations', CONVERSATION), {
      members: [ALICE, MALLORY],
    }),
  );
});
await check('a conversation can never be deleted by a client', async () => {
  await assertFails(deleteDoc(doc(db(ALICE), 'conversations', CONVERSATION)));
});

await seed();
console.log('\ncreating conversations');
await check('a member can open a conversation with a valid profile copy', async () => {
  await assertSucceeds(
    setDoc(doc(db(ALICE), 'conversations', newId), {
      members: [ALICE, MALLORY].sort(),
      participants: {
        [ALICE]: { username: ALICE, fullName: `Test ${ALICE}`, avatarUrl: null },
        [MALLORY]: {
          username: MALLORY,
          fullName: `Test ${MALLORY}`,
          avatarUrl: null,
        },
      },
      lastMessageContent: null,
      lastMessageAt: null,
      unreadCounts: { [ALICE]: 0, [MALLORY]: 0 },
      createdAt: Timestamp.now(),
    }),
  );
});
await check('the deterministic id formula is enforced', async () => {
  await assertFails(
    setDoc(doc(db(ALICE), 'conversations', 'whatever'), {
      members: [ALICE, MALLORY].sort(),
      participants: {
        [ALICE]: { username: ALICE, fullName: `Test ${ALICE}`, avatarUrl: null },
        [MALLORY]: {
          username: MALLORY,
          fullName: `Test ${MALLORY}`,
          avatarUrl: null,
        },
      },
      lastMessageContent: null,
      lastMessageAt: null,
      unreadCounts: { [ALICE]: 0, [MALLORY]: 0 },
      createdAt: Timestamp.now(),
    }),
  );
});
await check('a participant snapshot that is not their profile is refused', async () => {
  await assertFails(
    setDoc(doc(db(ALICE), 'conversations', newId), {
      members: [ALICE, MALLORY].sort(),
      participants: {
        [ALICE]: { username: 'nobody', fullName: 'Fake', avatarUrl: null },
        [MALLORY]: {
          username: MALLORY,
          fullName: `Test ${MALLORY}`,
          avatarUrl: null,
        },
      },
      lastMessageContent: null,
      lastMessageAt: null,
      unreadCounts: { [ALICE]: 0, [MALLORY]: 0 },
      createdAt: Timestamp.now(),
    }),
  );
});
await check('a conversation must have exactly two members', async () => {
  await assertFails(
    setDoc(doc(db(ALICE), 'conversations', conversationId(ALICE, BOB)), {
      members: [ALICE, BOB, MALLORY].sort(),
      participants: {},
      lastMessageContent: null,
      lastMessageAt: null,
      unreadCounts: {},
      createdAt: Timestamp.now(),
    }),
  );
});

await seed();
console.log('\nposts, likes, comments, notifications');
await check('any verified user can read a post', async () => {
  await assertSucceeds(getDoc(doc(db(MALLORY), 'posts', 'post1')));
});
await check('a like document must be keyed by the liker', async () => {
  await assertSucceeds(
    setDoc(doc(db(BOB), 'posts', 'post1', 'likes', BOB), {
      authorId: BOB,
      username: BOB,
      createdAt: serverTimestamp(),
    }),
  );
});
await check('liking under someone else id is refused', async () => {
  await assertFails(
    setDoc(doc(db(BOB), 'posts', 'post1', 'likes', ALICE), {
      authorId: ALICE,
      username: ALICE,
      createdAt: serverTimestamp(),
    }),
  );
});
await check('only my own like is readable', async () => {
  await assertSucceeds(getDoc(doc(db(BOB), 'posts', 'post1', 'likes', BOB)));
  await assertFails(getDoc(doc(db(MALLORY), 'posts', 'post1', 'likes', BOB)));
});
await check('an existing like cannot be rewritten', async () => {
  await assertFails(
    setDoc(doc(db(BOB), 'posts', 'post1', 'likes', BOB), {
      authorId: BOB,
      username: BOB,
      createdAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(db(BOB), 'posts', 'post1', 'likes', BOB), {
      username: 'hacked',
    }),
  );
});
await check('the liker can undo their like', async () => {
  await assertSucceeds(deleteDoc(doc(db(BOB), 'posts', 'post1', 'likes', BOB)));
  await assertFails(
    deleteDoc(doc(db(MALLORY), 'posts', 'post1', 'likes', BOB)),
  );
});
await check('a like must carry only authorId, username, createdAt', async () => {
  await assertFails(
    setDoc(doc(db(MALLORY), 'posts', 'post1', 'likes', MALLORY), {
      authorId: MALLORY,
      username: MALLORY,
      createdAt: serverTimestamp(),
      extra: 1,
    }),
  );
});
await check('a like cannot claim someone else profile', async () => {
  await assertFails(
    setDoc(doc(db(MALLORY), 'posts', 'post1', 'likes', MALLORY), {
      authorId: MALLORY,
      username: ALICE,
      createdAt: serverTimestamp(),
    }),
  );
});
await check('a comment is capped at 1000 characters', async () => {
  await assertFails(
    setDoc(doc(db(BOB), 'posts', 'post1', 'comments', 'c1'), {
      authorId: BOB,
      username: BOB,
      content: 'b'.repeat(1001),
      createdAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    setDoc(doc(db(BOB), 'posts', 'post1', 'comments', 'c1'), {
      authorId: BOB,
      username: BOB,
      content: 'nice',
      createdAt: serverTimestamp(),
    }),
  );
});
await check('commenting as someone else is refused', async () => {
  await assertFails(
    setDoc(doc(db(BOB), 'posts', 'post1', 'comments', 'c2'), {
      authorId: ALICE,
      username: ALICE,
      content: 'nice',
      createdAt: serverTimestamp(),
    }),
  );
});
await check('an empty comment is refused', async () => {
  await assertFails(
    setDoc(doc(db(BOB), 'posts', 'post1', 'comments', 'c3'), {
      authorId: BOB,
      username: BOB,
      content: '',
      createdAt: serverTimestamp(),
    }),
  );
});
await check('a comment cannot be edited or deleted', async () => {
  await assertFails(
    updateDoc(doc(db(BOB), 'posts', 'post1', 'comments', 'c1'), {
      content: 'edited',
    }),
  );
  await assertFails(deleteDoc(doc(db(BOB), 'posts', 'post1', 'comments', 'c1')));
});
await check('counters move by one at most', async () => {
  // FeedRepository.toggleLike/addComment use FieldValue.increment(1), which is
  // what the rule is written against.
  await assertSucceeds(
    updateDoc(doc(db(BOB), 'posts', 'post1'), {
      likesCount: increment(1),
    }),
  );
  await assertSucceeds(
    updateDoc(doc(db(BOB), 'posts', 'post1'), {
      likesCount: increment(-1),
    }),
  );
  await assertFails(
    updateDoc(doc(db(BOB), 'posts', 'post1'), { likesCount: 99 }),
  );
  await assertFails(
    updateDoc(doc(db(BOB), 'posts', 'post1'), {
      likesCount: increment(2),
      commentsCount: increment(2),
    }),
  );
});
await check('a post caption cannot be rewritten', async () => {
  await assertFails(
    updateDoc(doc(db(ALICE), 'posts', 'post1'), { caption: 'changed' }),
  );
});
await check('only the author can delete a post', async () => {
  await assertFails(deleteDoc(doc(db(BOB), 'posts', 'post1')));
  await assertSucceeds(deleteDoc(doc(db(ALICE), 'posts', 'post1')));
});
await check('the recipient can mark a notification read', async () => {
  await assertSucceeds(
    updateDoc(doc(db(ALICE), 'notifications', 'note1'), { isRead: true }),
  );
});
await check('marking someone else notification is refused', async () => {
  await assertFails(
    updateDoc(doc(db(BOB), 'notifications', 'note1'), { isRead: true }),
  );
});
await check('a notification cannot be un-read', async () => {
  await assertFails(
    updateDoc(doc(db(ALICE), 'notifications', 'note1'), { isRead: false }),
  );
});
await check('clients cannot forge notifications', async () => {
  await assertFails(
    setDoc(doc(db(ALICE), 'notifications', 'note2'), {
      recipientId: ALICE,
      actorId: BOB,
      type: 'like',
      isRead: false,
      createdAt: Timestamp.now(),
    }),
  );
});

await seed();
console.log('\nprofiles and usernames');
await check('a verified user can look up a profile', async () => {
  await assertSucceeds(getDoc(doc(db(MALLORY), 'publicProfiles', BOB)));
});
await check('profile listing needs the paging limit', async () => {
  // The group filter is what the list rule insists on; see the age groups.
  const listed = (page) =>
    query(
      collection(db(ALICE), 'publicProfiles'),
      where('ageGroup', '==', 'adult'),
      where('usernameLowercase', '>=', 'a'),
      limit(page),
    );
  await assertSucceeds(getDocs(listed(20)));
  await assertFails(getDocs(listed(21)));
});
await check('a user can edit only their own display fields', async () => {
  await assertSucceeds(
    updateDoc(doc(db(ALICE), 'publicProfiles', ALICE), {
      bio: 'new bio',
      fullName: 'New name',
    }),
  );
  await assertFails(
    updateDoc(doc(db(ALICE), 'publicProfiles', ALICE), { username: 'hijack' }),
  );
  await assertFails(
    updateDoc(doc(db(BOB), 'publicProfiles', ALICE), { bio: 'not mine' }),
  );
});
await check('usernames are readable before sign-up but not listable', async () => {
  await assertSucceeds(
    getDoc(doc(testEnv.unauthenticatedContext().firestore(), 'usernames', ALICE)),
  );
  await assertFails(
    getDocs(query(collection(db(ALICE), 'usernames'), limit(10))),
  );
});

// --------------------------------------------------------------- age groups
const TEEN = 'tina';
const TEEN_OTHER = 'timmy';
const ADULT_OTHER = 'tabitha';
const LEGACY = 'legacy';
const TURNED_EIGHTEEN = 'eighteenit';
const ALMOST_EIGHTEEN = 'notquite';
const JUST_TURNED_THIRTEEN = 'thirteen';
const TEEN_WANNABE = 'youngwant';
const NO_GROUP = 'nogroup';
const EXTRA_KEY = 'extrakey';

/** A birth date `yearsAgo` years old, `shift` days younger than exactly that. */
const born = (yearsAgo, shift = 0) => {
  const today = new Date();
  return Timestamp.fromDate(
    new Date(
      Date.UTC(
        today.getUTCFullYear() - yearsAgo,
        today.getUTCMonth(),
        today.getUTCDate() + shift,
      ),
    ),
  );
};

/** An account whose private date, username row and public profile agree. */
async function account(uid, birthDate, group) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const store = context.firestore();
    await setDoc(doc(store, 'users', uid), {
      birthDate,
      createdAt: Timestamp.now(),
    });
    await setDoc(doc(store, 'usernames', uid), { uid });
    if (group === 'legacy') {
      const row = profile(uid);
      delete row.ageGroup;
      await setDoc(doc(store, 'publicProfiles', uid), row);
    } else if (group !== undefined) {
      await setDoc(doc(store, 'publicProfiles', uid), {
        ...profile(uid),
        ageGroup: group,
      });
    }
  });
}

/** The exact shape ChatRepository.searchUsers sends. */
const search = (uid, group, prefix) =>
  query(
    collection(db(uid), 'publicProfiles'),
    where('ageGroup', '==', group),
    orderBy('usernameLowercase'),
    startAt(prefix),
    endAt(`${prefix}\uf8ff`),
    limit(20),
  );

const found = (snapshot) => snapshot.docs.map((row) => row.id).sort().join(',');

function onlyRows(actual, expected, what) {
  if (actual !== expected) {
    throw new Error(`${what}: found [${actual}], expected [${expected}]`);
  }
}

await account(TEEN, born(15), 'teen');
await account(TEEN_OTHER, born(16), 'teen');
await account(ADULT_OTHER, born(30), 'adult');
await account(LEGACY, born(40), 'legacy');
await account(TURNED_EIGHTEEN, born(18), 'teen');
await account(ALMOST_EIGHTEEN, born(18, 1), undefined);
await account(JUST_TURNED_THIRTEEN, born(13), undefined);
await account(TEEN_WANNABE, born(14), undefined);
await account(NO_GROUP, born(15), undefined);
await account(EXTRA_KEY, born(15), undefined);

const teenRows = [TEEN, TEEN_OTHER, TURNED_EIGHTEEN].sort().join(',');

await check('an adult searching by name range finds only adults', async () => {
  const rows = await assertSucceeds(getDocs(search(ALICE, 'adult', 't')));
  onlyRows(found(rows), ADULT_OTHER, 'adult search');
});
await check('a teen searching the same name range finds only teens', async () => {
  const rows = await assertSucceeds(getDocs(search(TEEN, 'teen', 't')));
  onlyRows(found(rows), [TEEN, TEEN_OTHER].sort().join(','), 'teen search');
});
await check('a teen search over every name finds teens and no adult', async () => {
  const rows = await assertSucceeds(
    getDocs(
      query(
        collection(db(TEEN), 'publicProfiles'),
        where('ageGroup', '==', 'teen'),
        where('usernameLowercase', '>=', 'a'),
        limit(20),
      ),
    ),
  );
  onlyRows(found(rows), teenRows, 'a teen range over every name');
});
await check('an adult who asks the server for teens is refused the query', async () => {
  await assertFails(getDocs(search(ALICE, 'teen', 't')));
});
await check('a teen who asks for adults is refused the query', async () => {
  await assertFails(getDocs(search(TEEN, 'adult', 'a')));
});
await check('a search that never names a group is refused', async () => {
  await assertFails(
    getDocs(
      query(
        collection(db(TEEN), 'publicProfiles'),
        where('usernameLowercase', '>=', 'a'),
        limit(20),
      ),
    ),
  );
});
await check('a searcher whose own profile has no group searches nobody', async () => {
  await assertFails(getDocs(search(LEGACY, 'adult', 'a')));
});
await check('a profile with no group is never found in a search', async () => {
  const rows = await assertSucceeds(getDocs(search(ALICE, 'adult', 'le')));
  onlyRows(found(rows), '', 'the legacy profile in an adult search');
});
await check('the same profile still opens by id, so chats and feeds work', async () => {
  await assertSucceeds(getDoc(doc(db(TEEN), 'publicProfiles', LEGACY)));
});
await check('a teen cannot put themselves in the adult group', async () => {
  await assertFails(
    updateDoc(doc(db(TEEN), 'publicProfiles', TEEN), { ageGroup: 'adult' }),
  );
});
await check('a teen restating their own group is not punished for it', async () => {
  await assertSucceeds(
    updateDoc(doc(db(TEEN), 'publicProfiles', TEEN), {
      ageGroup: 'teen',
      bio: 'still a teen',
    }),
  );
});
await check('nobody can buy a different group by editing their birth date', async () => {
  await assertFails(
    updateDoc(doc(db(TEEN), 'users', TEEN), { birthDate: born(40) }),
  );
});
await check('a new profile states the group its birth date gives', async () => {
  await assertSucceeds(
    setDoc(doc(db(JUST_TURNED_THIRTEEN), 'publicProfiles', JUST_TURNED_THIRTEEN), {
      ...profile(JUST_TURNED_THIRTEEN),
      ageGroup: 'teen',
    }),
  );
});
await check('a thirteen-year-old cannot create an adult profile', async () => {
  await assertFails(
    setDoc(doc(db(TEEN_WANNABE), 'publicProfiles', TEEN_WANNABE), {
      ...profile(TEEN_WANNABE),
      ageGroup: 'adult',
    }),
  );
});
await check('a day short of eighteen is still a teen', async () => {
  await assertFails(
    setDoc(doc(db(ALMOST_EIGHTEEN), 'publicProfiles', ALMOST_EIGHTEEN), {
      ...profile(ALMOST_EIGHTEEN),
      ageGroup: 'adult',
    }),
  );
  await assertSucceeds(
    setDoc(doc(db(ALMOST_EIGHTEEN), 'publicProfiles', ALMOST_EIGHTEEN), {
      ...profile(ALMOST_EIGHTEEN),
      ageGroup: 'teen',
    }),
  );
});
await check('a profile cannot be created without any group', async () => {
  const row = profile(NO_GROUP);
  delete row.ageGroup;
  await assertFails(
    setDoc(doc(db(NO_GROUP), 'publicProfiles', NO_GROUP), row),
  );
});
await check('a profile cannot be created with an unknown key', async () => {
  await assertFails(
    setDoc(doc(db(EXTRA_KEY), 'publicProfiles', EXTRA_KEY), {
      ...profile(EXTRA_KEY),
      ageGroup: 'teen',
      country: 'EG',
    }),
  );
  await assertFails(
    updateDoc(doc(db(TEEN), 'publicProfiles', TEEN), {
      ageGroup: 'teen',
      country: 'EG',
    }),
  );
});
await check('the eighteenth birthday heals a profile left as a teen', async () => {
  await assertSucceeds(
    updateDoc(doc(db(TURNED_EIGHTEEN), 'publicProfiles', TURNED_EIGHTEEN), {
      ageGroup: 'adult',
    }),
  );
});
await check('a legacy owner can set the group they were always in', async () => {
  await assertSucceeds(
    updateDoc(doc(db(LEGACY), 'publicProfiles', LEGACY), { bio: 'healing' }),
  );
  await assertSucceeds(
    updateDoc(doc(db(LEGACY), 'publicProfiles', LEGACY), {
      ageGroup: 'adult',
    }),
  );
  await assertFails(
    updateDoc(doc(db(LEGACY), 'publicProfiles', LEGACY), {
      ageGroup: 'teen',
    }),
  );
});

await seed();
console.log('\nstorage');
await check('a member can upload their own chat image', async () => {
  const storage = user(ALICE).storage();
  await assertSucceeds(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${ALICE}/photo.png`),
      new Uint8Array([1, 2, 3]),
      { contentType: 'image/png' },
    ),
  );
});
await check('uploading chat media as somebody else is refused', async () => {
  const storage = user(ALICE).storage();
  await assertFails(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${BOB}/photo.png`),
      new Uint8Array([1, 2, 3]),
      { contentType: 'image/png' },
    ),
  );
});
await check('a stranger cannot upload into the thread', async () => {
  const storage = user(MALLORY).storage();
  await assertFails(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${MALLORY}/photo.png`),
      new Uint8Array([1, 2, 3]),
      { contentType: 'image/png' },
    ),
  );
});
await check('a stranger cannot read chat media', async () => {
  // Reads the object the member upload above created.
  const storage = user(MALLORY).storage();
  await assertFails(
    getDownloadURL(ref(storage, `chats/${CONVERSATION}/${ALICE}/photo.png`)),
  );
});
await check('the other participant can read chat media', async () => {
  const storage = user(BOB).storage();
  await assertSucceeds(
    getDownloadURL(ref(storage, `chats/${CONVERSATION}/${ALICE}/photo.png`)),
  );
});
await check('chat media of an unknown content type is refused', async () => {
  const storage = user(ALICE).storage();
  await assertFails(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${ALICE}/notes.bin`),
      new Uint8Array([1, 2, 3]),
      { contentType: 'multipart/form-data' },
    ),
  );
});
await check('a participant can upload the other chat media kinds', async () => {
  const storage = user(ALICE).storage();
  await assertSucceeds(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${ALICE}/clip.mp4`),
      new Uint8Array([1, 2, 3]),
      { contentType: 'video/mp4' },
    ),
  );
  await assertSucceeds(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${ALICE}/note.m4a`),
      new Uint8Array([1, 2, 3]),
      { contentType: 'audio/mp4' },
    ),
  );
  await assertSucceeds(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${ALICE}/report.pdf`),
      new Uint8Array([1, 2, 3]),
      { contentType: 'application/pdf' },
    ),
  );
});
await check('a chat image over 5 MB is refused', async () => {
  const storage = user(ALICE).storage();
  await assertFails(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${ALICE}/huge.jpg`),
      new Uint8Array(5 * 1024 * 1024 + 1),
      { contentType: 'image/jpeg' },
    ),
  );
});
await check('a chat voice note over 5 MB is refused', async () => {
  const storage = user(ALICE).storage();
  await assertFails(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${ALICE}/huge.m4a`),
      new Uint8Array(5 * 1024 * 1024 + 1),
      { contentType: 'audio/mp4' },
    ),
  );
});
await check('a chat document over 10 MB is refused', async () => {
  const storage = user(ALICE).storage();
  await assertFails(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${ALICE}/huge.pdf`),
      new Uint8Array(10 * 1024 * 1024 + 1),
      { contentType: 'application/pdf' },
    ),
  );
});
await check('a video may be larger than the image ceiling', async () => {
  const storage = user(ALICE).storage();
  await assertSucceeds(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${ALICE}/long.mp4`),
      new Uint8Array(6 * 1024 * 1024),
      { contentType: 'video/mp4' },
    ),
  );
});
await check('a user can post media under their own id', async () => {
  const storage = user(ALICE).storage();
  await assertSucceeds(
    uploadBytes(
      ref(storage, `posts/${ALICE}/image.png`),
      new Uint8Array([1, 2, 3]),
      { contentType: 'image/png' },
    ),
  );
  await assertFails(
    uploadBytes(
      ref(storage, `posts/${BOB}/image.png`),
      new Uint8Array([1, 2, 3]),
      { contentType: 'image/png' },
    ),
  );
});

// These four cases are the exact shape FeedRepository.uploadPostMedia and
// createPost send, replayed after the media-posting report. They pin down that
// the rules already allow video, and that they only reject it when the
// contentType is missing or belongs to somebody else's folder.
const postBytes = new Uint8Array(64 * 1024);
const postMediaPath = (uid, name) => `posts/${uid}/${name}`;

await check('the app jpeg upload is accepted for the author', async () => {
  await assertSucceeds(
    uploadBytes(
      ref(user(ALICE).storage(), postMediaPath(ALICE, 'P1.jpg')),
      postBytes,
      { contentType: 'image/jpeg' },
    ),
  );
});
await check('an mp4 upload is accepted for the author', async () => {
  await assertSucceeds(
    uploadBytes(
      ref(user(ALICE).storage(), postMediaPath(ALICE, 'P2.mp4')),
      postBytes,
      { contentType: 'video/mp4' },
    ),
  );
});
await check('media with no contentType is refused', async () => {
  // Storage infers application/octet-stream when metadata is missing, and the
  // rules only take image/* and video/*.
  await assertFails(
    uploadBytes(
      ref(user(ALICE).storage(), postMediaPath(ALICE, 'clip')),
      postBytes,
    ),
  );
});
await check('a file that is not an image or a video is refused', async () => {
  await assertFails(
    uploadBytes(
      ref(user(ALICE).storage(), postMediaPath(ALICE, 'P3.mp4')),
      postBytes,
      { contentType: 'application/x-msdownload' },
    ),
  );
});
await check('an account with an unverified email cannot upload media', async () => {
  const context = testEnv.authenticatedContext(ALICE, {
    email_verified: false,
  });
  await assertFails(
    uploadBytes(
      ref(context.storage(), postMediaPath(ALICE, 'P4.jpg')),
      postBytes,
      { contentType: 'image/jpeg' },
    ),
  );
});
await check('another signed-in reader can open post media', async () => {
  const storage = user(ALICE).storage();
  await uploadBytes(
    ref(storage, postMediaPath(ALICE, 'P5.jpg')),
    postBytes,
    { contentType: 'image/jpeg' },
  );
  await assertSucceeds(
    getDownloadURL(
      ref(user(BOB).storage(), postMediaPath(ALICE, 'P5.jpg')),
    ),
  );
  await assertFails(
    getDownloadURL(
      ref(
        testEnv.unauthenticatedContext().storage(),
        postMediaPath(ALICE, 'P5.jpg'),
      ),
    ),
  );
});

const postDoc = (mediaType, mediaUrl, caption) => ({
  authorId: ALICE,
  username: ALICE,
  fullName: `Test ${ALICE}`,
  avatarUrl: null,
  caption,
  mediaUrl,
  mediaType,
  likesCount: 0,
  commentsCount: 0,
  createdAt: serverTimestamp(),
});

await check('a video post document is accepted', async () => {
  await assertSucceeds(
    setDoc(
      doc(db(ALICE), 'posts', 'videoPost'),
      postDoc('video', 'https://example.com/P2.mp4', 'watch this'),
    ),
  );
});
await check('a media-only post is accepted, a text-less empty one is not', async () => {
  await assertSucceeds(
    setDoc(
      doc(db(ALICE), 'posts', 'imageOnlyPost'),
      postDoc('image', 'https://example.com/P1.jpg', ''),
    ),
  );
  await assertFails(
    setDoc(doc(db(ALICE), 'posts', 'emptyPost'), postDoc('none', null, '')),
  );
});

console.log('\ncarousel media (posts.mediaUrls)');

const slides = (count) =>
  Array.from({ length: count }, (_, index) => `https://example.com/P${index}.jpg`);
// The rules language has no list macro, so firestore.rules only inspects the
// count and the first slide; slides 2..10 are checked in FeedRepository.
const carousel = (urls, mediaType = 'image', mediaUrl = urls[0]) => ({
  ...postDoc(mediaType, mediaUrl, ''),
  mediaUrls: urls,
});

await check('a legacy post that only sets mediaUrl is still accepted', async () => {
  await assertSucceeds(
    setDoc(doc(db(ALICE), 'posts', 'legacyPost'), postDoc('image', 'https://example.com/P0.jpg', '')),
  );
});
await check('a carousel of two slides is accepted', async () => {
  await assertSucceeds(
    setDoc(doc(db(ALICE), 'posts', 'carouselTwo'), carousel(slides(2))),
  );
});
await check('a carousel of ten slides is accepted', async () => {
  await assertSucceeds(
    setDoc(doc(db(ALICE), 'posts', 'carouselTen'), carousel(slides(10))),
  );
});
await check('an eleventh slide is refused', async () => {
  await assertFails(
    setDoc(doc(db(ALICE), 'posts', 'carouselEleven'), carousel(slides(11))),
  );
});
await check('an empty carousel is refused', async () => {
  // mediaUrl stays a real string: the write must fail on the rule, not on
  // malformed test data.
  await assertFails(
    setDoc(
      doc(db(ALICE), 'posts', 'carouselEmpty'),
      carousel([], 'image', 'https://example.com/P0.jpg'),
    ),
  );
});
await check('a first slide that is not a string is refused', async () => {
  await assertFails(
    setDoc(
      doc(db(ALICE), 'posts', 'carouselNumber'),
      carousel([42], 'image', 42),
    ),
  );
});
await check('a blank first slide is refused', async () => {
  await assertFails(
    setDoc(doc(db(ALICE), 'posts', 'carouselBlank'), carousel([''])),
  );
});
await check('a carousel cannot mix slides with a clip', async () => {
  await assertFails(
    setDoc(
      doc(db(ALICE), 'posts', 'carouselVideoMix'),
      carousel(slides(2), 'video'),
    ),
  );
});
await check('a carousel is refused when its first slide is not mediaUrl', async () => {
  await assertFails(
    setDoc(
      doc(db(ALICE), 'posts', 'mismatchedCarousel'),
      {
        ...postDoc('image', 'https://example.com/P1.jpg', 'hi'),
        mediaUrls: ['https://example.com/P2.jpg'],
      },
    ),
  );
});

console.log('\nstory viewers');

/** A story document, written with the rules off: no client may seed one. */
async function seedStory(id, authorId) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'stories', id), {
      authorId,
      username: authorId,
      fullName: `Test ${authorId}`,
      avatarUrl: null,
      mediaUrl: 'https://example.com/story.jpg',
      createdAt: Timestamp.now(),
    });
  });
}

/** A post document for the report checks: posts/post1 is deleted earlier. */
async function seedPost(id, authorId) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'posts', id), {
      authorId,
      username: authorId,
      fullName: `Test ${authorId}`,
      avatarUrl: null,
      caption: 'hello',
      mediaUrl: null,
      mediaType: 'none',
      likesCount: 0,
      commentsCount: 0,
      createdAt: Timestamp.now(),
    });
  });
}

const view = (viewerId) => ({ userId: viewerId, viewedAt: serverTimestamp() });
const viewers = (storyId, viewerId) =>
  doc(db(viewerId), 'stories', storyId, 'viewers', viewerId);

await seedStory('aliceStory', ALICE);
await seedStory('bobStory', BOB);

await check('a reader records a view on somebody else story', async () => {
  await assertSucceeds(setDoc(viewers('aliceStory', BOB), view(BOB)));
});
await check('nobody records a view on their own story', async () => {
  await assertFails(setDoc(viewers('aliceStory', ALICE), view(ALICE)));
});
await check('a view cannot be written for another account', async () => {
  await assertFails(
    setDoc(doc(db(BOB), 'stories', 'aliceStory', 'viewers', ALICE), view(ALICE)),
  );
});
await check('a view written with the device clock is refused', async () => {
  await assertFails(
    setDoc(doc(db(MALLORY), 'stories', 'aliceStory', 'viewers', MALLORY), {
      userId: MALLORY,
      viewedAt: Timestamp.fromDate(new Date('2020-01-01')),
    }),
  );
});
await check('a view document has no extra fields', async () => {
  await assertFails(
    setDoc(doc(db(ALICE), 'stories', 'bobStory', 'viewers', ALICE), {
      ...view(ALICE),
      storyId: 'bobStory',
    }),
  );
});
await check('a view cannot be edited', async () => {
  await assertFails(
    updateDoc(viewers('aliceStory', BOB), { viewedAt: serverTimestamp() }),
  );
});
await check('only the author reads the audience', async () => {
  await assertSucceeds(
    getDocs(
      query(
        collection(db(ALICE), 'stories', 'aliceStory', 'viewers'),
        limit(200),
      ),
    ),
  );
  await assertFails(
    getDocs(
      query(
        collection(db(MALLORY), 'stories', 'aliceStory', 'viewers'),
        limit(200),
      ),
    ),
  );
});
await check('an audience list without a limit is refused', async () => {
  await assertFails(
    getDocs(collection(db(ALICE), 'stories', 'aliceStory', 'viewers')),
  );
});
await check('a stranger cannot delete somebody else view', async () => {
  await assertFails(
    deleteDoc(doc(db(MALLORY), 'stories', 'aliceStory', 'viewers', BOB)),
  );
});
await check('the author can clear the audience while the story exists', async () => {
  await assertSucceeds(deleteDoc(doc(db(ALICE), 'stories', 'aliceStory', 'viewers', BOB)));
});
await check('deleteStory must clear the audience before the story document', async () => {
  // The viewer delete rule reads the parent story through get(), so once the
  // story is gone its audience can never be removed by anybody. This asserts
  // the order StoryRepository.deleteStory has to keep.
  await assertSucceeds(setDoc(viewers('bobStory', ALICE), view(ALICE)));
  await assertSucceeds(deleteDoc(doc(db(BOB), 'stories', 'bobStory')));
  await assertFails(deleteDoc(doc(db(BOB), 'stories', 'bobStory', 'viewers', ALICE)));
});

console.log('\nfollows');

const followRow = (uid) => ({ userId: uid, followedAt: serverTimestamp() });
// Each db(uid) is its own Firestore instance, so a batch has to be built from
// the same instance as the references it writes.
const followersDoc = (as, ownerId, followerId) =>
  doc(db(as), 'users', ownerId, 'followers', followerId);
const followingDoc = (as, ownerId, targetId) =>
  doc(db(as), 'users', ownerId, 'following', targetId);
const on = (store, ownerId, sub, rowId) =>
  doc(store, 'users', ownerId, sub, rowId);

// FollowRepository.setFollowing writes exactly these two rows in one batch.
await check('a follow writes both mirrored rows in one batch', async () => {
  const alice = db(ALICE);
  const batch = writeBatch(alice);
  batch.set(on(alice, BOB, 'followers', ALICE), followRow(ALICE));
  batch.set(on(alice, ALICE, 'following', BOB), followRow(BOB));
  await assertSucceeds(batch.commit());
});
await check('a stranger may page through someone follower list', async () => {
  await assertSucceeds(
    getDocs(
      query(collection(db(MALLORY), 'users', BOB, 'followers'), limit(201)),
    ),
  );
});
await check('dumping a whole follower list without a limit is refused', async () => {
  await assertFails(getDocs(collection(db(MALLORY), 'users', BOB, 'followers')));
});
// This is why the app counts with a limit(201) probe instead of count(): an
// aggregate carries no limit, so no rule can bound it.
await check('a count() aggregate is refused under the bounded list rule', async () => {
  await assertFails(
    getCountFromServer(collection(db(MALLORY), 'users', BOB, 'followers')),
  );
});
await check('nobody writes a follower row for another account', async () => {
  await assertFails(setDoc(followersDoc(BOB, BOB, ALICE), followRow(ALICE)));
});
await check('a user cannot follow themselves', async () => {
  await assertFails(setDoc(followersDoc(ALICE, ALICE, ALICE), followRow(ALICE)));
  await assertFails(setDoc(followingDoc(ALICE, ALICE, ALICE), followRow(ALICE)));
});
await check('a follow row cannot claim to be about somebody else', async () => {
  await assertFails(setDoc(followersDoc(MALLORY, BOB, MALLORY), followRow(ALICE)));
});
await check('a follow row has no extra fields', async () => {
  await assertFails(
    setDoc(followersDoc(MALLORY, BOB, MALLORY), {
      ...followRow(MALLORY),
      since: '2020',
    }),
  );
});
await check('a follow written with the device clock is refused', async () => {
  await assertFails(
    setDoc(followersDoc(MALLORY, BOB, MALLORY), {
      userId: MALLORY,
      followedAt: Timestamp.fromDate(new Date('2020-01-01')),
    }),
  );
});
await check('a following row cannot be planted in another account list', async () => {
  await assertFails(setDoc(followingDoc(MALLORY, BOB, ALICE), followRow(ALICE)));
});
await check('a follow cannot be edited', async () => {
  await assertFails(
    updateDoc(followersDoc(ALICE, BOB, ALICE), { userId: MALLORY }),
  );
});
await check('the author of a profile cannot remove a follower', async () => {
  await assertFails(deleteDoc(followersDoc(BOB, BOB, ALICE)));
});
await check('an unfollow removes both rows', async () => {
  const alice = db(ALICE);
  const batch = writeBatch(alice);
  batch.delete(on(alice, BOB, 'followers', ALICE));
  batch.delete(on(alice, ALICE, 'following', BOB));
  await assertSucceeds(batch.commit());
});

console.log('\nsaved stickers');

// SavedStickerRepository writes users/{me}/savedStickers/{packId}_{sticker}, so
// a bookmark is a reference into the packs the app ships: no bytes, no URL and
// no storage path ever reaches this collection.
// The writer and the shelf owner are separate arguments: a rule that only holds
// when the two differ is the one worth testing.
const savedDoc = (as, owner, id) => on(db(as), owner, 'savedStickers', id);
const savedRow = (packId, sticker, savedAt) => ({
  packId,
  sticker,
  savedAt: savedAt ?? serverTimestamp(),
});
const CAT = 'mixsay-friends_cat';
const MINE = (id) => savedDoc(ALICE, ALICE, id);

await check('saving a bundled sticker writes one reference row', async () => {
  await assertSucceeds(setDoc(MINE(CAT), savedRow('mixsay-friends', 'cat')));
});
await check('a stranger cannot plant a bookmark in another account shelf', async () => {
  await assertFails(
    setDoc(savedDoc(MALLORY, ALICE, 'mixsay-friends_moon'), savedRow('mixsay-friends', 'moon')),
  );
});
await check('a bookmark cannot be written into another account', async () => {
  await assertFails(
    setDoc(savedDoc(ALICE, MALLORY, 'mixsay-friends_taco'), savedRow('mixsay-friends', 'taco')),
  );
});
await check('a signed-out device has no bookmarks to save', async () => {
  await assertFails(
    setDoc(
      on(
        testEnv.unauthenticatedContext().firestore(),
        ALICE,
        'savedStickers',
        'mixsay-friends_tea',
      ),
      savedRow('mixsay-friends', 'tea'),
    ),
  );
});
await check('a row whose id is not both halves is refused', async () => {
  await assertFails(setDoc(MINE('mixsay-friends_sun'), savedRow('mixsay-friends', 'cat')));
});
await check('a bookmark may not carry a file, a path or a URL', async () => {
  await assertFails(
    setDoc(MINE('mixsay-friends_heart'), {
      ...savedRow('mixsay-friends', 'heart'),
      mediaUrl: 'https://example.com/heart.png',
    }),
  );
});
await check('a half outside the pack-id charset is refused', async () => {
  // Upper case and a stray underscore: the charset the bundled pack ids use, so
  // a made-up row cannot look like a pack the app knows, and neither half can
  // hold the `_` that joins them into an id.
  await assertFails(setDoc(MINE('MixSay_friends'), savedRow('MixSay-friends', 'cat')));
  await assertFails(setDoc(MINE('a_b_c'), savedRow('a', 'b_c')));
  await assertFails(setDoc(MINE('mixsay-friends_'), savedRow('mixsay-friends', '')));
});
await check('a bookmark stamped with the device clock is refused', async () => {
  await assertFails(
    setDoc(
      MINE('mixsay-friends_rainbow'),
      savedRow('mixsay-friends', 'rainbow', Timestamp.fromDate(new Date('2020-01-01'))),
    ),
  );
});
await check('saving a sticker twice is not an error', async () => {
  // The row id already forbids a duplicate, so the second tap may only move the
  // timestamp; anything else would report a failure for a save that worked.
  await assertSucceeds(updateDoc(MINE(CAT), { savedAt: serverTimestamp() }));
});
await check('a bookmark cannot be re-pointed at another sticker', async () => {
  await assertFails(updateDoc(MINE(CAT), { sticker: 'moon' }));
  await assertFails(updateDoc(MINE(CAT), { packId: 'other-pack' }));
});
await check('the owner reads a bookmark', async () => {
  await assertSucceeds(getDoc(MINE(CAT)));
});
await check('nobody else reads a bookmark', async () => {
  await assertFails(getDoc(savedDoc(BOB, ALICE, CAT)));
});
await check('the owner pages the saved tab with the app ceiling', async () => {
  await assertSucceeds(
    getDocs(query(collection(db(ALICE), 'users', ALICE, 'savedStickers'), limit(200))),
  );
});
await check('one row past the ceiling is refused', async () => {
  await assertFails(
    getDocs(query(collection(db(ALICE), 'users', ALICE, 'savedStickers'), limit(201))),
  );
});
await check('dumping every bookmark without a limit is refused', async () => {
  await assertFails(getDocs(collection(db(ALICE), 'users', ALICE, 'savedStickers')));
});
await check('a stranger cannot list another account saved stickers', async () => {
  await assertFails(
    getDocs(query(collection(db(MALLORY), 'users', ALICE, 'savedStickers'), limit(200))),
  );
});
// The 200 ceiling itself is the app's: rules cannot count a collection, and an
// aggregate carries no limit, so the repository counts with limit(200) and this
// proves count() is not available to lean on.
await check('a count() aggregate is refused under the bounded list rule', async () => {
  await assertFails(
    getCountFromServer(collection(db(ALICE), 'users', ALICE, 'savedStickers')),
  );
});
await check('the owner removes a bookmark', async () => {
  await assertSucceeds(deleteDoc(MINE(CAT)));
});
await check('nobody else removes a bookmark', async () => {
  await assertFails(deleteDoc(savedDoc(BOB, ALICE, 'mixsay-friends_rainbow')));
});

console.log('\nreports');

// A report id is reporter_target, so every case gets its own target: two
// checks can never collide on one document.
for (const id of [
  'spamTarget',
  'noteTarget',
  'longNoteTarget',
  'ownPost',
  'reasonTarget',
  'idTarget',
  'spoofTarget',
  'twiceTarget',
]) {
  await seedPost(id, ALICE);
}

const report = (reporter, targetId, reason, targetType = 'post', extra) => ({
  reporterId: reporter,
  targetType,
  targetId,
  reason,
  createdAt: serverTimestamp(),
  ...extra,
});
const reportRef = (reporter, targetId) =>
  doc(db(reporter), 'reports', `${reporter}_${targetId}`);

await check('a report about somebody else post is accepted', async () => {
  await assertSucceeds(
    setDoc(reportRef(BOB, 'spamTarget'), report(BOB, 'spamTarget', 'spam')),
  );
});
await check('a report is accepted with a valid extra note', async () => {
  await assertSucceeds(
    setDoc(
      reportRef(BOB, 'noteTarget'),
      report(BOB, 'noteTarget', 'harassment', 'post', {
        extraNote: 'sent it twice a minute',
      }),
    ),
  );
});
await check('a note longer than 300 characters is refused', async () => {
  await assertFails(
    setDoc(
      reportRef(BOB, 'longNoteTarget'),
      report(BOB, 'longNoteTarget', 'other', 'post', {
        extraNote: 'a'.repeat(301),
      }),
    ),
  );
});
await check('nobody reports their own post', async () => {
  await assertFails(
    setDoc(
      reportRef(ALICE, 'ownPost'),
      report(ALICE, 'ownPost', 'spam'),
    ),
  );
});
await check('nobody reports their own story', async () => {
  await assertFails(
    setDoc(
      reportRef(ALICE, 'aliceStory'),
      report(ALICE, 'aliceStory', 'spam', 'story'),
    ),
  );
});
await check('a report about a story of somebody else is accepted', async () => {
  await assertSucceeds(
    setDoc(
      reportRef(BOB, 'aliceStory'),
      report(BOB, 'aliceStory', 'nudity', 'story'),
    ),
  );
});
await check('a report about a document that does not exist is refused', async () => {
  await assertFails(
    setDoc(
      doc(db(BOB), 'reports', `${BOB}_ghostTarget`),
      report(BOB, 'ghostTarget', 'other'),
    ),
  );
});
await check('an unknown report reason is refused', async () => {
  await assertFails(
    setDoc(
      reportRef(BOB, 'reasonTarget'),
      report(BOB, 'reasonTarget', 'rude'),
    ),
  );
});
await check('a report id that is not reporter_target is refused', async () => {
  await assertFails(
    setDoc(
      doc(db(BOB), 'reports', `${BOB}_notTheTarget`),
      report(BOB, 'idTarget', 'spam'),
    ),
  );
});
await check('a report cannot name another reporter', async () => {
  await assertFails(
    setDoc(
      reportRef(BOB, 'spoofTarget'),
      report(BOB, 'spoofTarget', 'spam', 'post', { reporterId: MALLORY }),
    ),
  );
});
await check('a client can neither read nor list reports', async () => {
  await assertFails(getDoc(reportRef(ALICE, 'spamTarget')));
  await assertFails(getDocs(collection(db(ALICE), 'reports')));
});
await check('reporting the same target twice is refused', async () => {
  await assertSucceeds(
    setDoc(
      reportRef(BOB, 'twiceTarget'),
      report(BOB, 'twiceTarget', 'spam'),
    ),
  );
  await assertFails(
    setDoc(
      reportRef(BOB, 'twiceTarget'),
      report(BOB, 'twiceTarget', 'violence'),
    ),
  );
});
await check('a report cannot be edited or deleted', async () => {
  await assertFails(
    updateDoc(reportRef(BOB, 'spamTarget'), { reason: 'other' }),
  );
  await assertFails(deleteDoc(reportRef(BOB, 'spamTarget')));
});

await testEnv.cleanup();

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length > 0) {
  for (const failure of failures) console.log(` - ${failure}`);
  process.exitCode = 1;
}
