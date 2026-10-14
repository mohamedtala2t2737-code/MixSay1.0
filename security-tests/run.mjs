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
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
  limit,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
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
  createdAt: Timestamp.now(),
});

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
const newId = conversationId(ALICE, MALLORY);
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
  await assertSucceeds(
    getDocs(
      query(
        collection(db(ALICE), 'publicProfiles'),
        where('usernameLowercase', '>=', 'a'),
        limit(20),
      ),
    ),
  );
  await assertFails(
    getDocs(
      query(
        collection(db(ALICE), 'publicProfiles'),
        where('usernameLowercase', '>=', 'a'),
        limit(21),
      ),
    ),
  );
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
await check('non-image chat media is refused', async () => {
  const storage = user(ALICE).storage();
  await assertFails(
    uploadBytes(
      ref(storage, `chats/${CONVERSATION}/${ALICE}/notes.txt`),
      new Uint8Array([1, 2, 3]),
      { contentType: 'text/plain' },
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

await testEnv.cleanup();

console.log(`\n${passed} passed, ${failures.length} failed`);
if (failures.length > 0) {
  for (const failure of failures) console.log(` - ${failure}`);
  process.exitCode = 1;
}
