import { GenerateImageProps } from '@/types/generate_image';
import { Model } from '@/types/model';

const LEAP_API_KEY = process.env.LEAP_API_KEY;
// const CALLBACK_URL = process.env.CALLBACK_URL;

export async function generateImage({
  model = Model.SDXL,
  prompt,
  negativePrompt = 'asymmetric, watermarks',
  steps = 50,
  width = 1024,
  height = 1024,
  numberOfImages = 1,
  promptStrength = 7,
  seed,
}: GenerateImageProps) {
  const url = `https://api.tryleap.ai/api/v1/images/models/${model}/inferences`;

  const options = {
    method: 'POST',
    headers: {
      'accept': 'application/json',
      'content-type': 'application/json',
      'authorization': `Bearer ${LEAP_API_KEY}`,
    },
    body: JSON.stringify({
      prompt,
      negativePrompt,
      steps,
      width,
      height,
      numberOfImages,
      promptStrength,
      seed,
      // webhookUrl: `${CALLBACK_URL}/api/leap_webhook}`,
    }),
  };

  const res = await fetch(url, options);
  return await res.json();
}

export async function getInference({ inferenceId, modelId }: {
    inferenceId: string,
    modelId: string,
}) {
  const url = `https://api.tryleap.ai/api/v1/images/models/${modelId}/inferences/${inferenceId}`;
  const options = {
    method: 'GET',
    headers: {
      accept: 'application/json',
      authorization: `Bearer ${LEAP_API_KEY}`,
    },
  };

  const res = await fetch(url, options);
  return await res.json();
}
