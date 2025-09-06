import { type ReadonlyURLSearchParams } from 'next/navigation';

const IS_SERVER = typeof window === 'undefined';

export const createUrl = (pathname: string, params: URLSearchParams | ReadonlyURLSearchParams) => {
  const paramsString = params.toString();
  const queryString = `${paramsString.length ? '?' : ''}${paramsString}`;

  return `${pathname}${queryString}`;
};

export function getUrl(path: string) {
  const baseURL = IS_SERVER ?
    process.env.NEXT_PUBLIC_SITE_URL! :
    window.location.origin;
  return new URL(path, baseURL).toString();
}
