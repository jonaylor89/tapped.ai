
import { ImageResponse } from 'next/og';

export async function GET(req: Request) {
  const url = new URL(req.url);
  const imageUri = url.searchParams.get('image_uri');
  const explicitContent = url.searchParams.get('explicit_content') === 'true' ?
    true :
    false;
  const height = parseInt(url.searchParams.get('height') ?? '1024');
  const width = parseInt(url.searchParams.get('width') ?? '1024');

  console.log({ imageUri, explicitContent });

  if (imageUri === undefined || imageUri === null) {
    return Response.json(
      { error: 'no image uri provided' },
      { status: 400 }
    );
  }

  return new ImageResponse(
    <div style={{
      display: 'flex',
      width: '100%',
      height: '100%',
    }}>
      <img
        src={imageUri}
        alt="generated"
      />
      {explicitContent && (
        <img
          src="https://coverart.tapped.ai/images/explicit_content_warning.png"
          alt="explicit content warning"
          height={height * 0.1}
          style={{
            position: 'absolute',
            bottom: '2px',
            left: '2px',
          }}
        />
      )}
    </div>,
    {
      width,
      height,
    }
  );
}
