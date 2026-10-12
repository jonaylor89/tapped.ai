import OpenAI from "openai";

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
