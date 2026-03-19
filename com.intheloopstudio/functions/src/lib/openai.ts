import OpenAI from "openai";

const SINGLE_MARKETING_PLAN_TEMPLATE = `
Please provide a detailed marketing strategy report for promoting {ARTIST_NAME}'s 
new single. You are assuming the role of a marketing manager at a independent 
record label and your conversational tone will be in spartan you 
will not use corporate jargon. The goal is to achieve impressive 
traction and grow a loyal fanbase. Include creative and 
cost-effective strategies promotion report.Your goal is 
to create a hyper specific marketing report for an artist 
whos releasing is a single coming out on {RELEASE_TIMELINE}. 
In this specific example you will be working for an artist 
named {ARTIST_NAME}. Their biggest genres are {ARTIST_GENRES} 
and the aesthetic of the single is {AESTHETIC}.
Finally, this single is leading to {MORE_TO_COME}.'
`;

const MARKETING_PLAN_TEMPLATE = `
Please provide a detailed marketing strategy report for promoting {ARTIST_NAME}'s 
new {RELEASE_TYPE}. You are assuming the role of a marketing manager at a independent 
record label and your conversational tone will be in spartan you 
will not use corporate jargon. The goal is to achieve impressive 
traction and grow a loyal fanbase. Include creative and 
cost-effective strategies promotion report.Your goal is 
to create a hyper specific marketing report for an artist 
whos releasing is a {RELEASE_TYPE} coming out on {RELEASE_TIMELINE}. 
In this specific example you will be working for an artist 
named {ARTIST_NAME}. The aesthetic of the single is {AESTHETIC}.
Finally, this {RELEASE_TYPE} is leading to {MORE_TO_COME}.


Format the response to be in markdown format.
`;

const ENHANCE_BIO_TEMPLATE = `Create a concise and engaging artist 
biography for {ARTIST_NAME}. 
Highlight their unique style, achievements, 
and what sets them apart in the music industry. 
Use the information provided, social media handles (if applicable
  twitter handle: {TWITTER_HANDLE},
  instagram handle: {INSTAGRAM_HANDLE},
  tiktok handle: {TIKTOK_HANDLE} 
), 
genre ({ARTIST_GENRES}), and any outstanding accomplishments, to craft a compelling two-paragraph 
artist introduction. Remember to keep it captivating and suitable for press and 
promotional materials. It should be no more than 100 words`;

export function formatTemplate(template: string, vars: Record<string, string>): string {
  let result = template;
  for (const [key, value] of Object.entries(vars)) {
    result = result.split(`{${key}}`).join(value);
  }
  return result;
}

export const chatGpt = async (
  prompt: string,
  options?: {
    model?: string;
    temperature?: number;
  },
): Promise<string> => {
  const client = new OpenAI();
  const res = await client.chat.completions.create({
    model: options?.model ?? "gpt-4-1106-preview",
    temperature: options?.temperature,
    messages: [{ role: "user", content: prompt }],
  });

  return res.choices[0]?.message?.content ?? "";
};

export async function generateBasicMarketingPlan({
  releaseType,
  singleName,
  aesthetic,
  releaseTimeline,
  moreToCome,
  targetAudience,
  artistName,
  apiKey,
}: {
  releaseType: string;
  singleName: string;
  aesthetic: string;
  releaseTimeline: string;
  moreToCome: string;
  targetAudience: string;
  artistName: string;
  apiKey: string;
}): Promise<{ content: string; prompt: string }> {
  process.env.OPENAI_API_KEY = apiKey;

  const vars = {
    RELEASE_TYPE: releaseType,
    SINGLE_NAME: singleName,
    AESTHETIC: aesthetic,
    RELEASE_TIMELINE: releaseTimeline,
    MORE_TO_COME: moreToCome,
    TARGET_AUDIENCE: targetAudience,
    ARTIST_NAME: artistName,
  };

  const formatted = formatTemplate(MARKETING_PLAN_TEMPLATE, vars);
  const content = await chatGpt(formatted);

  return { content, prompt: formatted };
}

export async function generateSingleBasicMarketingPlan({
  singleName,
  aesthetic,
  releaseTimeline,
  moreToCome,
  targetAudience,
  artistName,
  artistGenres,
  apiKey,
}: {
  singleName: string;
  aesthetic: string;
  releaseTimeline: string;
  moreToCome: string;
  targetAudience: string;
  artistName: string;
  artistGenres: string;
  apiKey: string;
}): Promise<{ content: string; prompt: string }> {
  process.env.OPENAI_API_KEY = apiKey;

  const vars = {
    SINGLE_NAME: singleName,
    AESTHETIC: aesthetic,
    RELEASE_TIMELINE: releaseTimeline,
    MORE_TO_COME: moreToCome,
    TARGET_AUDIENCE: targetAudience,
    ARTIST_NAME: artistName,
    ARTIST_GENRES: artistGenres,
  };

  const formatted = formatTemplate(SINGLE_MARKETING_PLAN_TEMPLATE, vars);
  const content = await chatGpt(formatted);

  return { content, prompt: formatted };
}

export async function basicEnhancedBio({
  artistName,
  twitterHandle,
  instagramHandle,
  tiktokHandle,
  artistGenres,
  apiKey,
}: {
  artistName: string;
  twitterHandle: string;
  instagramHandle: string;
  tiktokHandle: string;
  artistGenres: Array<string>;
  apiKey: string;
}): Promise<{ content: string; prompt: string }> {
  process.env.OPENAI_API_KEY = apiKey;

  const vars = {
    ARTIST_NAME: artistName,
    TWITTER_HANDLE: twitterHandle,
    INSTAGRAM_HANDLE: instagramHandle,
    TIKTOK_HANDLE: tiktokHandle,
    ARTIST_GENRES: artistGenres.join(", "),
  };

  const formatted = formatTemplate(ENHANCE_BIO_TEMPLATE, vars);
  const content = await chatGpt(formatted);

  return { content, prompt: formatted };
}
