// @file        apps/backend/src/services/onboarding/fallback-handler.ts
// @module      services/onboarding
// @description Fallback handlers for failed onboarding steps
//              Provides manual instructions and alternative solutions
//
import { logger } from '../../lib/logger';
/**
 * Fallback handler for onboarding steps
 */
export class OnboardingFallbackHandler {
    /**
     * Get fallback instructions for git-config
     */
    static getGitConfigFallback(error) {
        return {
            stepId: 'git-config',
            stepTitle: 'Configure Git',
            reason: error || 'Git configuration failed',
            manualSteps: [
                'Open Terminal/PowerShell',
                'Run: git config --global user.name "Your Name"',
                'Run: git config --global user.email "your.email@company.com"',
                'Verify: git config --global --list',
            ],
            alternativeApproaches: [
                'Configure per-repository (remove --global flag)',
                'Use Git GUI tools (GitHub Desktop, GitKraken)',
                'Configure via IDE settings if available',
            ],
            helpResources: [
                'https://git-scm.com/book/en/v2/Getting-Started-First-Time-Git-Setup',
                'https://docs.github.com/en/get-started/getting-started-with-git',
            ],
            contactSupport: 'Contact your team IT support if git is not installed',
        };
    }
    /**
     * Get fallback instructions for SSH setup
     */
    static getSSHSetupFallback(error) {
        return {
            stepId: 'ssh-setup',
            stepTitle: 'Setup SSH Keys',
            reason: error || 'SSH key generation failed',
            manualSteps: [
                'Open Terminal/PowerShell',
                'Run: ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa',
                'Press Enter to accept default location',
                'Enter a passphrase (or leave blank)',
                'Copy public key: cat ~/.ssh/id_rsa.pub',
                'Add to GitHub/GitLab SSH settings',
                'Test: ssh -T git@github.com',
            ],
            alternativeApproaches: [
                'Use HTTPS instead of SSH (requires personal access token)',
                'Use SSH agent for key management',
                'Generate keys via IDE/Git GUI tools',
            ],
            helpResources: [
                'https://docs.github.com/en/authentication/connecting-to-github-with-ssh',
                'https://docs.gitlab.com/ee/user/ssh.html',
                'https://www.ssh.com/ssh/keygen/',
            ],
            contactSupport: 'Contact your IT team if you need SSH access',
        };
    }
    /**
     * Get fallback instructions for cloud login
     */
    static getCloudLoginFallback(error) {
        return {
            stepId: 'cloud-login',
            stepTitle: 'Cloud Login',
            reason: error || 'Cloud authentication required',
            manualSteps: [
                'Open GitHub/Azure/Google login page',
                'Click "Sign In"',
                'Enter your credentials',
                'Authorize the IDE extension',
                'Copy the provided code',
                'Paste the code in the terminal prompt',
                'Verify: check your account name in the IDE',
            ],
            alternativeApproaches: [
                'Use personal access token instead of OAuth',
                'Configure via config file',
                'Use HTTPS with stored credentials',
            ],
            helpResources: [
                'https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token',
                'https://learn.microsoft.com/en-us/azure/developer/javascript/configure-local-development-environment',
            ],
            contactSupport: 'Contact your cloud admin for account issues',
        };
    }
    /**
     * Get fallback instructions for repo clone
     */
    static getRepoCloneFallback(error) {
        return {
            stepId: 'repo-clone',
            stepTitle: 'Clone Repository',
            reason: error || 'Repository clone failed',
            manualSteps: [
                'Open Terminal/PowerShell',
                'Navigate to desired workspace location',
                'Run: git clone <repository-url>',
                'Enter authentication if prompted',
                'Wait for clone to complete',
                'Verify: cd <repo-name> && ls -la',
            ],
            alternativeApproaches: [
                'Use git clone with HTTPS instead of SSH',
                'Download repository as ZIP file',
                'Use GitHub Desktop or GitKraken to clone',
                'Use git clone with --depth 1 for shallow clone',
            ],
            helpResources: [
                'https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository',
                'https://git-scm.com/book/en/v2/Git-Basics-Getting-a-Git-Repository',
            ],
            contactSupport: 'Verify repository access permissions with your team lead',
        };
    }
    /**
     * Get fallback instructions for build config
     */
    static getBuildConfigFallback(error) {
        return {
            stepId: 'build-config',
            stepTitle: 'Configure Build',
            reason: error || 'Build configuration failed',
            manualSteps: [
                'Open Terminal/PowerShell in repository',
                'Check Node.js version: node --version',
                'Check npm version: npm --version',
                'Clear npm cache: npm cache clean --force',
                'Delete node_modules: rm -rf node_modules',
                'Delete lockfile: rm package-lock.json',
                'Run: npm install',
                'Run: npm ci (if package-lock.json exists)',
            ],
            alternativeApproaches: [
                'Use yarn instead: yarn install',
                'Use pnpm instead: pnpm install',
                'Use Volta for Node.js version management',
                'Use Docker for containerized setup',
            ],
            helpResources: [
                'https://docs.npmjs.com/cli/v8/commands/npm-install',
                'https://nodejs.org/en/download/',
                'https://github.com/volta-cli/volta',
            ],
            contactSupport: 'Check team documentation for specific build requirements',
        };
    }
    /**
     * Get fallback instructions for verify
     */
    static getVerifyFallback(error) {
        return {
            stepId: 'verify',
            stepTitle: 'Verify Setup',
            reason: error || 'Setup verification failed',
            manualSteps: [
                'Run: npm run build (or your build command)',
                'Check for build errors',
                'Run: npm test (or your test command)',
                'Check test output for failures',
                'Fix any identified issues',
                'Re-run build and tests',
                'Consult team wiki for troubleshooting',
            ],
            alternativeApproaches: [
                'Run tests in watch mode: npm run test -- --watch',
                'Run specific test file: npm test -- <file-name>',
                'Check coverage: npm run test -- --coverage',
                'Use IDE debugger to step through tests',
            ],
            helpResources: [
                'https://jestjs.io/docs/getting-started',
                'https://nodejs.org/en/docs/',
            ],
            contactSupport: 'Post errors to team Slack or create an issue on GitHub',
        };
    }
    /**
     * Get fallback instruction for any step
     */
    static getFallback(stepId, error) {
        switch (stepId) {
            case 'git-config':
                return this.getGitConfigFallback(error);
            case 'ssh-setup':
                return this.getSSHSetupFallback(error);
            case 'cloud-login':
                return this.getCloudLoginFallback(error);
            case 'repo-clone':
                return this.getRepoCloneFallback(error);
            case 'build-config':
                return this.getBuildConfigFallback(error);
            case 'verify':
                return this.getVerifyFallback(error);
            default:
                return {
                    stepId,
                    stepTitle: 'Step',
                    reason: error || 'Step failed',
                    manualSteps: ['Review step description', 'Check documentation', 'Ask for help'],
                    alternativeApproaches: ['Skip this step and continue', 'Contact support'],
                    helpResources: [],
                    contactSupport: 'Contact your team IT support for assistance',
                };
        }
    }
    /**
     * Log fallback instructions
     */
    static logFallback(instruction) {
        logger.warn('Step requires fallback instructions', {
            stepId: instruction.stepId,
            stepTitle: instruction.stepTitle,
            reason: instruction.reason,
        });
        logger.info('Manual steps:', instruction.manualSteps);
        logger.info('Alternative approaches:', instruction.alternativeApproaches);
        logger.info('Help resources:', instruction.helpResources);
    }
    /**
     * Format fallback as markdown
     */
    static formatMarkdown(instruction) {
        const lines = [
            `# ${instruction.stepTitle} - Fallback Instructions`,
            '',
            `**Reason:** ${instruction.reason}`,
            '',
            '## Manual Steps',
            ...instruction.manualSteps.map((step, i) => `${i + 1}. ${step}`),
            '',
            '## Alternative Approaches',
            ...instruction.alternativeApproaches.map((approach, i) => `${i + 1}. ${approach}`),
            '',
            '## Help Resources',
            ...instruction.helpResources.map((resource) => `- [${resource}](${resource})`),
            '',
            `## Support`,
            instruction.contactSupport,
        ];
        return lines.join('\n');
    }
    /**
     * Format fallback as HTML
     */
    static formatHTML(instruction) {
        return `
<div class="fallback-instructions">
  <h2>${instruction.stepTitle} - Fallback Instructions</h2>
  
  <div class="reason">
    <p><strong>Reason:</strong> ${instruction.reason}</p>
  </div>
  
  <div class="manual-steps">
    <h3>Manual Steps</h3>
    <ol>
      ${instruction.manualSteps.map((step) => `<li>${step}</li>`).join('\n')}
    </ol>
  </div>
  
  <div class="alternatives">
    <h3>Alternative Approaches</h3>
    <ol>
      ${instruction.alternativeApproaches.map((approach) => `<li>${approach}</li>`).join('\n')}
    </ol>
  </div>
  
  <div class="resources">
    <h3>Help Resources</h3>
    <ul>
      ${instruction.helpResources.map((resource) => `<li><a href="${resource}">${resource}</a></li>`).join('\n')}
    </ul>
  </div>
  
  <div class="support">
    <p><strong>Support:</strong> ${instruction.contactSupport}</p>
  </div>
</div>
    `;
    }
}
//# sourceMappingURL=fallback-handler.js.map