// Compatibility endpoints delegate all application-data access to Rust.
export async function proxyToRust(path: string, body: Uint8Array, headers: Record<string, string>) {
  const baseUrl = (process.env.TAPPED_API_URL ?? "https://api.tapped.ai").replace(/\/+$/, "");
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15_000);
  try {
    const response = await fetch(`${baseUrl}${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", ...headers },
      body: new Uint8Array(body),
      signal: controller.signal,
      redirect: "error",
    });
    return {
      status: response.status,
      body: await response.text(),
      contentType: response.headers.get("content-type") ?? "application/json",
    };
  } finally {
    clearTimeout(timeout);
  }
}
