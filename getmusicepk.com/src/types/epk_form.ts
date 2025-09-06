import { 
    DocumentData, 
    QueryDocumentSnapshot, 
    SnapshotOptions,
    Timestamp,
} from "firebase/firestore";

export type EpkForm = {
  id: string;
  userId: string;
  artistName: string; 
  imageUrl: string;
  bio: string;
  location: string;
  jobs: string[];
  // spotifyId: string;
  instagramHandle?: string;
  tiktokHandle?: string;
  twitterHandle?: string;
  notableSongs: { title: string, plays: number }[];
  phoneNumber: string;
  timestamp: Timestamp;
};

export const epkFormConverter = {
  toFirestore: (epkForm: EpkForm): DocumentData => {
    return { ...epkForm };
  },
  fromFirestore: (doc: QueryDocumentSnapshot, options: SnapshotOptions): EpkForm => {
    const data = doc.data(options)!;
    return {
      id: data.id,
      userId: data.userId,
      artistName: data.artistName,
      imageUrl: data.imageUrl,
      bio: data.bio,
      location: data.location,
      jobs: data.jobs,
      // spotifyId: data.spotifyId,
      instagramHandle: data.instagramHandle,
      tiktokHandle: data.tiktokHandle,
      twitterHandle: data.twitterHandle,
      notableSongs: data.notableSongs,
      phoneNumber: data.phoneNumber,
      timestamp: data.timestamp,
    };
  }
};