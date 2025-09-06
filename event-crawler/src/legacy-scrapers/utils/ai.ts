import { ChatOpenAI } from "@langchain/openai";
import { HumanMessage } from "@langchain/core/messages";

export const chatGpt = async (
  prompt: string,
  options?: {
    model?: string;
    temperature?: number;
  },
): Promise<string> => {
  const modelName = options?.model ?? "gpt-3.5-turbo";
  const model = new ChatOpenAI({
    modelName,
    ...options,
  });

  const message = new HumanMessage({
    content: [
      {
        type: "text",
        text: prompt,
      },
    ],
  });

  const res = await model.invoke([message]);

  const result = res.content.toString();

  return result;
};
