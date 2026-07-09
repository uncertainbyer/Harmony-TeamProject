import {
  DistributedService,
  SyncConnectionState,
  DistributedSyncState,
  SyncResult
} from '../service/DistributedService';
import { common } from '@kit.AbilityKit';

// ⭐ 服务错误接口，替代 any
interface ServiceError {
  message: string;
  name?: string;
  code?: string;
}

@Entry
@Component
struct CloudSyncTest {
  // ---- 表单状态 ----
  @State username: string = '';
  @State password: string = '';
  // ---- 服务状态 ----
  @State serviceStatus: string = '未初始化';
  @State connectionStateText: string = '空闲';
  @State lastMessage: string = '';
  @State isLoggedIn: boolean = false;
  @State userId: string = '';
  // ---- 操作结果 ----
  @State syncResultText: string = '';
  @State uploadResultText: string = '';
  @State logLines: string[] = [];
  // ---- 控制 ----
  @State isSyncing: boolean = false;
  // ---- 错误提示相关状态 ----
  @State loginError: string = '';
  @State loginErrorType: string = '';
  @State loginErrorCode: string = '';
  @State showErrorBanner: boolean = false;
  // 错误类型枚举
  private readonly ERROR_TYPES: Record<string, string> = {
    "NETWORK": '🌐 网络错误',
    "AUTH": '🔐 认证错误',
    "CERT": '📜 证书/签名错误',
    "PARAM": '⚙️ 参数配置错误',
    "TIMEOUT": '⏱️ 超时错误',
    "SERVER": '🖥️ 服务器错误',
    "UNKNOWN": '❓ 未知错误'
  };
  private service: DistributedService = DistributedService.getInstance();

  aboutToAppear(): void {
    this.addLog('页面加载，检查服务状态...');

    if (this.service.isReady()) {
      // 服务已就绪，正常执行
      this.serviceStatus = '已就绪';
      this.setupService();
    } else {
      // ⭐ 服务未就绪，检查是否有初始化错误信息
      const initError: string | undefined = AppStorage.get<string>('init_error');
      if (initError !== undefined && initError.length > 0) {
        this.serviceStatus = '初始化失败: ' + initError;
        this.addLog('❌ 初始化失败: ' + initError);
      } else {
        // ⭐ 后备方案：直接在页面中再次尝试初始化
        this.addLog('服务未就绪，尝试在页面中初始化...');
        this.retryInit();
      }
    }
  }



  // ⭐ 新增：在页面中重试初始化
  private async retryInit(): Promise<void> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      await this.service.init(context);
      this.serviceStatus = '已就绪';
      this.addLog('✅ 页面中初始化成功');
      this.setupService();
    } catch (err) {
      const error: Error = err as Error;
      this.serviceStatus = '初始化失败: ' + error.message;
      this.addLog('❌ 页面中初始化失败: ' + error.message);
    }
  }

  // ⭐ 新增：提取公共的服务设置逻辑
  private setupService(): void {
    this.service.onStateChanged((state: DistributedSyncState): void => {
      this.updateStatus(state);
    });

    let token: string | undefined = AppStorage.get<string>('cloud_sync_token');
    if (token !== undefined && token.length > 0) {
      this.isLoggedIn = true;
      this.userId = AppStorage.get<string>('cloud_user_id') ?? '';
      this.addLog('已恢复登录状态，用户ID: ' + this.userId);
    } else {
      this.addLog('未登录，请先登录');
    }
  }

  private updateStatus(state: DistributedSyncState): void {
    this.connectionStateText = this.stateToText(state.state);
    this.lastMessage = state.lastMessage;
    this.addLog('[状态] ' + this.connectionStateText + ' - ' + state.lastMessage);
  }

  private stateToText(state: SyncConnectionState): string {
    switch (state) {
      case SyncConnectionState.IDLE:
        return '空闲';
      case SyncConnectionState.CONNECTING:
        return '连接中';
      case SyncConnectionState.CONNECTED:
        return '已连接';
      case SyncConnectionState.SYNCING:
        return '同步中';
      case SyncConnectionState.ERROR:
        return '错误';
      default:
        return '未知';
    }
  }

  // ---- 智能错误分析（接收字符串参数，替代 any） ----
  private analyzeLoginError(message: string, code?: string): void {
    const errMsg: string = message || '';
    const errCode: string = code || '';

    this.loginError = errMsg;
    this.loginErrorCode = errCode;

    // 根据错误信息分类
    if (errCode === '1001500001' || errMsg.includes('fingerprint') || errMsg.includes('指纹')) {
      this.loginErrorType = this.ERROR_TYPES.CERT;
      this.loginError = '证书指纹验证失败（错误码: 1001500001）\n'
        + '🔍 请检查：\n'
        + '  1. AGC后台是否配置了正确的SHA256证书指纹\n'
        + '  2. 调试证书与发布证书的指纹是否分开配置\n'
        + '  3. 配置后等待约30分钟缓存生效';
    } else if (errCode === '1001502003' || errMsg.includes('client_id') || errMsg.includes('appId') ||
      errMsg.includes('clientId')) {
      this.loginErrorType = this.ERROR_TYPES.PARAM;
      this.loginError = 'Client ID 配置错误（错误码: 1001502003）\n'
        + '🔍 请检查：\n'
        + '  1. module.json5 中的 client_id 与 AGC 后台是否一致\n'
        + '  2. 注意不要有多余空格或特殊字符\n'
        + '  3. app.json5 中的 app_id 是否配置正确';
    } else if (errCode === '2300006' || errMsg.includes('resolve host') || errMsg.includes('域名解析')) {
      this.loginErrorType = this.ERROR_TYPES.NETWORK;
      this.loginError = '域名解析失败（错误码: 2300006）\n'
        + '🔍 请检查：\n'
        + '  1. 设备网络是否通畅（尝试切换WiFi/蜂窝网络）\n'
        + '  2. 服务器域名是否可访问\n'
        + '  3. 是否配置了网络代理需要调整';
    } else if (errCode === '1001500003' || errMsg.includes('scope') || errMsg.includes('permission')) {
      this.loginErrorType = this.ERROR_TYPES.AUTH;
      this.loginError = '权限/Scope 不匹配（错误码: 1001500003）\n'
        + '🔍 请检查：\n'
        + '  1. AGC后台是否申请了对应的Scope权限\n'
        + '  2. 个人开发者不支持"一键登录"功能\n'
        + '  3. 元服务需设置 supportAtomicService: true';
    } else if (errMsg.includes('timeout') || errMsg.includes('超时') || errCode === '401') {
      this.loginErrorType = this.ERROR_TYPES.TIMEOUT;
      this.loginError = '请求超时或参数错误（错误码: ' + (errCode || '401') + '）\n'
        + '🔍 请检查：\n'
        + '  1. 设备系统时间是否准确（误差超过5分钟会导致TLS握手失败）\n'
        + '  2. 请求参数是否完整（如 loginRequest 未设置参数）\n'
        + '  3. 网络连接是否稳定';
    } else if (errMsg.includes('500') || errMsg.includes('502') || errMsg.includes('503')) {
      this.loginErrorType = this.ERROR_TYPES.SERVER;
      this.loginError = '服务器返回异常（HTTP ' + (errMsg.match(/\d{3}/)?.[0] || '未知') + '）\n'
        + '🔍 请检查：\n'
        + '  1. 服务器端日志是否有异常\n'
        + '  2. Content-Type 请求头是否配置正确\n'
        + '  3. 请求体格式是否服务端期望的格式';
    } else if (errMsg.includes('certificate') || errMsg.includes('证书') || errMsg.includes('TLS')) {
      this.loginErrorType = this.ERROR_TYPES.CERT;
      this.loginError = '证书校验失败\n'
        + '🔍 请检查：\n'
        + '  1. 设备系统时间是否准确\n'
        + '  2. 服务器TLS版本是否≥1.2\n'
        + '  3. 企业证书是否已预置到设备信任链';
    } else {
      this.loginErrorType = this.ERROR_TYPES.UNKNOWN;
      this.loginError = '未知登录错误\n'
        + '详细信息: ' + errMsg + '\n'
        + '错误码: ' + (errCode || '无') + '\n'
        + '🔍 建议查看 hilog 日志获取更多信息';
    }

    // 显示错误横幅
    this.showErrorBanner = true;

    // 8秒后自动隐藏错误横幅
    setTimeout(() => {
      this.showErrorBanner = false;
    }, 8000);
  }

  // ---- 关闭错误提示 ----
  private dismissError(): void {
    this.showErrorBanner = false;
    this.loginError = '';
    this.loginErrorType = '';
    this.loginErrorCode = '';
  }

  // ---- 操作 ----

  private async doLogin(): Promise<void> {
    if (this.username.length === 0 || this.password.length === 0) {
      this.addLog('❌ 请输入用户名和密码');
      return;
    }
    this.addLog('🔄 正在登录...');
    // 登录前清除之前的错误
    this.dismissError();

    try {
      let success: boolean = await this.service.login(this.username, this.password);
      if (success) {
        this.isLoggedIn = true;
        this.userId = this.service.getLocalDeviceId();
        this.addLog('✅ 登录成功！用户ID: ' + this.userId);
      } else {
        // login 返回 false 但没有抛异常时的处理
        this.analyzeLoginError('服务返回登录失败，但无详细错误信息');
        this.addLog('❌ 登录失败（无详细错误）');
      }
    } catch (err) {
      const serviceErr: ServiceError = err as ServiceError;

      // ⭐ 增强：把原始 err 的完整信息输出到日志
      this.addLog('❌ 登录异常 - 原始信息:');
      this.addLog('  message: ' + serviceErr.message);
      this.addLog('  code: ' + (serviceErr.code || '无'));
      this.addLog('  name: ' + (serviceErr.name || '无'));
      this.addLog('  toString: ' + String(err));
      this.addLog('  JSON: ' + JSON.stringify(err));

      this.analyzeLoginError(serviceErr.message, serviceErr.code);
    }
  }

  private async doLogout(): Promise<void> {
    this.addLog('🔄 正在退出...');
    await this.service.logout();
    this.isLoggedIn = false;
    this.userId = '';
    this.username = '';
    this.password = '';
    this.dismissError(); // 退出时清除错误
    this.addLog('✅ 已退出登录');
  }

  private async doSync(): Promise<void> {
    if (!this.isLoggedIn) {
      this.addLog('❌ 请先登录');
      return;
    }
    this.isSyncing = true;
    this.syncResultText = '同步中...';
    this.addLog('🔄 开始同步...');
    try {
      let result: SyncResult = await this.service.syncNow(true);
      if (result.success) {
        this.syncResultText = '✅ 同步成功，共处理 ' + result.syncCount + ' 条数据';
        this.addLog('✅ 同步成功，共处理 ' + result.syncCount + ' 条数据');
      } else {
        this.syncResultText = '❌ 同步失败: ' + result.errorMsg;
        this.addLog('❌ 同步失败: ' + result.errorMsg);
      }
    } catch (err) {
      const error: Error = err as Error;
      this.syncResultText = '❌ 同步异常: ' + error.message;
      this.addLog('❌ 同步异常: ' + error.message);
    }
    this.isSyncing = false;
  }

  private async doUploadTest(): Promise<void> {
    if (!this.isLoggedIn) {
      this.addLog('❌ 请先登录');
      return;
    }
    this.uploadResultText = '上传中...';
    this.addLog('🔄 测试图片上传（模拟）...');
    try {
      let testUris: string[] = [];
      let result: string[] = await this.service.uploadImages(testUris);
      this.uploadResultText = '✅ 上传完成，返回 ' + result.length + ' 个URL';
      this.addLog('✅ 上传完成');
    } catch (err) {
      const error: Error = err as Error;
      this.uploadResultText = '❌ 上传失败: ' + error.message;
      this.addLog('❌ 上传失败: ' + error.message);
    }
  }

  private clearLog(): void {
    this.logLines = [];
    this.syncResultText = '';
    this.uploadResultText = '';
  }

  private addLog(msg: string): void {
    let time: string = new Date().toLocaleTimeString();
    this.logLines.push('[' + time + '] ' + msg);
    if (this.logLines.length > 100) {
      this.logLines.shift();
    }
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          // ---- 标题 ----
          Text('☁️ 分布式云同步测试')
            .fontSize(22)
            .fontWeight(700)
            .margin({ top: 20, bottom: 16 });

          // ---- 状态面板 ----
          Column() {
            Text('系统状态')
              .fontSize(16)
              .fontWeight(600)
              .width('100%');

            Row() {
              Text('服务状态:')
                .fontSize(14)
                .width(90);
              Text(this.serviceStatus)
                .fontSize(14)
                .fontColor(this.serviceStatus === '已就绪' ? Color.Green : Color.Orange);
            }.width('100%').margin({ top: 4 });

            Row() {
              Text('连接状态:')
                .fontSize(14)
                .width(90);
              Text(this.connectionStateText)
                .fontSize(14)
                .fontColor(this.connectionStateText === '已连接' ? Color.Green : Color.Gray);
            }.width('100%').margin({ top: 4 });

            Row() {
              Text('登录状态:')
                .fontSize(14)
                .width(90);
              Text(this.isLoggedIn ? '✅ 已登录' : '❌ 未登录')
                .fontSize(14)
                .fontColor(this.isLoggedIn ? Color.Green : Color.Red);
            }.width('100%').margin({ top: 4 });

            if (this.isLoggedIn) {
              Row() {
                Text('用户ID:')
                  .fontSize(14)
                  .width(90);
                Text(this.userId)
                  .fontSize(12)
                  .fontColor(Color.Blue);
              }.width('100%').margin({ top: 4 });
            }

            Text('最新消息: ' + this.lastMessage)
              .fontSize(12)
              .fontColor(Color.Gray)
              .margin({ top: 6 });
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .margin({ bottom: 12 });

          // ---- 登录区 ----
          if (!this.isLoggedIn) {
            Column() {
              Text('登录云服务器')
                .fontSize(16)
                .fontWeight(600)
                .width('100%')
                .margin({ bottom: 8 });

              TextInput({ placeholder: '用户名', text: this.username })
                .width('100%')
                .height(44)
                .borderRadius(8)
                .border({ width: 1, color: '#DDD' })
                .padding({ left: 12 })
                .onChange((val: string): void => {
                  this.username = val;
                });

              TextInput({ placeholder: '密码', text: this.password })
                .width('100%')
                .height(44)
                .borderRadius(8)
                .border({ width: 1, color: '#DDD' })
                .padding({ left: 12 })
                .type(InputType.Password)
                .margin({ top: 8 })
                .onChange((val: string): void => {
                  this.password = val;
                });

              Button('登录')
                .width('100%')
                .height(44)
                .backgroundColor('#007DFF')
                .fontColor(Color.White)
                .borderRadius(8)
                .margin({ top: 12 })
                .onClick(() => {
                  this.doLogin();
                });
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#F0F8FF')
            .borderRadius(8)
            .margin({ bottom: 12 });
          }

          // ---- 操作按钮 ----
          Column() {
            Text('功能测试')
              .fontSize(16)
              .fontWeight(600)
              .width('100%')
              .margin({ bottom: 8 });

            if (this.isLoggedIn) {
              Button('退出登录')
                .width('100%')
                .height(40)
                .backgroundColor('#FF6B6B')
                .fontColor(Color.White)
                .borderRadius(8)
                .margin({ bottom: 8 })
                .onClick(() => {
                  this.doLogout();
                });
            }

            Button('🔄 全量同步')
              .width('100%')
              .height(44)
              .backgroundColor('#007DFF')
              .fontColor(Color.White)
              .borderRadius(8)
              .margin({ bottom: 8 })
              .enabled(this.isLoggedIn && !this.isSyncing)
              .onClick(() => {
                this.doSync();
              });

            if (this.syncResultText.length > 0) {
              Text(this.syncResultText)
                .fontSize(13)
                .margin({ bottom: 8 });
            }

            Button('🖼️ 测试图片上传')
              .width('100%')
              .height(44)
              .backgroundColor('#4CAF50')
              .fontColor(Color.White)
              .borderRadius(8)
              .margin({ bottom: 8 })
              .enabled(this.isLoggedIn)
              .onClick(() => {
                this.doUploadTest();
              });

            if (this.uploadResultText.length > 0) {
              Text(this.uploadResultText)
                .fontSize(13)
                .margin({ bottom: 8 });
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFF8E1')
          .borderRadius(8)
          .margin({ bottom: 12 });

          // ---- 日志区 ----
          Column() {
            Row() {
              Text('📋 运行日志')
                .fontSize(16)
                .fontWeight(600);
              Blank();
              Button('清空日志')
                .fontSize(12)
                .height(28)
                .backgroundColor(Color.Gray)
                .fontColor(Color.White)
                .borderRadius(4)
                .onClick(() => {
                  this.clearLog();
                });
            }
            .width('100%')
            .margin({ bottom: 6 });

            List({ space: 2 }) {
              ForEach(this.logLines, (line: string, index: number): void => {
                ListItem() {
                  Text(line)
                    .fontSize(12)
                    .fontFamily('Courier New')
                    .fontColor(Color.Gray)
                    .width('100%');
                }
              }, (line: string, index: number): string => {
                return index.toString();
              });
            }
            .width('100%')
            .height(200)
            .border({ width: 1, color: '#EEE' })
            .borderRadius(6)
            .padding(8)
            .backgroundColor('#FAFAFA');
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F3E5F5')
          .borderRadius(8);
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Color.White);
      }
      .width('100%')
      .height('100%');

      // ---- 错误提示横幅（覆盖层） ----
      if (this.showErrorBanner) {
        Column() {
          // 错误类型标签 + 关闭按钮
          Row() {
            Text(this.loginErrorType)
              .fontSize(14)
              .fontWeight(700)
              .fontColor(Color.White);
            Blank();
            Button('✕')
              .fontSize(16)
              .fontColor(Color.White)
              .backgroundColor(Color.Transparent)
              .width(28)
              .height(28)
              .onClick(() => {
                this.dismissError();
              });
          }
          .width('100%')
          .margin({ bottom: 8 });

          // 错误码
          if (this.loginErrorCode.length > 0) {
            Text('错误码: ' + this.loginErrorCode)
              .fontSize(13)
              .fontColor(Color.White)
              .fontWeight(500)
              .width('100%')
              .margin({ bottom: 6 });
          }

          // 错误详情（支持多行）
          Text(this.loginError)
            .fontSize(13)
            .fontColor(Color.White)
            .lineHeight(20)
            .width('100%');
        }
        .width('90%')
        .padding(16)
        .backgroundColor(this.getErrorBgColor())
        .borderRadius(12)
        .shadow({
          radius: 12,
          color: '#66000000',
          offsetX: 0,
          offsetY: 4
        })
        .position({ x: '5%', y: 60 })
        // 使用 TransitionEffect，替代旧版对象字面量语法
        .transition(
          TransitionEffect.translate({ x: 0, y: -100 })
            .combine(TransitionEffect.opacity(0))
        )
        // 用 animation 控制动画时长
        .animation({
          duration: 300,
          curve: Curve.EaseInOut
        });
      }
    }
    .width('100%')
    .height('100%');
  }

  // ---- 根据错误类型返回背景色 ----
  private getErrorBgColor(): ResourceColor {
    switch (this.loginErrorType) {
      case this.ERROR_TYPES.CERT:
        return '#E65100'; // 橙色 - 证书问题
      case this.ERROR_TYPES.NETWORK:
        return '#1565C0'; // 蓝色 - 网络问题
      case this.ERROR_TYPES.AUTH:
        return '#C62828'; // 红色 - 认证问题
      case this.ERROR_TYPES.PARAM:
        return '#6A1B9A'; // 紫色 - 配置问题
      case this.ERROR_TYPES.TIMEOUT:
        return '#E65100'; // 橙色 - 超时
      case this.ERROR_TYPES.SERVER:
        return '#C62828'; // 红色 - 服务器问题
      default:
        return '#37474F'; // 深灰 - 未知错误
    }
  }
}