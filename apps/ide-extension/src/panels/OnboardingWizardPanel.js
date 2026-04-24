// @file        apps/ide-extension/src/panels/OnboardingWizardPanel.tsx
// @module      ui/panels/onboarding
// @description React component for workspace onboarding wizard
//              Displays 10-minute setup flow with auto-run and manual fallback
//
import React, { useState, useEffect } from 'react';
import './OnboardingWizardPanel.css';
/**
 * Onboarding Wizard Panel component
 */
export const OnboardingWizardPanel = ({ sessionId, userId, workspaceId, teamId, onComplete, }) => {
    const [steps, setSteps] = useState([]);
    const [currentStepIndex, setCurrentStepIndex] = useState(0);
    const [completionPercentage, setCompletionPercentage] = useState(0);
    const [isRunning, setIsRunning] = useState(false);
    const [totalDurationMs, setTotalDurationMs] = useState(0);
    useEffect(() => {
        initializeWizard();
    }, [sessionId]);
    useEffect(() => {
        // Track elapsed time
        if (isRunning) {
            const interval = setInterval(() => {
                setTotalDurationMs((prev) => prev + 100);
            }, 100);
            return () => clearInterval(interval);
        }
    }, [isRunning]);
    const initializeWizard = async () => {
        // Initialize with default steps
        const defaultSteps = [
            {
                id: 'git-config',
                title: 'Configure Git',
                description: 'Set your Git name and email for commits',
                order: 1,
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: true,
                estimatedDurationMs: 30000,
            },
            {
                id: 'ssh-setup',
                title: 'Setup SSH Keys',
                description: 'Generate SSH key pair for GitHub/GitLab access',
                order: 2,
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: true,
                estimatedDurationMs: 45000,
            },
            {
                id: 'cloud-login',
                title: 'Cloud Login',
                description: 'Authenticate with cloud provider (GitHub/Azure/Google)',
                order: 3,
                status: 'pending',
                completed: false,
                autoRunnable: false,
                manualFallback: true,
                estimatedDurationMs: 60000,
            },
            {
                id: 'repo-clone',
                title: 'Clone Repository',
                description: 'Clone team repository to workspace',
                order: 4,
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: true,
                estimatedDurationMs: 120000,
            },
            {
                id: 'build-config',
                title: 'Configure Build',
                description: 'Install dependencies and configure build tools',
                order: 5,
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: true,
                estimatedDurationMs: 300000,
            },
            {
                id: 'verify',
                title: 'Verify Setup',
                description: 'Run build and tests to verify everything works',
                order: 6,
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: true,
                estimatedDurationMs: 180000,
            },
            {
                id: 'complete',
                title: 'Complete',
                description: 'Onboarding complete, ready to start coding',
                order: 7,
                status: 'pending',
                completed: false,
                autoRunnable: true,
                manualFallback: false,
                estimatedDurationMs: 5000,
            },
        ];
        setSteps(defaultSteps);
        setIsRunning(true);
    };
    const handleAutoRunAll = async () => {
        const newSteps = [...steps];
        for (let i = 0; i < newSteps.length; i++) {
            const step = newSteps[i];
            if (step.autoRunnable && !step.completed) {
                step.status = 'in-progress';
                setSteps([...newSteps]);
                setCurrentStepIndex(i);
                // Simulate step execution
                await new Promise((resolve) => setTimeout(resolve, step.estimatedDurationMs));
                step.status = 'completed';
                step.completed = true;
                step.result = { success: true };
            }
            setSteps([...newSteps]);
            updateProgress(newSteps);
        }
        setIsRunning(false);
        if (onComplete) {
            onComplete();
        }
    };
    const handleSkipStep = () => {
        const newSteps = [...steps];
        newSteps[currentStepIndex].status = 'skipped';
        setSteps(newSteps);
        handleNextStep();
    };
    const handleNextStep = () => {
        if (currentStepIndex < steps.length - 1) {
            setCurrentStepIndex(currentStepIndex + 1);
        }
        else {
            setIsRunning(false);
            if (onComplete) {
                onComplete();
            }
        }
    };
    const handlePreviousStep = () => {
        if (currentStepIndex > 0) {
            setCurrentStepIndex(currentStepIndex - 1);
        }
    };
    const updateProgress = (newSteps) => {
        const completed = newSteps.filter((s) => s.completed).length;
        setCompletionPercentage((completed / newSteps.length) * 100);
    };
    const currentStep = steps[currentStepIndex];
    const formatDuration = (ms) => {
        const seconds = Math.floor((ms % 60000) / 1000);
        const minutes = Math.floor(ms / 60000);
        return `${minutes}:${String(seconds).padStart(2, '0')}`;
    };
    return (<div className="onboarding-wizard-panel">
      <div className="wizard-header">
        <h1>Welcome to Your Team</h1>
        <p>Let's set up your workspace in 10 minutes</p>

        <div className="progress-section">
          <div className="progress-bar">
            <div className="progress-fill" style={{ width: `${completionPercentage}%` }}/>
          </div>
          <div className="progress-stats">
            <span>{Math.round(completionPercentage)}% Complete</span>
            <span>{formatDuration(totalDurationMs)} Elapsed</span>
          </div>
        </div>
      </div>

      <div className="wizard-content">
        <div className="steps-sidebar">
          <div className="steps-list">
            {steps.map((step, index) => (<div key={step.id} className={`step-item ${step.status} ${index === currentStepIndex ? 'active' : ''}`} onClick={() => setCurrentStepIndex(index)}>
                <div className="step-number">
                  {step.completed ? <span className="checkmark">✓</span> : <span>{step.order}</span>}
                </div>
                <div className="step-info">
                  <div className="step-title">{step.title}</div>
                  <div className="step-status">{step.status}</div>
                </div>
              </div>))}
          </div>
        </div>

        <div className="step-content">
          {currentStep && (<>
              <div className="step-header">
                <h2>{currentStep.title}</h2>
                <p>{currentStep.description}</p>
              </div>

              <div className="step-details">
                {currentStep.status === 'pending' && (<div className="step-pending">
                    <p>Ready to start this step</p>
                    {currentStep.autoRunnable && (<button className="btn-primary" onClick={handleAutoRunAll}>
                        Start All Steps
                      </button>)}
                  </div>)}

                {currentStep.status === 'in-progress' && (<div className="step-running">
                    <div className="spinner"/>
                    <p>Setting up {currentStep.title.toLowerCase()}...</p>
                    <p className="estimate">
                      Est. {formatDuration(currentStep.estimatedDurationMs)} remaining
                    </p>
                  </div>)}

                {currentStep.status === 'completed' && (<div className="step-success">
                    <div className="checkmark-large">✓</div>
                    <p>{currentStep.title} completed successfully</p>
                    {currentStep.result && (<pre className="result-details">{JSON.stringify(currentStep.result, null, 2)}</pre>)}
                  </div>)}

                {currentStep.status === 'failed' && (<div className="step-error">
                    <div className="error-icon">⚠</div>
                    <p>Failed to complete {currentStep.title}</p>
                    {currentStep.error && (<pre className="error-details">{currentStep.error}</pre>)}
                    {currentStep.manualFallback && (<p className="fallback-info">Please complete this step manually</p>)}
                  </div>)}

                {currentStep.status === 'skipped' && (<div className="step-skipped">
                    <p>{currentStep.title} was skipped</p>
                  </div>)}
              </div>

              <div className="step-actions">
                <button className="btn-secondary" onClick={handlePreviousStep} disabled={currentStepIndex === 0}>
                  ← Previous
                </button>

                {currentStep.status === 'pending' && (<>
                    {currentStep.autoRunnable && (<button className="btn-primary" onClick={() => handleNextStep()}>
                        Run Step
                      </button>)}
                    {currentStep.manualFallback && (<button className="btn-secondary" onClick={handleSkipStep}>
                        Skip
                      </button>)}
                  </>)}

                {currentStep.status !== 'pending' && (<button className="btn-primary" onClick={handleNextStep} disabled={currentStepIndex === steps.length - 1 && !currentStep.completed}>
                    {currentStepIndex === steps.length - 1 ? 'Finish' : 'Next →'}
                  </button>)}
              </div>
            </>)}
        </div>
      </div>
    </div>);
};
export default OnboardingWizardPanel;
//# sourceMappingURL=OnboardingWizardPanel.js.map