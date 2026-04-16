import axios, { AxiosInstance, CancelTokenSource } from 'axios';
import * as vscode from 'vscode';

/** Hyperparameters that callers can override per-request. */
export interface GenerateOptions {
  model?: string;
  temperature?: number;
  top_p?: number;
  num_predict?: number;
  /** Timeout in milliseconds. Defaults to config `ollama.timeoutMs` or 120 000. */
  timeoutMs?: number;
}

/** Parsed response chunk from the Ollama streaming NDJSON API. */
interface OllamaChunk {
  response?: string;
  done?: boolean;
  error?: string;
}

export class OllamaClient {
  private client: AxiosInstance;
  private readonly endpoint: string;
  private currentModel: string;

  constructor(endpoint: string, defaultModel: string) {
    this.endpoint = endpoint;
    this.currentModel = defaultModel;
    // Timeout is set per-request; use a generous default for the shared instance.
    this.client = axios.create({
      baseURL: endpoint,
      timeout: 0, // per-request timeouts are applied via CancelToken
    });
  }

  getCurrentModel(): string {
    return this.currentModel;
  }

  async checkHealth(): Promise<void> {
    try {
      const response = await this.client.get('/api/tags', { timeout: 10000 });
      if (!response.data) {
        throw new Error('Ollama server not responding');
      }
    } catch (error) {
      throw new Error(`Ollama health check failed: ${(error as Error).message}`);
    }
  }

  async listModels(): Promise<Array<{ name: string; size: number }>> {
    const response = await this.client.get<{ models: Array<{ name: string; size: number }> }>('/api/tags', { timeout: 10000 });
    return response.data.models ?? [];
  }

  /** Non-streaming generate — for short prompts where streaming isn't needed. */
  async generate(prompt: string, opts: GenerateOptions = {}): Promise<string> {
    const timeoutMs = this._resolveTimeout(opts);
    try {
      const response = await this.client.post<{ response: string }>(
        '/api/generate',
        this._buildBody(prompt, { ...opts, model: opts.model ?? this.currentModel }, false),
        { timeout: timeoutMs }
      );
      return response.data.response ?? '';
    } catch (error) {
      throw new Error(`Generate failed: ${(error as Error).message}`);
    }
  }

  /**
   * Streaming generate with:
   * - Frame-level NDJSON buffering (handles partial/multi-object chunks)
   * - Cancellation token propagation (VSCode CancellationToken)
   * - Configurable timeout via options or `ollama.timeoutMs` setting
   */
  async *generateWithStream(
    prompt: string,
    cancellationToken: vscode.CancellationToken,
    opts: GenerateOptions = {}
  ): AsyncGenerator<string> {
    const timeoutMs = this._resolveTimeout(opts);
    const axiosCancelSource: CancelTokenSource = axios.CancelToken.source();

    // Wire VSCode cancellation → Axios cancellation
    const vscodeCancelDisposable = cancellationToken.onCancellationRequested(() => {
      axiosCancelSource.cancel('Request cancelled by user');
    });

    // Timeout abort
    const timeoutHandle = setTimeout(() => {
      axiosCancelSource.cancel(`Request timed out after ${timeoutMs}ms`);
    }, timeoutMs);

    try {
      const response = await this.client.post(
        '/api/generate',
        this._buildBody(prompt, { ...opts, model: opts.model ?? this.currentModel }, true),
        {
          responseType: 'stream',
          cancelToken: axiosCancelSource.token,
        }
      );

      let buffer = '';

      for await (const rawChunk of response.data as AsyncIterable<Buffer>) {
        if (cancellationToken.isCancellationRequested) {
          axiosCancelSource.cancel('Request cancelled by user');
          break;
        }

        // Accumulate bytes and split on newlines — handles partial chunks correctly
        buffer += rawChunk.toString('utf-8');
        const lines = buffer.split('\n');
        // The last element may be an incomplete line — keep it in the buffer
        buffer = lines.pop() ?? '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed) continue;

          let parsed: OllamaChunk;
          try {
            parsed = JSON.parse(trimmed) as OllamaChunk;
          } catch {
            // Non-JSON line (e.g. HTTP trailer) — skip silently
            continue;
          }

          if (parsed.error) {
            throw new Error(`Ollama stream error: ${parsed.error}`);
          }
          if (parsed.response) {
            yield parsed.response;
          }
          if (parsed.done) {
            return;
          }
        }
      }

      // Flush any remaining buffer content
      if (buffer.trim()) {
        try {
          const parsed = JSON.parse(buffer.trim()) as OllamaChunk;
          if (parsed.response) yield parsed.response;
        } catch {
          // ignore trailing non-JSON
        }
      }
    } catch (error) {
      if (axios.isCancel(error)) {
        // Cancellation is not an error from the caller's perspective
        return;
      }
      throw new Error(`Generate stream failed: ${(error as Error).message}`);
    } finally {
      clearTimeout(timeoutHandle);
      vscodeCancelDisposable.dispose();
    }
  }

  async embed(text: string): Promise<number[]> {
    try {
      const response = await this.client.post<{ embeddings: number[][] }>('/api/embed', {
        model: this.currentModel,
        input: text,
      }, { timeout: 30000 });
      return response.data.embeddings[0] ?? [];
    } catch (error) {
      throw new Error(`Embed failed: ${(error as Error).message}`);
    }
  }

  setSwitchModel(model: string): void {
    this.currentModel = model;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  private _resolveTimeout(opts: GenerateOptions): number {
    if (opts.timeoutMs !== undefined) return opts.timeoutMs;
    const config = vscode.workspace.getConfiguration('ollama');
    return config.get<number>('timeoutMs') ?? 120_000;
  }

  private _resolveHyperparams(opts: GenerateOptions): { temperature: number; top_p: number; num_predict: number } {
    const config = vscode.workspace.getConfiguration('ollama');
    return {
      temperature: opts.temperature ?? config.get<number>('temperature') ?? 0.7,
      top_p:       opts.top_p      ?? config.get<number>('top_p')       ?? 0.95,
      num_predict: opts.num_predict ?? config.get<number>('numPredict')  ?? 2048,
    };
  }

  private _buildBody(
    prompt: string,
    opts: GenerateOptions & { model: string },
    stream: boolean
  ): Record<string, unknown> {
    const hp = this._resolveHyperparams(opts);
    return {
      model: opts.model,
      prompt,
      stream,
      temperature: hp.temperature,
      top_p:       hp.top_p,
      num_predict: hp.num_predict,
    };
  }
}
