export declare class Agent {
    private name;
    constructor(name: string);
    execute(task: string): Promise<string>;
}
export declare class Orchestrator {
    private agents;
    constructor();
    executeTask(task: string): Promise<string>;
}
//# sourceMappingURL=extension.d.ts.map