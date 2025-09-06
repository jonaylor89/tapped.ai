
export async function POST(req: Request) {
  const url = new URL(req.url);
  console.log({ url });

  const { headers } = req;
  console.log({ headers });

  const body = await req.json();
  console.log({ body });

  return new Response('OK', { status: 200 });
}
