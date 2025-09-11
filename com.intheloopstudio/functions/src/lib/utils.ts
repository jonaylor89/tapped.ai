/* eslint-disable import/no-unresolved */

import type { CallableContext } from "firebase-functions/v1/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { tokensRef } from "./firebase";

const founderIds = [
  "8yYVxpQ7cURSzNfBsaBGF7A7kkv2", // Johannes
  "n4zIL6bOuPTqRC3dtsl6gyEBPQl1", // Ilias
];

export const isNullOrUndefined = (value: any): boolean => {
  return value === null || value === undefined;
};

export const getFileFromURL = (fileURL: string): string => {
  const fSlashes = fileURL.split("/");
  const fQuery = fSlashes[fSlashes.length - 1].split("?");
  const segments = fQuery[0].split("%2F");
  const fileName = segments.join("/");

  return fileName;
};

export const getFoundersDeviceTokens = async (): Promise<string[]> => {
  const deviceTokens = (
    await Promise.all(
      founderIds.map(
        async (founderId) => {

          const querySnapshot = await tokensRef
            .doc(founderId)
            .collection("tokens")
            .get();

          const tokens: string[] = querySnapshot.docs.map((snap) => snap.id);

          return tokens;
        })
    )
  ).flat();

  return deviceTokens;
}

export const authenticated = (context: CallableContext): void => {
  // Checking that the user is authenticated.
  if (!context.auth) {
    // Throwing an HttpsError so that the client gets the error details.
    throw new HttpsError(
      "failed-precondition",
      "The function must be called while authenticated."
    );
  }
};

export const authenticatedRequest = (request: CallableRequest): void => {
  // Checking that the user is authenticated.
  if (!request.auth) {
    // Throwing an HttpsError so that the client gets the error details.
    throw new HttpsError(
      "failed-precondition",
      "The function must be called while authenticated."
    );
  }
};

export const sanitizeUsername = (artistName: string): string => {
  // Convert name to lowercase
  let username = artistName.trim().toLowerCase();

  // Replace spaces with a hyphen
  username = username.replace(/\s+/g, "_");

  // Remove disallowed characters (only keep letters, numbers, hyphens, and underscores)
  username = username.replace(/[^a-z0-9_]/g, "");

  return username;
}

export const imageUrlToBase64 = async (imageUrl: string): Promise<string> => {
  try {
    // Fetch the image
    const response = await fetch(imageUrl);
      
    // Check if the fetch was successful
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
      
    // Get the image as a Blob
    const blob = await response.blob();
      
    // Create a FileReader instance
    const reader = new FileReader();
      
    // Create a promise to handle the asynchronous FileReader
    const base64String: string = await new Promise<string>((resolve, reject) => {
      reader.onloadend = () => {
        if (typeof reader.result === "string") {
          resolve(reader.result);
        } else {
          reject(new Error("FileReader result is not a string"));
        }
      };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
    
      
    // Remove the data URL prefix to get only the base64 string
    return base64String.split(",")[1];
  } catch (error) {
    console.error("Error converting image to base64:", error);
    throw error;
  }
}