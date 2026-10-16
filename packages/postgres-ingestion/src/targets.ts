import type { Pool } from "pg";

export type ClaimedTarget = {
  id: string;
  source: string;
  source_key: string;
  url: string;
  venue_id: string | null;
  lease_token: string;
  lease_until: Date;
  attempts: number;
};
/** Scheduling/target creation remains operator-controlled; this never starts a worker or fetch. */
export async function claimTargets(pool: Pool, count: number, leaseSeconds = 300): Promise<ClaimedTarget[]> {
  if (
    !Number.isInteger(count) ||
    count < 1 ||
    count > 500 ||
    !Number.isInteger(leaseSeconds) ||
    leaseSeconds < 30 ||
    leaseSeconds > 3600
  )
    throw new Error("Invalid work claim bounds");
  return (await pool.query("SELECT * FROM claim_scrape_targets($1,$2)", [count, leaseSeconds])).rows;
}
export async function finishTarget(
  pool: Pool,
  target: Pick<ClaimedTarget, "id" | "lease_token">,
  nextFetch: Date,
  failure: string | null = null,
): Promise<boolean> {
  if (!Number.isFinite(nextFetch.getTime()) || nextFetch.getTime() <= Date.now())
    throw new Error("Invalid next fetch time");
  return (
    await pool.query("SELECT finish_scrape_target($1,$2,$3,$4) AS ok", [
      target.id,
      target.lease_token,
      nextFetch,
      failure,
    ])
  ).rows[0].ok;
}
