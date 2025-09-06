import { ImageResponse } from "next/og";
import TappedTheme from "./tapped_theme";
import FunkyTheme from "./funky_theme";
import MinimalistTheme from "./minimalist_theme";
import { EPKComponent } from "@/types/epk_component";
import { EpkPayload } from "@/types/epk_payload";


const width = 900;
const height = 1200;

export const runtime = 'edge';

const themeComponents: Record<string, EPKComponent> = {
  tapped: TappedTheme,
  funky: FunkyTheme,
  minimalist: MinimalistTheme,
};

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const theme = searchParams.get('theme');
  const epkString = searchParams.get('epkData') ?? '';
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
  })
  console.log({ theme });

  let chosenFont: string;
  let chosenFontItalic: string;
  let chosenFontBold: string;
  let fontDataRegular;
  let fontDataItalic;
  let fontDataBold;

  if (theme === 'funky'){
      chosenFont = 'JosefinSans';
      chosenFontItalic = 'JosefinSansItalic';
      chosenFontBold = 'JosefinSansBold'
      fontDataRegular = await fetch(
          new URL('../fonts/JosefinSans-Medium.ttf', import.meta.url)
      ).then((res) => res.arrayBuffer());
  
      fontDataItalic = await fetch(
          new URL('../fonts/JosefinSans-Italic.ttf', import.meta.url)
      ).then((res) => res.arrayBuffer());
  
      fontDataBold = await fetch(
          new URL('../fonts/JosefinSans-Bold.ttf', import.meta.url)
      ).then((res) => res.arrayBuffer());
  } else if (theme === 'minimalist'){
      chosenFont = 'Arimo';
      chosenFontItalic = 'ArimoItalic';
      chosenFontBold = 'ArimoBold'
      fontDataRegular = await fetch(
          new URL('../fonts/Arimo-Medium.ttf', import.meta.url)
      ).then((res) => res.arrayBuffer());
  
      fontDataItalic = await fetch(
          new URL('../fonts/Arimo-Italic.ttf', import.meta.url)
      ).then((res) => res.arrayBuffer());
  
      fontDataBold = await fetch(
          new URL('../fonts/Arimo-Bold.ttf', import.meta.url)
      ).then((res) => res.arrayBuffer());
  } else {
      chosenFont = 'Inter';
      chosenFontItalic = 'InterItalic';
      chosenFontBold = 'InterBold'
      fontDataRegular = await fetch(
          new URL('../fonts/Inter-Medium.ttf', import.meta.url)
      ).then((res) => res.arrayBuffer());
  
      fontDataItalic = await fetch(
          new URL('../fonts/InterTight-Italic.ttf', import.meta.url)
      ).then((res) => res.arrayBuffer());
  
      fontDataBold = await fetch(
          new URL('../fonts/Inter-Bold.ttf', import.meta.url)
      ).then((res) => res.arrayBuffer());
  }

  const ThemeComponent: EPKComponent = themeComponents[theme || 'tapped'];

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

{/* <div
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
        </div> */}