/**
 * 日志级别枚举
 */
export enum LogLevel {
  /** 调试级别 */
  DEBUG = 0,
  /** 信息级别 */
  INFO = 1,
  /** 警告级别 */
  WARN = 2,
  /** 错误级别 */
  ERROR = 3,
  /** 关闭日志 */
  OFF = 4
}

/**
 * 日志配置
 */
export class LogConfig {
  /** 日志标签 */
  static APP_TAG: string = 'SocialPhoto';
  /** 当前日志级别 */
  static LEVEL: LogLevel = LogLevel.DEBUG;
  /** 是否输出到控制台 */
  static ENABLE_CONSOLE: boolean = true;
}

/**
 * 日志工具类
 * 提供统一的日志输出功能
 */
export class Logger {
  private tag: string;

  /**
   * 构造函数
   * @param tag 日志标签
   */
  constructor(tag: string) {
    this.tag = tag;
  }

  /**
   * 创建Logger实例
   * @param tag 日志标签
   * @returns Logger实例
   */
  static create(tag: string): Logger {
    return new Logger(tag);
  }

  /**
   * 输出调试日志
   * @param message 消息
   * @param args 参数
   */
  debug(message: string, ...args: string[]): void {
    if (LogConfig.LEVEL <= LogLevel.DEBUG && LogConfig.ENABLE_CONSOLE) {
      const logMessage: string = this.formatMessage('DEBUG', message);
      console.debug(logMessage, args);
    }
  }

  /**
   * 输出信息日志
   * @param message 消息
   * @param args 参数
   */
  info(message: string, ...args: string[]): void {
    if (LogConfig.LEVEL <= LogLevel.INFO && LogConfig.ENABLE_CONSOLE) {
      const logMessage: string = this.formatMessage('INFO', message);
      console.info(logMessage, args);
    }
  }

  /**
   * 输出警告日志
   * @param message 消息
   * @param args 参数
   */
  warn(message: string, ...args: string[]): void {
    if (LogConfig.LEVEL <= LogLevel.WARN && LogConfig.ENABLE_CONSOLE) {
      const logMessage: string = this.formatMessage('WARN', message);
      console.warn(logMessage, args);
    }
  }

  /**
   * 输出错误日志
   * @param message 消息
   * @param args 参数
   */
  error(message: string, ...args: string[]): void {
    if (LogConfig.LEVEL <= LogLevel.ERROR && LogConfig.ENABLE_CONSOLE) {
      const logMessage: string = this.formatMessage('ERROR', message);
      console.error(logMessage, args);
    }
  }

  /**
   * 格式化日志消息
   * @param level 日志级别
   * @param message 消息
   * @returns 格式化后的消息
   */
  private formatMessage(level: string, message: string): string {
    const timestamp: string = this.getCurrentTime();
    return `[${timestamp}] [${LogConfig.APP_TAG}] [${this.tag}] [${level}] ${message}`;
  }

  /**
   * 获取当前时间字符串
   * @returns 时间字符串
   */
  private getCurrentTime(): string {
    const now: Date = new Date();
    const year: number = now.getFullYear();
    const month: string = this.padZero(now.getMonth() + 1);
    const day: string = this.padZero(now.getDate());
    const hour: string = this.padZero(now.getHours());
    const minute: string = this.padZero(now.getMinutes());
    const second: string = this.padZero(now.getSeconds());

    return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
  }

  /**
   * 数字补零
   * @param num 数字
   * @returns 补零后的字符串
   */
  private padZero(num: number): string {
    return num < 10 ? '0' + num : num.toString();
  }
}

/**
 * 默认日志实例
 */
export const logger: Logger = Logger.create('App');

export default Logger;