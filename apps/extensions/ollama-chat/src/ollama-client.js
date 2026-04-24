import axios from 'axios';
export class OllamaClient {
    constructor(endpoint, defaultModel) {
        this.endpoint = endpoint;
        this.currentModel = defaultModel;
        this.client = axios.create({
            baseURL: endpoint,
            timeout: 30000,
        });
    }
    getCurrentModel() {
        return this.currentModel;
    }
    async checkHealth() {
        try {
            const response = await this.client.get('/api/tags');
            if (!response.data) {
                throw new Error('Ollama server not responding');
            }
        }
        catch (error) {
            throw new Error(`Ollama health check failed: ${error.message}`);
        }
    }
    async listModels() {
        const response = await this.client.get('/api/tags');
        return response.data.models || [];
    }
    async generate(prompt, model = this.currentModel) {
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
        }
        catch (error) {
            throw new Error(`Generate failed: ${error.message}`);
        }
    }
    async *generateWithStream(prompt, model = this.currentModel) {
        try {
            const response = await this.client.post('/api/generate', {
                model,
                prompt,
                stream: true,
                temperature: 0.7,
                top_p: 0.95,
                num_predict: 2048,
            }, { responseType: 'stream' });
            for await (const chunk of response.data) {
                const line = chunk.toString('utf-8').trim();
                if (line) {
                    try {
                        const json = JSON.parse(line);
                        if (json.response) {
                            yield json.response;
                        }
                    }
                    catch (e) {
                        // Skip non-JSON lines
                    }
                }
            }
        }
        catch (error) {
            throw new Error(`Generate stream failed: ${error.message}`);
        }
    }
    async embed(text) {
        try {
            const response = await this.client.post('/api/embed', {
                model: this.currentModel,
                input: text,
            });
            return response.data.embeddings[0] || [];
        }
        catch (error) {
            throw new Error(`Embed failed: ${error.message}`);
        }
    }
    setSwitchModel(model) {
        this.currentModel = model;
    }
}
//# sourceMappingURL=ollama-client.js.map