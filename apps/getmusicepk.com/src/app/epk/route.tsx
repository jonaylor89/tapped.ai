import { ImageResponse } from "next/og";
import type { EPKComponent } from "@/types/epk_component";
import type { EpkPayload } from "@/types/epk_payload";
import FunkyTheme from "./funky_theme";
import MinimalistTheme from "./minimalist_theme";
import TappedTheme from "./tapped_theme";

const width = 900;
const height = 1200;

export const runtime = "edge";

const themeComponents: Record<string, EPKComponent> = {
  tapped: TappedTheme,
  funky: FunkyTheme,
  minimalist: MinimalistTheme,
};

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const theme = searchParams.get("theme");
  const epkString = searchParams.get("epkData") ?? "";
  const epkForm = JSON.parse(epkString) as EpkPayload;

  const {
    artistName,
    bio,
    imageUrl,
    tiktokHandle,
    instagramHandle,
    twitterHandle,
    tappedRating,
    phoneNumber,
    notableSongs,
    location,
    jobs,
  } = epkForm;
  console.log({
    artistName,
    bio,
    imageUrl,
    tappedRating,
    tiktokHandle,
    instagramHandle,
    twitterHandle,
    phoneNumber,
  });
  console.log({ theme });

  let chosenFont: string;
  let chosenFontItalic: string;
  let chosenFontBold: string;
  let fontDataRegular;
  let fontDataItalic;
  let fontDataBold;

  const baseUrl = process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : "https://getmusicepk.com";

  if (theme === "funky") {
    chosenFont = "JosefinSans";
    chosenFontItalic = "JosefinSansItalic";
    chosenFontBold = "JosefinSansBold";
    fontDataRegular = await fetch(`${baseUrl}/fonts/JosefinSans-Medium.ttf`).then((res) => res.arrayBuffer());
    fontDataItalic = await fetch(`${baseUrl}/fonts/JosefinSans-Italic.ttf`).then((res) => res.arrayBuffer());
    fontDataBold = await fetch(`${baseUrl}/fonts/JosefinSans-Bold.ttf`).then((res) => res.arrayBuffer());
  } else if (theme === "minimalist") {
    chosenFont = "Arimo";
    chosenFontItalic = "ArimoItalic";
    chosenFontBold = "ArimoBold";
    fontDataRegular = await fetch(`${baseUrl}/fonts/Arimo-Medium.ttf`).then((res) => res.arrayBuffer());
    fontDataItalic = await fetch(`${baseUrl}/fonts/Arimo-Italic.ttf`).then((res) => res.arrayBuffer());
    fontDataBold = await fetch(`${baseUrl}/fonts/Arimo-Bold.ttf`).then((res) => res.arrayBuffer());
  } else {
    chosenFont = "Inter";
    chosenFontItalic = "InterItalic";
    chosenFontBold = "InterBold";
    fontDataRegular = await fetch(`${baseUrl}/fonts/Inter-Medium.ttf`).then((res) => res.arrayBuffer());
    fontDataItalic = await fetch(`${baseUrl}/fonts/InterTight-Italic.ttf`).then((res) => res.arrayBuffer());
    fontDataBold = await fetch(`${baseUrl}/fonts/Inter-Bold.ttf`).then((res) => res.arrayBuffer());
  }

  const ThemeComponent: EPKComponent = themeComponents[theme || "tapped"];

  return new ImageResponse(
    <ThemeComponent
      artistName={artistName}
      location={location}
      notableSongs={notableSongs}
      jobs={jobs}
      bio={bio}
      imageUrl={imageUrl}
      tappedRating={tappedRating}
      tiktokHandle={tiktokHandle}
      instagramHandle={instagramHandle}
      twitterHandle={twitterHandle}
      phoneNumber={phoneNumber}
    />,
    {
      height,
      width,
      debug: false,
      fonts: [
        {
          name: chosenFont,
          data: fontDataRegular,
        },
        {
          name: chosenFontItalic,
          data: fontDataItalic,
        },
        {
          name: chosenFontBold,
          data: fontDataBold,
        },
      ],
    },
  );
}

{
  /* <div
          style={{
            display: 'flex',
            flexDirection: 'column',
          }}
        >

          <svg
            bgColor='white'
            bgD={cells
              .map((row, rowIndex) =>
                row.map((cell, cellIndex) => (!cell ? `M ${cellIndex} ${rowIndex} l 1 0 0 1 -1 0 Z` : "")).join(" "),
              )
              .join(" ")}
            fgColor='black'
            fgD={cells
              .map((row, rowIndex) =>
                row.map((cell, cellIndex) => (cell ? `M ${cellIndex} ${rowIndex} l 1 0 0 1 -1 0 Z` : "")).join(" "),
              )
              .join(" ")}
            size={256}
            viewBoxSize={cells.length}
            height={size} 
            viewBox={`0 0 ${viewBoxSize} ${viewBoxSize}`} width={256}>
            {'Niral Desai' ? <title>{'Niral Desai'}</title> : null}
            <path d={bgD} fill='white' />
            <path d={fgD} fill='black' />
          </svg>
        </div> */
}
