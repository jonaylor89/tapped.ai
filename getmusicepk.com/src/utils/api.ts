import { httpsCallable } from "firebase/functions";
import { functions } from "@/utils/firebase";

export async function aiEnhanceBio({ userId }: {
    userId: string;
}) {
    const res = await httpsCallable<
        { userId: string; },
        { enhancedBio: string; }
    >(functions, 'generateEnhancedBio')({
        userId,
    });

    const enhancedBio = res.data.enhancedBio;

    return enhancedBio;
};