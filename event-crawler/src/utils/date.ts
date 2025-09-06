import { isEmpty } from "./strings";

export function addHours(initDate: Date, h: number): Date {
  const date = new Date(initDate);
  date.setHours(date.getHours() + h);
  return date;
}

export function getDateFromStr(dateStr: string | null | undefined, otherwise?: () => Date): Date {
  if (dateStr === null || dateStr === undefined || isEmpty(dateStr)) {
    return otherwise?.() ?? new Date();
  }

  return new Date(dateStr);
}