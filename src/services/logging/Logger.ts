export class Logger {
  constructor(private readonly scope: string) {}

  debug(message: string, ...args: any[]): void {
    this.write('debug', message, args);
  }

  info(message: string, ...args: any[]): void {
    this.write('info', message, args);
  }

  warn(message: string, ...args: any[]): void {
    this.write('warn', message, args);
  }

  error(message: string, ...args: any[]): void {
    this.write('error', message, args);
  }

  private write(level: string, message: string, args: any[]): void {
    if (args.length > 0) {
      console.log(`[${this.scope}] ${level}: ${message}`, ...args);
      return;
    }

    console.log(`[${this.scope}] ${level}: ${message}`);
  }
}

export default Logger;