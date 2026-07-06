/**
 * UUID生成工具类
 * 用于生成唯一标识符
 */
export class UUIDUtil {
  /**
   * 生成标准UUID（格式：xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx）
   * @returns UUID字符串
   */
  static generate(): string {
    const chars: string = '0123456789abcdef';
    let uuid: string = '';

    for (let i: number = 0; i < 36; i++) {
      if (i === 8 || i === 13 || i === 18 || i === 23) {
        uuid += '-';
      } else if (i === 14) {
        uuid += '4';
      } else if (i === 19) {
        uuid += chars.charAt(8 + Math.floor(Math.random() * 4));
      } else {
        const randomIndex: number = Math.floor(Math.random() * 16);
        uuid += chars.charAt(randomIndex);
      }
    }

    return uuid;
  }

  /**
   * 生成短UUID（无连字符，32位）
   * @returns 短UUID字符串
   */
  static generateShort(): string {
    const chars: string = '0123456789abcdef';
    let uuid: string = '';

    for (let i: number = 0; i < 32; i++) {
      const randomIndex: number = Math.floor(Math.random() * 16);
      uuid += chars.charAt(randomIndex);
    }

    return uuid;
  }

  /**
   * 生成数字型UUID（纯数字）
   * @param length 长度，默认16位
   * @returns 数字型UUID字符串
   */
  static generateNumeric(length: number = 16): string {
    const chars: string = '0123456789';
    let uuid: string = '';

    for (let i: number = 0; i < length; i++) {
      const randomIndex: number = Math.floor(Math.random() * 10);
      uuid += chars.charAt(randomIndex);
    }

    return uuid;
  }

  /**
   * 生成基于时间戳的UUID
   * @returns 时间戳UUID字符串
   */
  static generateTimestamp(): string {
    const timestamp: number = Date.now();
    const random: string = UUIDUtil.generateShort().substring(0, 8);
    return timestamp.toString() + '_' + random;
  }

  /**
   * 验证是否为有效的UUID格式
   * @param uuid UUID字符串
   * @returns 是否有效
   */
  static isValid(uuid: string): boolean {
    const pattern: RegExp = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
    return pattern.test(uuid);
  }

  /**
   * 验证是否为有效的短UUID格式
   * @param uuid UUID字符串
   * @returns 是否有效
   */
  static isValidShort(uuid: string): boolean {
    const pattern: RegExp = /^[0-9a-f]{32}$/;
    return pattern.test(uuid);
  }
}

export default UUIDUtil;