import { storage } from "../firebase";

export async function uploadImageToFirebase(
  imageData: Buffer,
  bookingId: string,
): Promise<string | null> {
  try {
    const filePath = `images/bookings/${bookingId}/${bookingId}.jpeg`;
    const bucket = storage.bucket("in-the-loop-306520.appspot.com");
    await bucket.file(filePath).save(imageData, {
      metadata: {
        contentType: "image/jpeg",
      },
    });

    // Generate signed URL for the uploaded image
    const signedUrl = await bucket.file(filePath).getSignedUrl({
      action: "read",
      expires: "03-01-2500", // Adjust the expiration date as needed
    });

    return signedUrl[0];
  } catch (error) {
    console.log("[!!!] Error uploading image:", error);
    return null;
  }
}
