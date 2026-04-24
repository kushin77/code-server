const qaResourcePrefix = process.env.QA_RESOURCE_PREFIX || 'qa-test-';

export const createTestWorkspaceName = (): string => `${qaResourcePrefix}${Date.now()}-workspace`;

export const createTestFileName = (): string => `${qaResourcePrefix}${Date.now()}-file.txt`;

export const isQaResourceName = (name: string): boolean => name.startsWith(qaResourcePrefix);

export const getQaResourcePrefix = (): string => qaResourcePrefix;
