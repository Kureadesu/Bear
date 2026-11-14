import {
  createRemoteJWKSet,
  importPKCS8,
  jwtVerify,
  SignJWT,
} from "jose";

const firebaseKeys = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/" +
      "securetoken@system.gserviceaccount.com",
  ),
);

let cachedGoogleToken;

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function documentPath(...parts) {
  return parts.map(encodeURIComponent).join("/");
}

function stringField(document, name) {
  return document?.fields?.[name]?.stringValue;
}

function stringArrayField(document, name) {
  const values = document?.fields?.[name]?.arrayValue?.values ?? [];
  return values.map((value) => value.stringValue);
}

async function googleAccessToken(account) {
  const now = Math.floor(Date.now() / 1000);

  if (
    cachedGoogleToken?.email === account.client_email &&
    cachedGoogleToken.expiresAt > now + 60
  ) {
    return cachedGoogleToken.token;
  }

  const key = await importPKCS8(account.private_key, "RS256");

  const assertion = await new SignJWT({
    scope: [
      "https://www.googleapis.com/auth/datastore",
      "https://www.googleapis.com/auth/firebase.messaging",
    ].join(" "),
  })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    console.error("Google authentication failed:", response.status);
    throw new HttpError(502, "Notification service authentication failed.");
  }

  const result = await response.json();

  cachedGoogleToken = {
    email: account.client_email,
    token: result.access_token,
    expiresAt: now + result.expires_in,
  };

  return result.access_token;
}

async function firestoreGet(baseUrl, path, accessToken) {
  const response = await fetch(`${baseUrl}/${path}`, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (response.status === 404) {
    return null;
  }

  if (!response.ok) {
    console.error("Firestore read failed:", response.status);
    throw new HttpError(502, "Unable to read notification data.");
  }

  return response.json();
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get("Origin");
    const allowedOrigin = env.ALLOWED_ORIGIN;

    const cors = {
      "Access-Control-Allow-Origin": allowedOrigin || "",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Authorization, Content-Type",
      "Vary": "Origin",
    };

    function reply(status, body) {
      return new Response(JSON.stringify(body), {
        status,
        headers: {
          ...cors,
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      });
    }

    // Android requests normally have no Origin header.
    // Browser requests must come from the configured website.
    if (origin && origin !== allowedOrigin) {
      return reply(403, { error: "Website origin not allowed." });
    }

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    if (new URL(request.url).pathname !== "/notify") {
      return reply(404, { error: "Not found." });
    }

    if (request.method !== "POST") {
      return reply(405, { error: "Use POST." });
    }

    try {
      if (!env.FIREBASE_SERVICE_ACCOUNT || !allowedOrigin) {
        throw new HttpError(500, "Worker configuration is incomplete.");
      }

      const account = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
      const projectId = account.project_id;

      const authorization = request.headers.get("Authorization") ?? "";

      if (!authorization.startsWith("Bearer ")) {
        throw new HttpError(401, "Sign in first.");
      }

      let uid;

      try {
        const { payload } = await jwtVerify(
          authorization.slice(7),
          firebaseKeys,
          {
            algorithms: ["RS256"],
            issuer: `https://securetoken.google.com/${projectId}`,
            audience: projectId,
            requiredClaims: ["sub", "exp", "iat", "auth_time"],
          },
        );

        const now = Math.floor(Date.now() / 1000);

        if (
          typeof payload.sub !== "string" ||
          payload.sub.length === 0 ||
          payload.sub.length > 128 ||
          typeof payload.iat !== "number" ||
          payload.iat > now + 30 ||
          typeof payload.auth_time !== "number" ||
          payload.auth_time > now + 30
        ) {
          throw new Error("Invalid Firebase claims.");
        }

        uid = payload.sub;
      } catch {
        throw new HttpError(401, "Your sign-in token is invalid or expired.");
      }

      const rawBody = await request.text();

      if (rawBody.length > 1024) {
        throw new HttpError(400, "Request is too large.");
      }

      let input;

      try {
        input = JSON.parse(rawBody);
      } catch {
        throw new HttpError(400, "Expected JSON.");
      }

      const messageId = input?.messageId;

      if (
        typeof messageId !== "string" ||
        !/^[A-Za-z0-9]{20}$/.test(messageId)
      ) {
        throw new HttpError(400, "Invalid message ID.");
      }

      const accessToken = await googleAccessToken(account);

      const baseUrl =
        `https://firestore.googleapis.com/v1/projects/` +
        `${encodeURIComponent(projectId)}/databases/(default)/documents`;

      const profile = await firestoreGet(
        baseUrl,
        documentPath("users", uid),
        accessToken,
      );

      const coupleId = stringField(profile, "coupleId");

      if (!coupleId) {
        throw new HttpError(403, "You are not paired.");
      }

      const couple = await firestoreGet(
        baseUrl,
        documentPath("couples", coupleId),
        accessToken,
      );

      const members = stringArrayField(couple, "memberIds");

      if (
        members.length !== 2 ||
        !members.every((member) => typeof member === "string") ||
        new Set(members).size !== 2 ||
        !members.includes(uid)
      ) {
        throw new HttpError(409, "Your partner has not joined yet.");
      }

      const message = await firestoreGet(
        baseUrl,
        documentPath("couples", coupleId, "messages", messageId),
        accessToken,
      );

      if (!message || stringField(message, "senderId") !== uid) {
        throw new HttpError(403, "You cannot notify for this message.");
      }

      const type = stringField(message, "type");
      const text = stringField(message, "text");

      if (
        !["note", "miss_you"].includes(type) ||
        typeof text !== "string" ||
        text.length === 0
      ) {
        throw new HttpError(400, "Unsupported message.");
      }

      const createdAt = Date.parse(
        message.fields?.createdAt?.timestampValue ?? "",
      );

      // Prevent using old saved messages to send unexpected alerts.
      if (
        !Number.isFinite(createdAt) ||
        Math.abs(Date.now() - createdAt) > 15 * 60 * 1000
      ) {
        throw new HttpError(400, "This message is too old to notify.");
      }

      const recipientId = members.find((member) => member !== uid);

      const deviceTokens = new Set();
      let pageToken = "";

      // Sufficient for up to 100 registered device records per account.
      for (let page = 0; page < 10; page++) {
        const url = new URL(
          `${baseUrl}/${documentPath("users", recipientId, "devices")}`,
        );

        url.searchParams.set("pageSize", "10");

        if (pageToken) {
          url.searchParams.set("pageToken", pageToken);
        }

        const response = await fetch(url, {
          headers: { Authorization: `Bearer ${accessToken}` },
        });

        if (!response.ok) {
          throw new HttpError(502, "Unable to load recipient devices.");
        }

        const result = await response.json();

        for (const device of result.documents ?? []) {
          const token = stringField(device, "token");

          if (
            stringField(device, "platform") === "android" &&
            typeof token === "string" &&
            token.length > 0
          ) {
            deviceTokens.add(token);
          }
        }

        pageToken = result.nextPageToken ?? "";

        if (!pageToken) break;
      }

      if (pageToken) {
        throw new HttpError(409, "Too many registered device records.");
      }

      if (deviceTokens.size === 0) {
        return reply(200, { status: "no_devices", sent: 0 });
      }

      // Atomically claim this message before sending.
      // Only one request can create this document.
      const claimUrl = new URL(
        `${baseUrl}/${documentPath(
          "couples",
          coupleId,
          "notificationAttempts",
        )}`,
      );
      claimUrl.searchParams.set("documentId", messageId);

      const claim = await fetch(claimUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          fields: {
            senderId: { stringValue: uid },
            attemptedAt: { timestampValue: new Date().toISOString() },
          },
        }),
      });

      if (claim.status === 409) {
        return reply(200, { status: "already_attempted" });
      }

      if (!claim.ok) {
        throw new HttpError(502, "Unable to record notification attempt.");
      }

      const senderName =
        stringField(profile, "displayName")?.trim().slice(0, 50) ||
        "Your person";

      const title =
        type === "miss_you"
          ? `${senderName} misses you 💗`
          : `${senderName} sent you a note 💌`;

      let sent = 0;

      // Sequential sending keeps resource usage modest for this small app.
      for (const token of deviceTokens) {
        const response = await fetch(
          `https://fcm.googleapis.com/v1/projects/` +
            `${encodeURIComponent(projectId)}/messages:send`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              message: {
                token,
                notification: {
                  title,
                  body: text.slice(0, 200),
                },
                data: {
                  coupleId,
                  messageId,
                  type,
                },
                android: {
                  priority: "HIGH",
                  ttl: "300s",
                },
              },
            }),
          },
        );

        if (response.ok) {
          sent++;
        } else {
          // Log status only: don't expose tokens or note contents.
          console.error("FCM send failed:", response.status);
        }
      }

      return reply(200, {
        status: sent > 0 ? "sent" : "delivery_failed",
        sent,
        failed: deviceTokens.size - sent,
      });
    } catch (error) {
      if (error instanceof HttpError) {
        return reply(error.status, { error: error.message });
      }

      console.error("Unexpected notification handler error.");
      return reply(500, { error: "Notification service failed." });
    }
  },
};