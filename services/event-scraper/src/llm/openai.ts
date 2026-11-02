import type { FetchLike, LlmClient, LlmJsonRequest, LlmJsonResponse } from "../types.js";

/**
 * OpenAI-compatible Chat Completions client with JSON-schema structured output (`response_format.json_schema`,
 * strict mode). Works with any server implementing that API shape. Uses global fetch (injectable for tests).
 *
 * Env (see `llmClientFromEnv`): OPENAI_API_KEY (required), EVENT_SCRAPER_LLM_MODEL (default gpt-4o-mini),
 * EVENT_SCRAPER_LLM_BASE_URL (default https://api.openai.com/v1).
 */

export const DEFAULT_LLM_MODEL = "gpt-4o-mini";
export const DEFAULT_LLM_BASE_URL = "https://api.openai.com/v1";

export interface OpenAiCompatibleOptions {
  apiKey: string;
  model?: string;
  baseUrl?: string;
  fetchImpl?: FetchLike;
  /** Per-request timeout. Default 90s. */
  timeoutMs?: number;
  /** Retries on 429/5xx/network errors. Default 2. */
  maxRetries?: number;
  /** Backoff sleep (injectable for tests). */
  sleep?: (ms: number) => Promise<void>;
}

export class LlmError extends Error {
  constructor(
    message: string,
    readonly code: "http" | "refusal" | "invalid_json" | "truncated" | "network" | "timeout",
    readonly status: number | null = null,
  ) {
    super(message);
    this.name = "LlmError";
  }
}

interface ChatCompletionResponse {
  model?: string;
  choices?: Array<{
    finish_reason?: string;
    message?: { content?: string | null; refusal?: string | null };
  }>;
  usage?: { prompt_tokens?: number; completion_tokens?: number };
}

export class OpenAiCompatibleClient implements LlmClient {
  readonly model: string;
  private readonly apiKey: string;
  private readonly baseUrl: string;
  private readonly fetchImpl: FetchLike;
  private readonly timeoutMs: number;
  private readonly maxRetries: number;
  private readonly sleep: (ms: number) => Promise<void>;

  constructor(options: OpenAiCompatibleOptions) {
    if (!options.apiKey) throw new Error("OpenAiCompatibleClient requires an API key");
    this.apiKey = options.apiKey;
    this.model = options.model || DEFAULT_LLM_MODEL;
    this.baseUrl = (options.baseUrl || DEFAULT_LLM_BASE_URL).replace(/\/+$/, "");
    this.fetchImpl = options.fetchImpl ?? ((input, init) => fetch(input, init));
    this.timeoutMs = options.timeoutMs ?? 90_000;
    this.maxRetries = options.maxRetries ?? 2;
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  }

  /** The request body sent to /chat/completions (exposed for tests and debugging; contains no secrets). */
  buildBody(request: LlmJsonRequest): Record<string, unknown> {
    return {
      model: this.model,
      temperature: request.temperature ?? 0,
      max_tokens: request.maxOutputTokens ?? 4096,
      messages: [
        { role: "system", content: request.system },
        { role: "user", content: request.user },
      ],
      response_format: {
        type: "json_schema",
        json_schema: { name: request.schemaName, strict: true, schema: request.schema },
      },
    };
  }

  async completeJson(request: LlmJsonRequest): Promise<LlmJsonResponse> {
    const body = JSON.stringify(this.buildBody(request));
    let attempt = 0;
    for (;;) {
      try {
        return await this.once(body);
      } catch (error) {
        const retryable =
          error instanceof LlmError &&
          (error.code === "network" ||
            error.code === "timeout" ||
            (error.code === "http" && (error.status === 429 || (error.status ?? 0) >= 500)));
        if (!retryable || attempt >= this.maxRetries) throw error;
        attempt++;
        await this.sleep(1000 * 4 ** (attempt - 1));
      }
    }
  }

  private async once(body: string): Promise<LlmJsonResponse> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    let response: Response;
    try {
      response = await this.fetchImpl(`${this.baseUrl}/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${this.apiKey}` },
        body,
        signal: controller.signal,
      });
    } catch (error) {
      const aborted = controller.signal.aborted;
      throw new LlmError(
        aborted ? "LLM request timed out" : `LLM request failed: ${(error as Error).message}`,
        aborted ? "timeout" : "network",
      );
    } finally {
      clearTimeout(timer);
    }
    if (!response.ok) {
      // Error bodies may echo request details; keep only a short, key-free snippet.
      const snippet = (await response.text().catch(() => "")).slice(0, 300).replace(/sk-[A-Za-z0-9_-]+/g, "sk-***");
      throw new LlmError(`LLM HTTP ${response.status}: ${snippet}`, "http", response.status);
    }
    const payload = (await response.json()) as ChatCompletionResponse;
    const choice = payload.choices?.[0];
    if (choice?.message?.refusal) throw new LlmError(`LLM refused: ${choice.message.refusal.slice(0, 200)}`, "refusal");
    if (choice?.finish_reason === "length") throw new LlmError("LLM output truncated (max tokens)", "truncated");
    const content = choice?.message?.content;
    if (!content) throw new LlmError("LLM returned no content", "invalid_json");
    let data: unknown;
    try {
      data = JSON.parse(content);
    } catch {
      throw new LlmError("LLM returned invalid JSON", "invalid_json");
    }
    return {
      data,
      model: payload.model ?? this.model,
      inputTokens: payload.usage?.prompt_tokens ?? null,
      outputTokens: payload.usage?.completion_tokens ?? null,
    };
  }
}

/** Builds a client from env, or null when OPENAI_API_KEY is unset (LLM fallback disabled). Never logs the key. */
export function llmClientFromEnv(
  env: Record<string, string | undefined> = process.env,
  overrides: Partial<OpenAiCompatibleOptions> = {},
): OpenAiCompatibleClient | null {
  const apiKey = env.OPENAI_API_KEY?.trim();
  if (!apiKey) return null;
  return new OpenAiCompatibleClient({
    apiKey,
    model: env.EVENT_SCRAPER_LLM_MODEL?.trim() || DEFAULT_LLM_MODEL,
    baseUrl: env.EVENT_SCRAPER_LLM_BASE_URL?.trim() || DEFAULT_LLM_BASE_URL,
    ...overrides,
  });
}
