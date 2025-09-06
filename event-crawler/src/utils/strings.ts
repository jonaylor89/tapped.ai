
export function isEmpty(str: string | null | undefined): str is string {
  return str === null || str === undefined || str.trim() === "";
}