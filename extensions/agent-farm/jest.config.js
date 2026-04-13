module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testMatch: ['**/*.test.ts', '**/*.test.js'],
  moduleFileExtensions: ['ts', 'js'],
  globals: {
    'ts-jest': {
      tsconfig: {
        esModuleInterop: true,
        allowSyntheticDefaultImports: true,
        skipLibCheck: true,
        forceConsistentCasingInFileNames: false,
      },
      isolatedModules: true,
    },
  },
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.test.ts',
  ],
  coveragePathIgnorePatterns: [
    '/node_modules/',
    '/dist/',
    '/out/',
  ],
  moduleNameMapper: {
    '^vscode$': '<rootDir>/src/__mocks__/vscode.ts',
  },
  testPathIgnorePatterns: [
    '/node_modules/',
    '/dist/',
  ],
};
