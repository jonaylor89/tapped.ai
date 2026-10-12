// Only Auth side effects and HTTP compatibility endpoints are deployable.
// Legacy Firestore modules remain as reference; never re-export them or use export *.
export { sendWelcomeEmailOnUserCreated } from "./lib/email_triggers";
export { addUserToMailchimpOnCreated } from "./lib/mailchimp";
export { notifyFoundersOnSignUp, notifyFoundersOnUserDelete } from "./lib/signups";
export {
  getArtistBySpotifyId,
  getTopTracksByArtistId,
  spotifyAuthorizeCodeGrant,
  spotifyRedirect,
  spotifyRefreshToken,
} from "./lib/spotify";
export { deleteStreamUser } from "./lib/stream";
export { inboundEmailWebhook, streamBeforeMessageWebhook } from "./lib/webhooks";
