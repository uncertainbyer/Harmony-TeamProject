/**
 * 时间格式化类型
 */
export enum TimeFormatType {
  /** 完整格式：2024-01-15 14:30:00 */
  FULL = 'full',
  /** 日期格式：2024-01-15 */
  DATE = 'date',
  /** 时间格式：14:30:00 */
  TIME = 'time',
  /** 简短日期：01-15 */
  SHORT_DATE = 'short_date',
  /** 简短时间：14:30 */
  SHORT_TIME = 'short_time',
  /** 中文日期：2024年1月15日 */
  CN_DATE = 'cn_date',
  /** 中文时间：14时30分 */
  CN_TIME = 'cn_time'
}

/**
 * 时间工具类
 * 提供时间格式化和计算功能
 */
export class TimeUtil {
  /**
   * 格式化时间戳
   * @param timestamp 时间戳（毫秒）
   * @param formatType 格式类型
   * @returns 格式化后的字符串
   */
  static format(timestamp: number, formatType: TimeFormatType = TimeFormatType.FULL): string {
    const date: Date = new Date(timestamp);

    const year: number = date.getFullYear();
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    const hour: number = date.getHours();
    const minute: number = date.getMinutes();
    const second: number = date.getSeconds();

    const monthStr: string = TimeUtil.padZero(month);
    const dayStr: string = TimeUtil.padZero(day);
    const hourStr: string = TimeUtil.padZero(hour);
    const minuteStr: string = TimeUtil.padZero(minute);
    const secondStr: string = TimeUtil.padZero(second);

    switch (formatType) {
      case TimeFormatType.FULL:
        return `${year}-${monthStr}-${dayStr} ${hourStr}:${minuteStr}:${secondStr}`;
      case TimeFormatType.DATE:
        return `${year}-${monthStr}-${dayStr}`;
      case TimeFormatType.TIME:
        return `${hourStr}:${minuteStr}:${secondStr}`;
      case TimeFormatType.SHORT_DATE:
        return `${monthStr}-${dayStr}`;
      case TimeFormatType.SHORT_TIME:
        return `${hourStr}:${minuteStr}`;
      case TimeFormatType.CN_DATE:
        return `${year}年${month}月${day}日`;
      case TimeFormatType.CN_TIME:
        return `${hour}时${minute}分`;
      default:
        return `${year}-${monthStr}-${dayStr} ${hourStr}:${minuteStr}:${secondStr}`;
    }
  }

  /**
   * 格式化为友好时间显示（如：刚刚、5分钟前、今天 14:30）
   * @param timestamp 时间戳（毫秒）
   * @returns 友好时间字符串
   */
  static formatFriendly(timestamp: number): string {
    const now: number = Date.now();
    const diff: number = now - timestamp;

    // 1分钟内
    if (diff < 60 * 1000) {
      return '刚刚';
    }

    // 1小时内
    if (diff < 60 * 60 * 1000) {
      const minutes: number = Math.floor(diff / (60 * 1000));
      return minutes + '分钟前';
    }

    // 今天内
    const todayStart: number = TimeUtil.getTodayStart();
    if (timestamp >= todayStart) {
      const timeStr: string = TimeUtil.format(timestamp, TimeFormatType.SHORT_TIME);
      return '今天 ' + timeStr;
    }

    // 昨天内
    const yesterdayStart: number = todayStart - 24 * 60 * 60 * 1000;
    if (timestamp >= yesterdayStart) {
      const timeStr: string = TimeUtil.format(timestamp, TimeFormatType.SHORT_TIME);
      return '昨天 ' + timeStr;
    }

    // 一周内
    const weekAgo: number = now - 7 * 24 * 60 * 60 * 1000;
    if (timestamp >= weekAgo) {
      const days: number = Math.floor(diff / (24 * 60 * 60 * 1000));
      return days + '天前';
    }

    // 超过一周，显示日期
    return TimeUtil.format(timestamp, TimeFormatType.DATE);
  }

  /**
   * 获取今天开始时间戳（00:00:00）
   * @returns 时间戳
   */
  static getTodayStart(): number {
    const now: Date = new Date();
    const year: number = now.getFullYear();
    const month: number = now.getMonth();
    const day: number = now.getDate();
    const today: Date = new Date(year, month, day, 0, 0, 0);
    return today.getTime();
  }

  /**
   * 获取今天结束时间戳（23:59:59）
   * @returns 时间戳
   */
  static getTodayEnd(): number {
    const now: Date = new Date();
    const year: number = now.getFullYear();
    const month: number = now.getMonth();
    const day: number = now.getDate();
    const today: Date = new Date(year, month, day, 23, 59, 59, 999);
    return today.getTime();
  }

  /**
   * 计算两个时间戳之间的天数差
   * @param timestamp1 时间戳1
   * @param timestamp2 时间戳2
   * @returns 天数差（绝对值）
   */
  static getDaysDiff(timestamp1: number, timestamp2: number): number {
    const diff: number = Math.abs(timestamp1 - timestamp2);
    return Math.floor(diff / (24 * 60 * 60 * 1000));
  }

  /**
   * 计算两个时间戳之间的小时差
   * @param timestamp1 时间戳1
   * @param timestamp2 时间戳2
   * @returns 小时差（绝对值）
   */
  static getHoursDiff(timestamp1: number, timestamp2: number): number {
    const diff: number = Math.abs(timestamp1 - timestamp2);
    return Math.floor(diff / (60 * 60 * 1000));
  }

  /**
   * 计算两个时间戳之间的分钟差
   * @param timestamp1 时间戳1
   * @param timestamp2 时间戳2
   * @returns 分钟差（绝对值）
   */
  static getMinutesDiff(timestamp1: number, timestamp2: number): number {
    const diff: number = Math.abs(timestamp1 - timestamp2);
    return Math.floor(diff / (60 * 1000));
  }

  /**
   * 判断是否为今天
   * @param timestamp 时间戳
   * @returns 是否为今天
   */
  static isToday(timestamp: number): boolean {
    const todayStart: number = TimeUtil.getTodayStart();
    const todayEnd: number = TimeUtil.getTodayEnd();
    return timestamp >= todayStart && timestamp <= todayEnd;
  }

  /**
   * 判断是否为昨天
   * @param timestamp 时间戳
   * @returns 是否为昨天
   */
  static isYesterday(timestamp: number): boolean {
    const todayStart: number = TimeUtil.getTodayStart();
    const yesterdayStart: number = todayStart - 24 * 60 * 60 * 1000;
    return timestamp >= yesterdayStart && timestamp < todayStart;
  }

  /**
   * 数字补零
   * @param num 数字
   * @returns 补零后的字符串
   */
  private static padZero(num: number): string {
    return num < 10 ? '0' + num : num.toString();
  }
}

export default TimeUtil;