/**
 * Flux Configuration Builder
 * Generates Flux CD configurations for automated GitOps deployments
 */

export interface FluxHelmConfig {
  name: string;
  namespace: string;
  chart: string;
  chartVersion: string;
  targetNamespace: string;
  values: Record<string, unknown>;
  interval: string; // e.g., "5m"
  timeout: string; // e.g., "5m"
  releaseName: string;
  skipCrds?: boolean;
  install?: {
    crds: 'create' | 'skip' | 'none';
  };
  upgrade?: {
    crds: 'create' | 'skip' | 'none';
  };
}

export interface FluxImagePolicy {
  name: string;
  namespace: string;
  imageRepository: string;
  policy: {
    semver?: {
      range: string; // e.g., "1.0.x"
    };
    numeric?: {
      order: 'asc' | 'desc';
    };
    alphabetical?: {
      order: 'asc' | 'desc';
    };
  };
}

export interface FluxKustomization {
  name: string;
  namespace: string;
  sourceRef: {
    kind: 'GitRepository' | 'Bucket';
    name: string;
  };
  path: string;
  interval: string; // e.g., "5m"
  timeout: string; // e.g.: "5m"
  prune: boolean;
  force: boolean;
  postBuild?: {
    substitute?: Record<string, string>;
    substituteFrom?: Array<{
      kind: 'ConfigMap' | 'Secret';
      name: string;
    }>;
  };
  patches?: Array<{
    target: {
      group?: string;
      version: string;
      kind: string;
      name: string;
      namespace?: string;
    };
    patch: string;
  }>;
  dependsOn?: Array<{
    name: string;
    namespace?: string;
  }>;
}

export interface FluxDeploymentConfig {
  gitRepository: {
    name: string;
    namespace: string;
    url: string;
    branch: string;
    interval: string;
    timeout: string;
    authentication?: {
      type: 'ssh' | 'https' | 'token';
      secretRef: string;
    };
  };
  helmRepositories: FluxHelmConfig[];
  imagePolicies: FluxImagePolicy[];
  kustomizations: FluxKustomization[];
  imageUpdateAutomation?: {
    name: string;
    namespace: string;
    checkInterval: string;
    updateStrategy: {
      strategy: 'Setters' | 'ChartVersion';
    };
    sourceRef: {
      kind: 'GitRepository';
      name: string;
    };
    gitCommitTemplate: {
      description: string;
      author: string;
    };
    push?: {
      branch: string;
    };
  };
}

/**
 * Flux Configuration Builder
 */
export class FluxConfigBuilder {
  private config: Partial<FluxDeploymentConfig> = {};

  /**
   * Create new configuration
   */
  static create(): FluxConfigBuilder {
    return new FluxConfigBuilder();
  }

  /**
   * Set Git repository source
   */
  setGitRepository(name: string, url: string, branch: string, interval: string = '5m'): this {
    this.config.gitRepository = {
      name,
      namespace: 'flux-system',
      url,
      branch,
      interval,
      timeout: '1m',
    };
    return this;
  }

  /**
   * Add Git authentication
   */
  setGitAuthentication(type: 'ssh' | 'https' | 'token', secretRef: string): this {
    if (this.config.gitRepository) {
      this.config.gitRepository.authentication = {
        type,
        secretRef,
      };
    }
    return this;
  }

  /**
   * Add Helm repository configuration
   */
  addHelmRepository(config: FluxHelmConfig): this {
    if (!this.config.helmRepositories) {
      this.config.helmRepositories = [];
    }
    this.config.helmRepositories.push(config);
    return this;
  }

  /**
   * Add image policy for automated version detection
   */
  addImagePolicy(policy: FluxImagePolicy): this {
    if (!this.config.imagePolicies) {
      this.config.imagePolicies = [];
    }
    this.config.imagePolicies.push(policy);
    return this;
  }

  /**
   * Add Kustomization target
   */
  addKustomization(kustomization: FluxKustomization): this {
    if (!this.config.kustomizations) {
      this.config.kustomizations = [];
    }
    this.config.kustomizations.push(kustomization);
    return this;
  }

  /**
   * Enable automated image updates
   */
  enableImageAutomation(gitBranch: string = 'automated-updates'): this {
    if (!this.config.gitRepository) {
      throw new Error('Git repository must be configured first');
    }

    this.config.imageUpdateAutomation = {
      name: 'image-automation',
      namespace: 'flux-system',
      checkInterval: '5m',
      updateStrategy: {
        strategy: 'ChartVersion',
      },
      sourceRef: {
        kind: 'GitRepository',
        name: this.config.gitRepository.name,
      },
      gitCommitTemplate: {
        description: 'Update image versions [ci skip]',
        author: 'flux-automation <noreply@kushnir.cloud>',
      },
      push: {
        branch: gitBranch,
      },
    };
    return this;
  }

  /**
   * Generate Flux HelmRepository YAML
   */
  generateHelmRepositoryYaml(name: string, url: string, interval: string = '1h'): string {
    return `apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: ${name}
  namespace: flux-system
spec:
  interval: ${interval}
  url: ${url}
  passCredentials: false
`;
  }

  /**
   * Generate Flux HelmRelease YAML
   */
  generateHelmReleaseYaml(helmConfig: FluxHelmConfig): string {
    const valuesYaml = this.mapToYaml('values', helmConfig.values);

    return `apiVersion: helm.toolkit.fluxcd.io/v2beta2
kind: HelmRelease
metadata:
  name: ${helmConfig.name}
  namespace: ${helmConfig.namespace}
spec:
  releaseName: ${helmConfig.releaseName}
  targetNamespace: ${helmConfig.targetNamespace}
  chart:
    spec:
      chart: ${helmConfig.chart}
      version: ${helmConfig.chartVersion}
      sourceRef:
        kind: HelmRepository
        name: ${helmConfig.name}-repo
        namespace: flux-system
  interval: ${helmConfig.interval}
  timeout: ${helmConfig.timeout}
  install:
    crds: create
    remediation:
      retries: 3
  upgrade:
    crds: create
    remediation:
      retries: 3
  rollback:
    recreate: true
  postRenderers:
    - kustomize: {}
${valuesYaml}
`;
  }

  /**
   * Generate Flux Kustomization YAML
   */
  generateKustomizationYaml(kustomization: FluxKustomization): string {
    let dependsOnYaml = '';
    if (kustomization.dependsOn && kustomization.dependsOn.length > 0) {
      dependsOnYaml = `
  dependsOn:
`;
      for (const dep of kustomization.dependsOn) {
        dependsOnYaml += `    - name: ${dep.name}\n`;
        if (dep.namespace) {
          dependsOnYaml += `      namespace: ${dep.namespace}\n`;
        }
      }
    }

    let patchesYaml = '';
    if (kustomization.patches && kustomization.patches.length > 0) {
      patchesYaml = `
  patches:
`;
      for (const patch of kustomization.patches) {
        patchesYaml += `    - target:
        group: ${patch.target.group || ''}
        version: ${patch.target.version}
        kind: ${patch.target.kind}
        name: ${patch.target.name}
`;
        if (patch.target.namespace) {
          patchesYaml += `        namespace: ${patch.target.namespace}\n`;
        }
        patchesYaml += `      patch: |\n${this.indentString(patch.patch, 8)}\n`;
      }
    }

    return `apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ${kustomization.name}
  namespace: ${kustomization.namespace}
spec:
  interval: ${kustomization.interval}
  timeout: ${kustomization.timeout}
  sourceRef:
    kind: ${kustomization.sourceRef.kind}
    name: ${kustomization.sourceRef.name}
  path: ${kustomization.path}
  prune: ${kustomization.prune}
  force: ${kustomization.force}
  wait: true
  validation: client
${dependsOnYaml}${patchesYaml}`;
  }

  /**
   * Generate Flux ImageRepository YAML
   */
  generateImageRepositoryYaml(policy: FluxImagePolicy): string {
    return `apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: ${policy.name}
  namespace: ${policy.namespace}
spec:
  image: ${policy.imageRepository}
  interval: 5m
`;
  }

  /**
   * Generate Flux ImagePolicy YAML
   */
  generateImagePolicyYaml(policy: FluxImagePolicy): string {
    let policySpec = '';

    if (policy.policy.semver) {
      policySpec = `
spec:
  imageRepositoryRef:
    name: ${policy.name}
  policy:
    semver:
      range: ${policy.policy.semver.range}
`;
    } else if (policy.policy.numeric) {
      policySpec = `
spec:
  imageRepositoryRef:
    name: ${policy.name}
  policy:
    numeric:
      order: ${policy.policy.numeric.order}
`;
    }

    return `apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: ${policy.name}-policy
  namespace: ${policy.namespace}
${policySpec}`;
  }

  /**
   * Generate complete Flux configuration YAML
   */
  generateCompleteConfig(): string {
    const yamls: string[] = [];

    if (this.config.gitRepository) {
      yamls.push(this.generateGitRepositoryYaml());
    }

    if (this.config.helmRepositories) {
      for (const helm of this.config.helmRepositories) {
        yamls.push(this.generateHelmRepositoryYaml(helm.name, helm.chart));
        yamls.push(this.generateHelmReleaseYaml(helm));
      }
    }

    if (this.config.imagePolicies) {
      for (const policy of this.config.imagePolicies) {
        yamls.push(this.generateImageRepositoryYaml(policy));
        yamls.push(this.generateImagePolicyYaml(policy));
      }
    }

    if (this.config.kustomizations) {
      for (const k of this.config.kustomizations) {
        yamls.push(this.generateKustomizationYaml(k));
      }
    }

    if (this.config.imageUpdateAutomation) {
      yamls.push(this.generateImageUpdateAutomationYaml());
    }

    return yamls.join('\n---\n');
  }

  /**
   * Generate Git repository source YAML
   */
  private generateGitRepositoryYaml(): string {
    const git = this.config.gitRepository!;
    let secretRef = '';

    if (git.authentication) {
      secretRef = `
    secretRef:
      name: ${git.authentication.secretRef}`;
    }

    return `apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: GitRepository
metadata:
  name: ${git.name}
  namespace: ${git.namespace}
spec:
  interval: ${git.interval}
  url: ${git.url}
  ref:
    branch: ${git.branch}${secretRef}
`;
  }

  /**
   * Generate image automation YAML
   */
  private generateImageUpdateAutomationYaml(): string {
    const automation = this.config.imageUpdateAutomation!;

    return `apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: ${automation.name}
  namespace: ${automation.namespace}
spec:
  interval: ${automation.checkInterval}
  sourceRef:
    kind: ${automation.sourceRef.kind}
    name: ${automation.sourceRef.name}
  git:
    checkout:
      ref:
        branch: ${automation.push?.branch || 'main'}
    push:
      branch: ${automation.push?.branch || 'main'}
    commit:
      author:
        email: ${automation.gitCommitTemplate.author.split(' ')[0]}
        name: Flux Automation
      messageTemplate: |
        ${automation.gitCommitTemplate.description}
  update:
    strategy: ${automation.updateStrategy.strategy}
`;
  }

  /**
   * Helper: convert object to YAML indented format
   */
  private mapToYaml(key: string, obj: Record<string, unknown>, indent: number = 2): string {
    const lines: string[] = [key + ':'];
    this.objectToYaml(obj, indent).split('\n').forEach((line) => {
      lines.push('  ' + line);
    });
    return lines.join('\n');
  }

  /**
   * Helper: convert object to YAML format
   */
  private objectToYaml(obj: Record<string, unknown>, indent: number = 0): string {
    const lines: string[] = [];
    const indentStr = ' '.repeat(indent);

    for (const [key, value] of Object.entries(obj)) {
      if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
        lines.push(`${indentStr}${key}: ${value}`);
      } else if (typeof value === 'object' && value !== null) {
        lines.push(`${indentStr}${key}:`);
        if (Array.isArray(value)) {
          value.forEach((item) => {
            lines.push(`${indentStr}  - ${item}`);
          });
        } else {
          lines.push(this.objectToYaml(value as Record<string, unknown>, indent + 2));
        }
      }
    }

    return lines.join('\n');
  }

  /**
   * Helper: indent multi-line string
   */
  private indentString(str: string, spaces: number): string {
    const indent = ' '.repeat(spaces);
    return str
      .split('\n')
      .map((line) => (line.trim() ? indent + line : ''))
      .join('\n');
  }

  /**
   * Build the final configuration object
   */
  build(): FluxDeploymentConfig {
    if (!this.config.gitRepository) {
      throw new Error('Git repository configuration is required');
    }

    return {
      gitRepository: this.config.gitRepository,
      helmRepositories: this.config.helmRepositories || [],
      imagePolicies: this.config.imagePolicies || [],
      kustomizations: this.config.kustomizations || [],
      imageUpdateAutomation: this.config.imageUpdateAutomation,
    };
  }
}
