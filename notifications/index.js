const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {setGlobalOptions} = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

setGlobalOptions({
  maxInstances: 10,
});

exports.sendAnnouncementNotification = onDocumentCreated(
    "announcements/{announcementId}",
    async (event) => {
      try {
        if (!event.data) {
          console.log("Announcement data nahi mili.");
          return;
        }

        const announcement = event.data.data();

        const title = announcement.title || "New Announcement";
        const description = announcement.description || "";

        const sendToTeachers = announcement.teachers === true;
        const sendToStudents = announcement.students === true;

        console.log("New announcement:", title);
        console.log("Teachers:", sendToTeachers);
        console.log("Students:", sendToStudents);

        const roles = [];

        if (sendToTeachers) {
          roles.push("teacher");
        }

        if (sendToStudents) {
          roles.push("student");
        }

        if (roles.length === 0) {
          console.log("Koi audience select nahi hai.");
          return;
        }

        const usersSnapshot = await admin
            .firestore()
            .collection("users")
            .where("role", "in", roles)
            .get();

        const tokens = [];

        usersSnapshot.forEach((doc) => {
          const userData = doc.data();
          const token = userData.fcmToken;

          if (token && typeof token === "string") {
            tokens.push(token);
          }
        });

        console.log("Total FCM tokens:", tokens.length);

        if (tokens.length === 0) {
          console.log("Koi FCM token nahi mila.");
          return;
        }

        const notification = {
          title: title,
          body:
          description.length > 100 ?
            description.substring(0, 100) + "..." :
            description,
        };

        const data = {
          announcementId: event.params.announcementId,
          title: title,
          description: description,
        };

        const response = await admin.messaging().sendEachForMulticast({
          tokens: tokens,
          notification: notification,
          data: data,
        });

        console.log(
            "Notifications sent: " +
          response.successCount +
          ", failed: " +
          response.failureCount,
        );

        const invalidTokens = [];

        response.responses.forEach((result, index) => {
          if (!result.success) {
            const errorCode = result.error && result.error.code;
            const errorMessage =
            result.error && result.error.message;

            console.log("FCM Error:", errorCode, errorMessage);

            if (
              errorCode ===
              "messaging/registration-token-not-registered" ||
            errorCode === "messaging/invalid-registration-token"
            ) {
              invalidTokens.push(tokens[index]);
            }
          }
        });

        if (invalidTokens.length > 0) {
          const cleanupPromises = [];

          usersSnapshot.forEach((doc) => {
            const userData = doc.data();

            if (invalidTokens.includes(userData.fcmToken)) {
              cleanupPromises.push(
                  doc.ref.update({
                    fcmToken: admin.firestore.FieldValue.delete(),
                  }),
              );
            }
          });

          await Promise.all(cleanupPromises);

          console.log(
              "Removed " + invalidTokens.length + " invalid FCM tokens.",
          );
        }
      } catch (error) {
        console.error("Notification function error:", error);
      }
    },
);
