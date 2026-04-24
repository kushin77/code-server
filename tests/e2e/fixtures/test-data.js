const qaResourcePrefix = process.env.QA_RESOURCE_PREFIX || 'qa-test-';
export const createTestWorkspaceName = () => `${qaResourcePrefix}${Date.now()}-workspace`;
export const createTestFileName = () => `${qaResourcePrefix}${Date.now()}-file.txt`;
export const isQaResourceName = (name) => name.startsWith(qaResourcePrefix);
export const getQaResourcePrefix = () => qaResourcePrefix;
//# sourceMappingURL=test-data.js.map