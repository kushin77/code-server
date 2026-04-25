/**
 * @file apps/copilot-engine/src/finetuning.js
 * @module copilot-engine/finetuning
 * @description Fine-tuning manager for Phase 6 code generation LLM adaptation
 * 
 * Manages:
 * - Training dataset preparation and validation
 * - Fine-tuning job lifecycle (queued, running, completed)
 * - Model versioning and checkpoint management
 * - Quality metrics and validation reporting
 */

const fs = require('fs');
const path = require('path');

/**
 * FineTuningManager handles model fine-tuning lifecycle
 */
class FineTuningManager {
  constructor(config = {}) {
    this.backend = config.backend || 'claude'; // claude | ollama
    this.model = config.model || 'claude-sonnet-4';
    this.datasetPath = config.datasetPath || './datasets/code-generation-finetuning';
    this.checkpointDir = config.checkpointDir || './artifacts/finetuning-checkpoints';
    this.metricsPath = config.metricsPath || './artifacts/finetuning-metrics.json';
    
    // Training parameters
    this.epochs = config.epochs || 3;
    this.batchSize = config.batchSize || 8;
    this.learningRate = config.learningRate || 0.001;
    this.validationSplit = config.validationSplit || 0.2;
    
    // Job tracking
    this.jobs = new Map();
    this.metrics = this.loadMetrics();
    
    this.ensureDirectories();
  }

  /**
   * Ensure required directories exist
   */
  ensureDirectories() {
    [this.checkpointDir, path.dirname(this.datasetPath)].forEach(dir => {
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
    });
  }

  /**
   * Load metrics from persistent storage
   */
  loadMetrics() {
    if (fs.existsSync(this.metricsPath)) {
      try {
        return JSON.parse(fs.readFileSync(this.metricsPath, 'utf-8'));
      } catch (e) {
        console.warn(`Failed to load metrics from ${this.metricsPath}:`, e.message);
      }
    }
    return {
      runs: [],
      totalExamplesProcessed: 0,
      averageAccuracy: 0,
      latestCheckpoint: null,
    };
  }

  /**
   * Save metrics to persistent storage
   */
  saveMetrics() {
    fs.writeFileSync(this.metricsPath, JSON.stringify(this.metrics, null, 2));
  }

  /**
   * Prepare dataset for fine-tuning
   * @param {string} datasetPath - Path to dataset directory
   * @returns {Promise<Object>} Dataset split into train/validation/test
   */
  async prepareDataset(datasetPath = this.datasetPath) {
    console.log(`[FT] Preparing dataset from: ${datasetPath}`);
    
    const examplesDir = path.join(datasetPath, 'examples');
    
    if (!fs.existsSync(examplesDir)) {
      throw new Error(`Examples directory not found: ${examplesDir}`);
    }

    // Load all examples
    const files = fs.readdirSync(examplesDir).filter(f => f.endsWith('.json'));
    const examples = [];

    for (const file of files) {
      try {
        const content = JSON.parse(fs.readFileSync(path.join(examplesDir, file), 'utf-8'));
        examples.push(content);
      } catch (e) {
        console.warn(`Failed to parse example ${file}:`, e.message);
      }
    }

    if (examples.length === 0) {
      throw new Error(`No training examples found in ${examplesDir}`);
    }

    // Split into train/validation/test
    const shuffle = (arr) => arr.sort(() => Math.random() - 0.5);
    const shuffled = shuffle(examples);
    
    const trainSize = Math.floor(shuffled.length * (1 - this.validationSplit));
    const valSize = Math.floor((shuffled.length - trainSize) * 0.5);

    const dataset = {
      train: shuffled.slice(0, trainSize),
      validation: shuffled.slice(trainSize, trainSize + valSize),
      test: shuffled.slice(trainSize + valSize),
      metadata: {
        totalExamples: shuffled.length,
        trainCount: trainSize,
        validationCount: valSize,
        testCount: shuffled.length - trainSize - valSize,
        categories: [...new Set(examples.map(e => e.category))],
      }
    };

    console.log(`[FT] Dataset prepared: ${dataset.metadata.totalExamples} examples ` +
      `(train: ${dataset.metadata.trainCount}, validation: ${dataset.metadata.validationCount}, ` +
      `test: ${dataset.metadata.testCount})`);

    return dataset;
  }

  /**
   * Submit a fine-tuning job
   * @param {string} jobId - Unique job identifier
   * @param {Object} config - Fine-tuning configuration
   * @returns {Object} Job status
   */
  submitJob(jobId, config = {}) {
    console.log(`[FT] Submitting fine-tuning job: ${jobId}`);
    
    const job = {
      id: jobId,
      status: 'queued', // queued | running | completed | failed
      createdAt: new Date().toISOString(),
      startedAt: null,
      completedAt: null,
      model: config.model || this.model,
      backend: config.backend || this.backend,
      datasetPath: config.datasetPath || this.datasetPath,
      epochs: config.epochs || this.epochs,
      batchSize: config.batchSize || this.batchSize,
      learningRate: config.learningRate || this.learningRate,
      metrics: {
        totalExamples: 0,
        examplesProcessed: 0,
        currentEpoch: 0,
        currentLoss: 0,
        validationAccuracy: 0,
      },
      checkpointPath: null,
      errorMessage: null,
    };

    this.jobs.set(jobId, job);
    return job;
  }

  /**
   * Get job status
   * @param {string} jobId - Job identifier
   * @returns {Object|null} Job status
   */
  getJobStatus(jobId) {
    return this.jobs.get(jobId) || null;
  }

  /**
   * Update job progress
   * @param {string} jobId - Job identifier
   * @param {Object} update - Status update
   */
  updateJobProgress(jobId, update) {
    const job = this.jobs.get(jobId);
    if (!job) {
      throw new Error(`Job not found: ${jobId}`);
    }

    Object.assign(job.metrics, update);
    
    if (update.status) {
      job.status = update.status;
    }
    
    if (update.status === 'running' && !job.startedAt) {
      job.startedAt = new Date().toISOString();
    }
    
    if (update.status === 'completed' && !job.completedAt) {
      job.completedAt = new Date().toISOString();
    }

    console.log(`[FT] Job ${jobId} progress:`, job.metrics);
  }

  /**
   * Save checkpoint for a job
   * @param {string} jobId - Job identifier
   * @param {Object} checkpoint - Model checkpoint data
   */
  saveCheckpoint(jobId, checkpoint) {
    const job = this.jobs.get(jobId);
    if (!job) {
      throw new Error(`Job not found: ${jobId}`);
    }

    const checkpointFile = path.join(
      this.checkpointDir,
      `${jobId}-epoch-${checkpoint.epoch}.json`
    );

    const checkpointData = {
      jobId,
      epoch: checkpoint.epoch,
      timestamp: new Date().toISOString(),
      metrics: checkpoint.metrics,
      modelSnapshot: checkpoint.model, // Simplified; in production, save weights separately
    };

    fs.writeFileSync(checkpointFile, JSON.stringify(checkpointData, null, 2));
    job.checkpointPath = checkpointFile;

    console.log(`[FT] Checkpoint saved: ${checkpointFile}`);
    return checkpointFile;
  }

  /**
   * Validate training examples
   * @param {Array} examples - Training examples to validate
   * @returns {Object} Validation report
   */
  validateExamples(examples) {
    console.log(`[FT] Validating ${examples.length} training examples`);

    const report = {
      totalExamples: examples.length,
      validExamples: 0,
      invalidExamples: 0,
      issues: [],
      categories: {},
    };

    examples.forEach((example, idx) => {
      const errors = [];

      if (!example.input || typeof example.input !== 'object') {
        errors.push('Missing or invalid input field');
      }
      if (!example.output || typeof example.output !== 'object') {
        errors.push('Missing or invalid output field');
      }
      if (!example.input?.task_description) {
        errors.push('Missing task_description in input');
      }
      if (!example.output?.code) {
        errors.push('Missing code in output');
      }

      if (errors.length > 0) {
        report.invalidExamples++;
        report.issues.push({ exampleIndex: idx, errors });
      } else {
        report.validExamples++;
        const category = example.category || 'uncategorized';
        report.categories[category] = (report.categories[category] || 0) + 1;
      }
    });

    console.log(`[FT] Validation complete: ${report.validExamples}/${report.totalExamples} valid`);
    return report;
  }

  /**
   * Generate fine-tuning training manifest
   * @returns {Object} Training manifest ready for submission
   */
  async generateTrainingManifest() {
    console.log('[FT] Generating training manifest');

    const dataset = await this.prepareDataset();
    const validation = this.validateExamples(dataset.train);

    if (validation.invalidExamples > 0) {
      console.warn(`[FT] Warning: ${validation.invalidExamples} invalid examples detected`);
    }

    return {
      timestamp: new Date().toISOString(),
      model: this.model,
      backend: this.backend,
      training: {
        examples: dataset.train.length,
        epochs: this.epochs,
        batchSize: this.batchSize,
        learningRate: this.learningRate,
      },
      validation: {
        examples: dataset.validation.length,
        split: this.validationSplit,
      },
      test: {
        examples: dataset.test.length,
      },
      datasetQuality: validation,
      checkpointDir: this.checkpointDir,
    };
  }

  /**
   * Export metrics for monitoring
   * @returns {Object} Current fine-tuning metrics
   */
  exportMetrics() {
    const activeJobs = Array.from(this.jobs.values()).filter(j => j.status !== 'completed');
    
    return {
      metrics: this.metrics,
      activeJobs: activeJobs.length,
      jobs: Array.from(this.jobs.entries()).map(([id, job]) => ({
        id,
        status: job.status,
        createdAt: job.createdAt,
        progress: `${job.metrics.examplesProcessed}/${job.metrics.totalExamples}`,
      })),
    };
  }
}

module.exports = { FineTuningManager };
