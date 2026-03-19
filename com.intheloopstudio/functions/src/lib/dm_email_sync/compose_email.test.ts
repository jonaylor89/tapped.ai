import type { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it, type Mock, vi } from "vitest";
import type { UserModel } from "../../types/models";

vi.mock("../openai", () => ({
  chatGpt: vi.fn().mockResolvedValue("mocked AI response"),
}));

vi.mock("../firebase", () => ({
  bookingsRef: {
    where: vi.fn().mockReturnValue({
      get: vi.fn().mockResolvedValue({ docs: [] }),
    }),
  },
  usersRef: {
    doc: vi.fn().mockReturnValue({
      get: vi.fn().mockResolvedValue({ data: () => ({}) }),
    }),
  },
}));

import { chatGpt } from "../openai";
import { composeVenueEmail } from "./compose_email";

const makeTimestamp = (iso: string) =>
  ({
    toDate: () => new Date(iso),
  }) as unknown as Timestamp;

const performer: UserModel = {
  id: "p1",
  email: "artist@test.com",
  unclaimed: false,
  timestamp: makeTimestamp("2024-01-01"),
  username: "coolartist",
  artistName: "Cool Artist",
  bio: "",
  occupations: ["performer"],
  badgesCount: 0,
  emailNotifications: { appReleases: true, tappedUpdates: true, bookingRequests: true, directMessages: true },
  pushNotifications: { appReleases: true, tappedUpdates: true, bookingRequests: true, directMessages: true },
  deleted: false,
  socialFollowing: {
    tiktokFollowers: 0,
    instagramFollowers: 0,
    twitterFollowers: 0,
    facebookFollowers: 0,
    soundcloudFollowers: 0,
    audiusFollowers: 0,
    twitchFollowers: 0,
  },
  performerInfo: { genres: ["rock", "indie"], reviewCount: 0, label: "" },
};

const venue: UserModel = {
  ...performer,
  id: "v1",
  username: "thevenue",
  artistName: "The Venue",
  occupations: ["venue"],
  performerInfo: null,
};

describe("composeVenueEmail", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns subject with performer display name", async () => {
    const result = await composeVenueEmail({
      performer,
      venue,
      note: "",
      opportunities: [],
    });

    expect(result.subject).toBe("Performance Inquiry from Cool Artist");
  });

  it("returns body from chatGpt", async () => {
    const result = await composeVenueEmail({
      performer,
      venue,
      note: "",
      opportunities: [],
    });

    expect(result.body).toBe("mocked AI response");
  });

  it("includes venue and performer names in prompt", async () => {
    await composeVenueEmail({
      performer,
      venue,
      note: "",
      opportunities: [],
    });

    const prompt = (chatGpt as Mock).mock.calls[0][0] as string;
    expect(prompt).toContain("The Venue");
    expect(prompt).toContain("Cool Artist");
  });

  it("includes genres in prompt", async () => {
    await composeVenueEmail({
      performer,
      venue,
      note: "",
      opportunities: [],
    });

    const prompt = (chatGpt as Mock).mock.calls[0][0] as string;
    expect(prompt).toContain("rock, indie");
  });

  it("includes note in prompt when provided", async () => {
    await composeVenueEmail({
      performer,
      venue,
      note: "Available Friday nights",
      opportunities: [],
    });

    const prompt = (chatGpt as Mock).mock.calls[0][0] as string;
    expect(prompt).toContain("Available Friday nights");
  });

  it("includes previous email thread in prompt when provided", async () => {
    await composeVenueEmail({
      performer,
      venue,
      note: "",
      opportunities: [],
      previousEmails: [
        { TextBody: "First email body", From: "a@b.com", To: "c@d.com" } as any,
        { TextBody: "Reply body", From: "c@d.com", To: "a@b.com" } as any,
      ],
    });

    const prompt = (chatGpt as Mock).mock.calls[0][0] as string;
    expect(prompt).toContain("Previous Conversations/Email Thread");
    expect(prompt).toContain("First email body");
    expect(prompt).toContain("Reply body");
  });

  it("does not include email thread section when no previous emails", async () => {
    await composeVenueEmail({
      performer,
      venue,
      note: "",
      opportunities: [],
    });

    const prompt = (chatGpt as Mock).mock.calls[0][0] as string;
    expect(prompt).not.toContain("Previous Conversations/Email Thread");
  });

  it("uses opportunity prompt when opportunities are provided", async () => {
    await composeVenueEmail({
      performer,
      venue,
      note: "",
      opportunities: [
        {
          id: "op1",
          userId: "u1",
          title: "Friday Night Live",
          description: "A live show",
          placeId: "p1",
          geohash: "abc",
          lat: 0,
          lng: 0,
          timestamp: makeTimestamp("2024-01-01"),
          startTime: makeTimestamp("2024-06-15"),
          endTime: makeTimestamp("2024-06-16"),
          isPaid: true,
          touched: null,
        },
      ],
    });

    const prompt = (chatGpt as Mock).mock.calls[0][0] as string;
    expect(prompt).toContain("Friday Night Live");
    expect(prompt).toContain("you're open to performing");
  });

  it("falls back to username when artistName is empty", async () => {
    const noNamePerformer = { ...performer, artistName: "" };

    const result = await composeVenueEmail({
      performer: noNamePerformer,
      venue,
      note: "",
      opportunities: [],
    });

    expect(result.subject).toBe("Performance Inquiry from coolartist");
  });
});
