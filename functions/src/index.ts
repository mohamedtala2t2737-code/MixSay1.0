import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

const app = getApps()[0] ?? initializeApp();
const firestore = getFirestore(app);
const messaging = getMessaging(app);

const isNonEmptyString = (value: unknown): value is string =>
  typeof value === "string" && value.trim().length > 0;

const messagePreview = (content: unknown, mediaUrl: unknown): string => {
  if (typeof content === "string" && content.trim().length > 0) {
    const trimmed = content.trim();
    return trimmed.length > 160 ? `${trimmed.slice(0, 157)}...` : trimmed;
  }
  return isNonEmptyString(mediaUrl) ? "Sent an image" : "New message";
};

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
    const senderProfile = await firestore
      .collection("publicProfiles")
      .doc(senderId)
      .get();
    const senderNameValue =
      senderProfile.get("fullName") || senderProfile.get("username");
    const senderName = isNonEmptyString(senderNameValue)
      ? senderNameValue.trim().slice(0, 80)
      : "MixSay";
    const notificationBody = messagePreview(message.content, message.mediaUrl);

    for (const recipientId of recipientIds) {
      const deviceSnapshot = await firestore
        .collection("users")
        .doc(recipientId)
        .collection("deviceTokens")
        .get();
      const devices = deviceSnapshot.docs.filter((device) =>
        isNonEmptyString(device.get("token")),
      );

      for (let offset = 0; offset < devices.length; offset += 500) {
        const batch = devices.slice(offset, offset + 500);
        const result = await messaging.sendEachForMulticast({
          tokens: batch.map((device) => device.get("token") as string),
          notification: {
            title: senderName,
            body: notificationBody,
          },
          data: {
            conversation_id: conversationId,
            message_id: messageId,
          },
          android: {
            priority: "high",
            notification: {
              channelId: "chat_messages",
            },
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

        const failedErrorCodes = result.responses.flatMap((sendResult) =>
          sendResult.error ? [sendResult.error.code] : [],
        );
        logger.info("Chat push delivery completed", {
          conversationId,
          messageId,
          recipientId,
          sent: result.successCount,
          failed: result.failureCount,
          failedErrorCodes,
        });
      }
    }
  },
);
