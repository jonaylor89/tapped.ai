import { redis } from '@/utils/redis';

export async function POST(req: Request) {
  const json = await req.json();
  const { body, sourceMessageId } = json;
  const decoded = atob(body);

  await redis.set(sourceMessageId, decoded);

  return Response.json({ success: true });
}
