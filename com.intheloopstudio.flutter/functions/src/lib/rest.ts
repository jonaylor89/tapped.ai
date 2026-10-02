/* eslint-disable import/no-unresolved */
import { onRequest } from "firebase-functions/v2/https";
import { usersRef } from "./firebase";

export const getUserById = onRequest(async (req, res) => {
  const { id } = req.query;

  if (typeof id !== "string") {
    res.status(400).send("Invalid request");
    return;
  }

  const userSnap = await usersRef.doc(id).get();
  const userData = userSnap.data();

  res.send(userData);
});

