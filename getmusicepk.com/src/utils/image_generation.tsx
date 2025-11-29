import satori from "satori";
import FunkyTheme from "@/app/epk/funky_theme";
import MinimalistTheme from "@/app/epk/minimalist_theme";
import TappedTheme from "@/app/epk/tapped_theme";
import type { EPKComponent } from "@/types/epk_component";
import type { EpkPayload } from "@/types/epk_payload";

const themeComponents: Record<string, EPKComponent> = {
  tapped: TappedTheme,
  funky: FunkyTheme,
  minimalist: MinimalistTheme,
};

let chosenFont: string;
let chosenFontItalic: string;
let chosenFontBold: string;

export async function generateEpkSvg({
  theme,
  height,
  width,
  artistName,
  bio,
  imageUrl,
  tappedRating,
  phoneNumber,
  location,
  notableSongs,
  jobs,
  twitterHandle,
  tiktokHandle,
  instagramHandle,
}: EpkPayload & {
  theme: string;
  height: number;
  width: number;
}): Promise<string> {
  let fontDataRegular;
  let fontDataItalic;
  let fontDataBold;

  const baseUrl =
    typeof window !== "undefined"
      ? window.location.origin
      : process.env.VERCEL_URL
        ? `https://${process.env.VERCEL_URL}`
        : "https://getmusicepk.com";

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

  const result = await satori(
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

  return result;
}
