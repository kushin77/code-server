/**
 * VS Code Mock for Node/Jest Testing
 */

export enum StatusBarAlignment {
  Left = 1,
  Right = 2,
}

export class Uri {
  static file(path: string) {
    return { fsPath: path };
  }
}

export const window = {
  createOutputChannel: jest.fn(() => ({
    appendLine: jest.fn(),
  })),
  createStatusBarItem: jest.fn(() => ({
    command: '',
    tooltip: '',
    text: '',
    show: jest.fn(),
  })),
};

export const commands = {
  registerCommand: jest.fn(),
};

export default {
  Uri,
  window,
  commands,
  StatusBarAlignment,
};
