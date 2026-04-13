import axios, { AxiosInstance } from 'axios';

export class OllamaClient {
  private client: AxiosInstance;
  private endpoint: string;
  private currentModel: string;

  constructor(endpoint: string, defaultModel: string) {
    this.endpoint = endpoint;
    this.currentModel = defaultModel;
    this.client = axios.create({
      baseURL: endpoint,
      timeout: 30000,
    });
  }

  getCurrentModel(): string {
    return this.currentModel;
  }

  async checkHealth(): Promise<void> {
    try {
      const response = await this.client.get('/api/tags');
      if (!response.data) {
        throw new Error('Ollama server not responding');
      }
    } catch (error) {
      throw new Error(`Ollama health check failed: ${(error as Error).message}`);
    }
  }

  async listModels(): Promise<any[]> {
    const response = await this.client.get('/api/tags');
    return response.data.models || [];
  }

  async generate(prompt: string, model: string = this.currentModel): Promise<string> {
    try {
      const response = await this.client.post('/api/generate', {
        model,
        prompt,
        stream: false,
        temperature: 0.7,
        top_p: 0.95,
        num_predict: 2048,
      });
      return response.data.response || '';
    } catch (error) {
      throw new Error(`Generate failed: ${(error as Error).message}`);
    }
  }

  async *generateWithStream(
    prompt: string,
    model: string = this.currentModel
  ): AsyncGenerator<string> {
    try {
      const response = await this.client.post(
        '/api/generate',
        {
          model,
          prompt,
          stream: true,
          temperature: 0.7,
          top_p: 0.95,
          num_predict: 2048,
        },
        { responseType: 'stream' }
      );

      let buffer = '';
      for await (const chunk of response.data) {
        // Accumulate bytes into buffer, handling chunk boundaries
        buffer += chunk.toString('utf-8');

        // Split on newline but preserve incomplete lines
        const lines = buffer.split('\n');
        // Keep the last incomplete line (if any) in the buffer
        buffer = lines.pop() || '';

        // Process all complete lines
        for (const line of lines) {
          const trimmed = line.trim();
          if (trimmed) {
            try {
              const json = JSON.parse(trimmed);
              if (json.response) {
                yield json.response;
              }
            } catch (e) {
              // Skip non-JSON lines
            }
          }
        }
      }

      // Process any remaining buffered content
      if (buffer.trim()) {
        try {
          const json = JSON.parse(buffer.trim());
          if (json.response) {
            yield json.response;
          }
        } catch (e) {
          // Skip non-JSON lines
        }
      }
    } catch (error) {
      throw new Error(`Generate stream failed: ${(error as Error).message}`);
    }
  }

  async embed(text: string): Promise<number[]> {
    try {
      const response = await this.client.post('/api/embed', {
        model: this.currentModel,
        input: text,
      });
      return response.data.embeddings[0] || [];
    } catch (error) {
      throw new Error(`Embed failed: ${(error as Error).message}`);
    }
  }

  setSwitchModel(model: string): void {
    this.currentModel = model;
  }
}
