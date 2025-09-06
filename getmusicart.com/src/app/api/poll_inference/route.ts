import { getInference } from '@/utils/leap';

export async function GET(req: Request) {
  const { searchParams } = new URL(req.url);
  const inferenceId = searchParams.get('inferenceId');
  const modelId = searchParams.get('modelId');
  if (!inferenceId || !modelId) {
    return Response.json(
      { error: 'Bad Request' },
      { status: 400 },
    );
  }

  console.log({ inferenceId, modelId });
  const json = await getInference({ inferenceId, modelId });
  console.log({ getInferenceRes: json });

  return Response.json(json);
}
