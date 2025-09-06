import { Model } from './model';

export type GenerateImageProps = {
    model?: Model;
    prompt: string;
    negativePrompt?: string;
    steps?: number;
    width?: number;
    height?: number;
    numberOfImages?: number;
    promptStrength?: number;
    seed?: number
}
