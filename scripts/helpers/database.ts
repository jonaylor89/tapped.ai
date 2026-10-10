export const DATABASE_URL = process.env.DATABASE_URL;

export function requireDatabaseUrl(): string {
  if (!DATABASE_URL) {
    throw new Error("DATABASE_URL is required");
  }
  return DATABASE_URL;
}
