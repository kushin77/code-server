export class Logger {
    constructor(scope) {
        this.scope = scope;
    }
    debug(message, ...args) {
        this.write('debug', message, args);
    }
    info(message, ...args) {
        this.write('info', message, args);
    }
    warn(message, ...args) {
        this.write('warn', message, args);
    }
    error(message, ...args) {
        this.write('error', message, args);
    }
    write(level, message, args) {
        if (args.length > 0) {
            console.log(`[${this.scope}] ${level}: ${message}`, ...args);
            return;
        }
        console.log(`[${this.scope}] ${level}: ${message}`);
    }
}
export default Logger;
//# sourceMappingURL=Logger.js.map