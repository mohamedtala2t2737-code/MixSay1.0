import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import {
  onDocumentCreated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";

const app = getApps()[0] ?? initializeApp();
const firestore = getFirestore(app);
const messaging = getMessaging(app);

const isNonEmptyString = (value: unknown): value is string =>
  typeof value === "string" && value.trim().length > 0;

const truncate = (value: string, max = 160): string =>
  value.length > max ? `${value.slice(0, max - 3)}...` : value;

const messagePreview = (content: unknown, mediaUrl: unknown): string => {
  if (isNonEmptyString(content)) return truncate(content.trim());
  return isNonEmptyString(mediaUrl) ? "Sent an image" : "New message";
};

type NotificationKind = "like" | "comment" | "message";

interface InboxEntry {
  /** Deterministic id so a retried function run overwrites instead of duplicates. */
  inboxId: string;
  recipientId: string;
  actorId: string;
  actorName: string;
  kind: NotificationKind;
  body: string;
  postId?: string;
  conversationId?: string;
  messageId?: string;
}

/**
 * Notifications are read back by the app from the `notifications` collection,
 * so the document is stored even when the device push fails (offline phone,
 * revoked permission). A failed push never blocks the inbox entry.
 */
async function deliverToInbox(entry: InboxEntry): Promise<void> {
  const document: Record<string, unknown> = {
    recipientId: entry.recipientId,
    actorId: entry.actorId,
    actorName: entry.actorName,
    type: entry.kind,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
  };
  if (entry.postId !== undefined) document.postId = entry.postId;
  if (entry.conversationId !== undefined) {
    document.conversationId = entry.conversationId;
  }

  try {
    await firestore.collection("notifications").doc(entry.inboxId).set(document);
  } catch (error) {
    logger.error("Unable to store a notification document", {
      recipientId: entry.recipientId,
      kind: entry.kind,
      error,
    });
  }

  await sendPush(entry);
}

async function sendPush(entry: InboxEntry): Promise<void> {
  const deviceSnapshot = await firestore
    .collection("users")
    .doc(entry.recipientId)
    .collection("deviceTokens")
    .get();
  const devices = deviceSnapshot.docs.filter((device) =>
    isNonEmptyString(device.get("token")),
  );
  if (devices.length === 0) return;

  const data: Record<string, string> = { type: entry.kind };
  if (entry.postId !== undefined) data.post_id = entry.postId;
  if (entry.conversationId !== undefined) {
    data.conversation_id = entry.conversationId;
  }
  if (entry.messageId !== undefined) data.message_id = entry.messageId;

  const channelId =
    entry.kind === "message" ? "chat_messages" : "post_interactions";

  for (let offset = 0; offset < devices.length; offset += 500) {
    const batch = devices.slice(offset, offset + 500);
    const result = await messaging.sendEachForMulticast({
      tokens: batch.map((device) => device.get("token") as string),
      notification: {
        title: entry.actorName,
        body: entry.body,
      },
      data,
      android: {
        priority: "high",
        notification: { channelId },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });

    const staleDeviceReferences = result.responses.flatMap(
      (sendResult, index) => {
        const errorCode = sendResult.error?.code;
        return errorCode === "messaging/registration-token-not-registered" ||
          errorCode === "messaging/invalid-registration-token"
          ? [batch[index].ref]
          : [];
      },
    );
    if (staleDeviceReferences.length > 0) {
      const cleanupBatch = firestore.batch();
      for (const reference of staleDeviceReferences) {
        cleanupBatch.delete(reference);
      }
      await cleanupBatch.commit();
    }

    logger.info("Push delivery completed", {
      recipientId: entry.recipientId,
      kind: entry.kind,
      sent: result.successCount,
      failed: result.failureCount,
      failedErrorCodes: result.responses.flatMap((sendResult) =>
        sendResult.error ? [sendResult.error.code] : [],
      ),
    });
  }
}

/**
 * `fullName` falls back to `username`, and both fall back to the app name so a
 * push never arrives with an empty title.
 */
async function displayNameOf(userId: string): Promise<string> {
  const profile = await firestore
    .collection("publicProfiles")
    .doc(userId)
    .get();
  const value = profile.get("fullName") || profile.get("username");
  return isNonEmptyString(value) ? value.trim().slice(0, 80) : "MixSay";
}

async function postAuthorId(postId: string): Promise<string | null> {
  const post = await firestore.collection("posts").doc(postId).get();
  const authorId = post.get("authorId");
  return isNonEmptyString(authorId) ? authorId : null;
}

export const sendChatMessageNotification = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    const messageSnapshot = event.data;
    if (!messageSnapshot) return;

    const { conversationId, messageId } = event.params;
    const message = messageSnapshot.data();
    const senderId = message.senderId;

    if (!isNonEmptyString(senderId)) {
      logger.warn("Skipping chat notification without a sender ID", {
        conversationId,
        messageId,
      });
      return;
    }

    const conversationSnapshot = await firestore
      .collection("conversations")
      .doc(conversationId)
      .get();
    const members: unknown = conversationSnapshot.get("members");
    if (
      !conversationSnapshot.exists ||
      !Array.isArray(members) ||
      members.length !== 2 ||
      !members.every(isNonEmptyString) ||
      new Set(members).size !== 2 ||
      !members.includes(senderId)
    ) {
      logger.warn("Skipping chat notification for an invalid conversation", {
        conversationId,
        messageId,
      });
      return;
    }

    const recipientIds = members.filter(
      (member): member is string => member !== senderId,
    );
    const senderName = await displayNameOf(senderId);
    const notificationBody = messagePreview(message.content, message.mediaUrl);

    for (const recipientId of recipientIds) {
      await deliverToInbox({
        inboxId: `message_${messageId}_${recipientId}`,
        recipientId,
        actorId: senderId,
        actorName: senderName,
        kind: "message",
        body: notificationBody,
        conversationId,
        messageId,
      });
    }
  },
);

export const sendPostLikeNotification = onDocumentCreated(
  "posts/{postId}/likes/{likerId}",
  async (event) => {
    const { postId, likerId } = event.params;
    if (!event.data || !isNonEmptyString(likerId)) return;

    const authorId = await postAuthorId(postId);
    if (authorId === null || authorId === likerId) return;

    await deliverToInbox({
      inboxId: `like_${postId}_${likerId}`,
      recipientId: authorId,
      actorId: likerId,
      actorName: await displayNameOf(likerId),
      kind: "like",
      body: "liked your post",
      postId,
    });
  },
);

/**
 * Un-liking removes the like document, so the matching inbox entries go with
 * it; otherwise the author would keep seeing a like that no longer exists.
 */
export const removePostLikeNotifications = onDocumentDeleted(
  "posts/{postId}/likes/{likerId}",
  async (event) => {
    const { postId, likerId } = event.params;
    if (!isNonEmptyString(likerId)) return;

    const matches = await firestore
      .collection("notifications")
      .where("postId", "==", postId)
      .where("actorId", "==", likerId)
      .where("type", "==", "like")
      .get();
    if (matches.empty) return;

    const cleanupBatch = firestore.batch();
    for (const document of matches.docs) {
      cleanupBatch.delete(document.ref);
    }
    await cleanupBatch.commit();
  },
);

/**
 * A post owns its likes and comments, but Firestore never cascades deletes. Left
 * alone, every deleted post keeps its subcollection documents forever: they stay
 * billable and keep matching collection-group reads. Writes are chunked because
 * a batch tops out at 500 operations.
 */
export const cleanupPostChildren = onDocumentDeleted(
  "posts/{postId}",
  async (event) => {
    const { postId } = event.params;

    for (const childCollection of ["likes", "comments"]) {
      const children = await firestore
        .collection(`posts/${postId}/${childCollection}`)
        .get();
      const documents = children.docs;

      for (let start = 0; start < documents.length; start += 400) {
        const batch = firestore.batch();
        for (const document of documents.slice(start, start + 400)) {
          batch.delete(document.ref);
        }
        await batch.commit();
      }
    }
  },
);

export const sendPostCommentNotification = onDocumentCreated(
  "posts/{postId}/comments/{commentId}",
  async (event) => {
    const commentSnapshot = event.data;
    if (!commentSnapshot) return;

    const { postId, commentId } = event.params;
    const comment = commentSnapshot.data();
    const authorId = comment.authorId;
    if (!isNonEmptyString(authorId)) {
      logger.warn("Skipping comment notification without an author ID", {
        postId,
        commentId,
      });
      return;
    }

    const postAuthorIdValue = await postAuthorId(postId);
    if (postAuthorIdValue === null || postAuthorIdValue === authorId) return;

    const content = comment.content;
    const body = isNonEmptyString(content)
      ? truncate(content.trim())
      : "commented on your post";

    await deliverToInbox({
      inboxId: `comment_${commentId}`,
      recipientId: postAuthorIdValue,
      actorId: authorId,
      actorName: await displayNameOf(authorId),
      kind: "comment",
      body: isNonEmptyString(content) ? `"${body}"` : body,
      postId,
    });
  },
);
