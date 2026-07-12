// api/DistributedApi.ts
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { PostModel } from '../model/PostModel';
import { PostRepository } from '../repository/PostRepository';
import { CommentRepository } from '../repository/CommentRepository';
import { CommentModel } from '../model/CommentModel';
import { Constants } from '../common/Constants';

/** 同步结果 */
export interface SyncResult {
  success: boolean;
  syncCount: number;
  errorMsg: string;
}

/** 登录结果 */
export interface LoginResult {
  success: boolean;
  data: boolean;
  message: string;
}

/** 个人资料 */
export interface UserProfile {
  displayNickname: string;
  avatar: string;
  bio: string;
}

/** 服务器响应 */
interface ServerResponse {
  success?: boolean;
  message?: string;
  data?: Record<string, Object>;
  displayNickname?: string;
  avatar?: string;
  bio?: string;
  urls?: string[];
  acceptedPostIds?: string[];
  acceptedCommentIds?: string[];
  syncCount?: number;
  errorMsg?: string;
}

/**
 * 分布式同步 API —— 通过 HTTP 与服务器同步
 */
class DistributedApi {
  private baseUrl: string = Constants.BASE_URL;

  /**
   * 获取当前登录 token
   */
  private getToken(): string {
    const token: string = AppStorage.get<string>('login_token') || '';
    return token;
  }

  /**
   * 保存 token
   */
  private saveToken(token: string): void {
    AppStorage.set<string>('login_token', token);
  }

  /**
   * 发起 HTTP 请求
   */
  // api/DistributedApi.ts — 只修改 request 方法中解析响应的部分

  private async request(
    method: string,
    path: string,
    body: Record<string, Object> | null
  ): Promise<ServerResponse | null> {
    const url: string = this.baseUrl + path;
    console.info('[DistributedApi] 发起请求: ' + method + ' ' + url);

    try {
      let requestMethod: http.RequestMethod;
      if (method === 'GET') {
        requestMethod = http.RequestMethod.GET;
      } else if (method === 'PUT') {
        requestMethod = http.RequestMethod.PUT;
      } else {
        requestMethod = http.RequestMethod.POST;
      }

      const headers: Record<string, string> = {
        'Content-Type': 'application/json'
      };

      const token: string = this.getToken();
      if (token.length > 0) {
        headers['authorization'] = 'Bearer ' + token;
      }

      // ★ 输出完整请求体用于调试
      const bodyStr: string = body ? JSON.stringify(body) : 'null';
      console.info('[DistributedApi] 请求体长度: ' + bodyStr.length + ' 字符');
      console.info('[DistributedApi] 请求体预览: ' + bodyStr.substring(0, 500));

      const requestOptions: http.HttpRequestOptions = {
        method: requestMethod,
        header: headers,
        extraData: body ? JSON.stringify(body) : undefined,
        connectTimeout: 15000,
        readTimeout: 15000
      };

      return new Promise<ServerResponse | null>((resolve: (value: ServerResponse | null) => void) => {
        const httpRequest: http.HttpRequest = http.createHttp();
        httpRequest.request(url, requestOptions, (err: Error, response: http.HttpResponse) => {
          httpRequest.destroy();
          if (err) {
            console.error('[DistributedApi] HTTP 请求失败: ' + err.message);
            resolve(null);
            return;
          }
          console.info('[DistributedApi] 响应状态码: ' + response.responseCode.toString());
          const rawResult: Object = response.result;
          if (response.responseCode === 200) {
            let parsedResult: ServerResponse | null = null;
            if (typeof rawResult === 'string') {
              try {
                parsedResult = JSON.parse(rawResult as string) as ServerResponse;
              } catch (parseErr) {
                console.error('[DistributedApi] JSON 解析失败: ' + (parseErr as Error).message);
                resolve(null);
                return;
              }
            } else {
              parsedResult = rawResult as ServerResponse;
            }
            console.info('[DistributedApi] 响应成功: ' + JSON.stringify(parsedResult).substring(0, 200));
            resolve(parsedResult);
          } else {
            console.error('[DistributedApi] 非200响应: ' + JSON.stringify(rawResult));
            resolve(null);
          }
        });
      });
    } catch (e) {
      console.error('[DistributedApi] request 方法异常: ' + (e as Error).message);
      return null;
    }
  }

  /**
   * 构建请求 body
   */
  private buildBody(keyValuePairs: string[][]): Record<string, Object> {
    const result: Record<string, Object> = {};
    for (let i = 0; i < keyValuePairs.length; i++) {
      const pair: string[] = keyValuePairs[i];
      result[pair[0]] = pair[1];
    }
    return result;
  }

  /**
   * 初始化（兼容旧接口）
   */
  async init(context: common.Context): Promise<void> {
    console.info('[DistributedApi] 初始化完成');
  }

  /**
   * 获取当前设备ID（兼容旧接口）
   */
  get localDeviceId(): string {
    return 'local_device_' + Date.now().toString();
  }

  /**
   * 检查是否就绪（兼容旧接口）
   */
  isReady(): boolean {
    return true;
  }

  // ============ 认证 ============

  /**
   * 登录
   */
  async login(username: string, password: string): Promise<LoginResult> {
    console.info('[DistributedApi] 开始登录: ' + username);
    try {
      const body: Record<string, Object> = this.buildBody([
        ['username', username],
        ['password', password]
      ]);
      const result: ServerResponse | null = await this.request('POST', '/api/auth/login', body);

      if (result === null) {
        console.error('[DistributedApi] 登录: 服务器无响应');
        return { success: false, data: false, message: '无法连接服务器' };
      }

      if (result.success === true && result.data) {
        const data: Record<string, Object> = result.data;
        const token: string = (data['token'] as string) || '';
        if (token.length > 0) {
          this.saveToken(token);
        }

        // ★ 从登录响应中直接设置所有个人资料
        const displayNickname: string = (data['displayNickname'] as string) || '用户';
        const avatar: string = (data['avatar'] as string) || '';
        const bio: string = (data['bio'] as string) || '这个人很懒，什么都没有写...';

        // ★ 强制写入 AppStorage，确保 UI 能读取到
        AppStorage.set<string>('display_nickname', displayNickname);
        AppStorage.set<string>('display_avatar', avatar);
        AppStorage.set<string>('display_bio', bio);

        console.info('[DistributedApi] 登录成功，昵称: ' + displayNickname + ', 头像: ' + avatar);

        return { success: true, data: true, message: '登录成功' };
      }

      return { success: false, data: false, message: result.message || '登录失败' };
    } catch (e) {
      console.error('[DistributedApi] 登录异常: ' + (e as Error).message);
      return { success: false, data: false, message: '登录异常: ' + (e as Error).message };
    }
  }

  async register(username: string, password: string): Promise<LoginResult> {
    console.info('[DistributedApi] 开始注册: ' + username);
    try {
      const body: Record<string, Object> = this.buildBody([
        ['username', username],
        ['password', password]
      ]);
      const result: ServerResponse | null = await this.request('POST', '/api/auth/register', body);

      if (result === null) {
        console.error('[DistributedApi] 注册: 服务器无响应');
        return { success: false, data: false, message: '无法连接服务器' };
      }

      if (result.success === true && result.data) {
        const data: Record<string, Object> = result.data;
        const token: string = (data['token'] as string) || '';
        if (token.length > 0) {
          this.saveToken(token);
        }

        // ★ 从注册响应中直接设置所有个人资料
        const displayNickname: string = (data['displayNickname'] as string) || '用户';
        const avatar: string = (data['avatar'] as string) || '';
        const bio: string = (data['bio'] as string) || '这个人很懒，什么都没有写...';

        // ★ 强制写入 AppStorage
        AppStorage.set<string>('display_nickname', displayNickname);
        AppStorage.set<string>('display_avatar', avatar);
        AppStorage.set<string>('display_bio', bio);

        console.info('[DistributedApi] 注册成功，昵称: ' + displayNickname + ', 头像: ' + avatar);

        return { success: true, data: true, message: '注册成功' };
      }

      return { success: false, data: false, message: result.message || '注册失败' };
    } catch (e) {
      console.error('[DistributedApi] 注册异常: ' + (e as Error).message);
      return { success: false, data: false, message: '注册异常: ' + (e as Error).message };
    }
  }

  /**
   * 退出登录
   */
  async logout(): Promise<void> {
    try {
      const emptyBody: Record<string, Object> = {};
      await this.request('POST', '/api/auth/logout', emptyBody);
      AppStorage.set<string>('login_token', '');
    } catch (_) {}
  }

  /**
   * 获取个人资料
   */
  async getProfile(): Promise<UserProfile> {
    try {
      const result: ServerResponse | null = await this.request('GET', '/api/auth/profile', null);
      if (result && result.success === true && result.data) {
        const data: Record<string, Object> = result.data;
        return {
          displayNickname: (data['displayNickname'] as string) || '',
          avatar: (data['avatar'] as string) || '',
          bio: (data['bio'] as string) || ''
        };
      }
    } catch (_) {}
    return { displayNickname: '', avatar: '', bio: '' };
  }

  /**
   * 更新个人资料
   */
  async updateProfile(profile: UserProfile): Promise<UserProfile> {
    try {
      const body: Record<string, Object> = this.buildBody([
        ['displayNickname', profile.displayNickname],
        ['avatar', profile.avatar],
        ['bio', profile.bio]
      ]);
      const result: ServerResponse | null = await this.request('PUT', '/api/auth/profile', body);
      if (result && result.success === true && result.data) {
        const data: Record<string, Object> = result.data;
        return {
          displayNickname: (data['displayNickname'] as string) || profile.displayNickname,
          avatar: (data['avatar'] as string) || profile.avatar,
          bio: (data['bio'] as string) || profile.bio
        };
      }
    } catch (_) {}
    return profile;
  }

  /**
   * 上传图片
   */
  async uploadImages(imagePaths: string[]): Promise<string[]> {
    try {
      const body: Record<string, Object> = {};
      body['imagePaths'] = JSON.stringify(imagePaths);
      const result: ServerResponse | null = await this.request('POST', '/api/images/upload', body);
      if (result && result.urls) {
        return result.urls;
      }
    } catch (_) {}
    return imagePaths;
  }

  // ============ 同步 ============

  /**
   * 同步到云端（上传 + 下载）
   */
  async sync(isFullSync: boolean): Promise<SyncResult> {
    let totalSynced: number = 0;

    try {
      const postRepo: PostRepository = new PostRepository();
      const commentRepo: CommentRepository = new CommentRepository();

      const unsyncedPosts: PostModel[] = await postRepo.queryUnsyncedPosts();
      const unsyncedComments: CommentModel[] = await commentRepo.queryUnsyncedComments();

      // 构建上传 body — 手动构建 JSON 字符串避免 Record<string, Object> 序列化数组问题
      let uploadJson: string = '';
      if (unsyncedPosts.length === 0 && unsyncedComments.length === 0) {
        uploadJson = '{"deviceId":"' + this.localDeviceId.replace(/"/g, '\\"') + '"}';
      } else {
        let postsJson: string = '[]';
        if (unsyncedPosts.length > 0) {
          postsJson = '[';
          for (let pi = 0; pi < unsyncedPosts.length; pi++) {
            const p: PostModel = unsyncedPosts[pi];
            if (pi > 0) postsJson += ',';
            const imgArr: string[] = p.getImagePathArray();
            let imgArrJson: string = '[]';
            try { imgArrJson = JSON.stringify(imgArr); } catch (_) {}
            const imgJson: string = '"' + imgArrJson.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
            const content: string = p.content.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
            postsJson += '{"postId":"' + p.postId.replace(/"/g, '\\"') +
              '","userId":"' + p.userId.replace(/"/g, '\\"') +
              '","userName":"' + p.userName.replace(/"/g, '\\"') +
              '","userAvatar":"' + p.userAvatar.replace(/"/g, '\\"') +
              '","content":"' + content + '","imagePaths":' + imgJson +
              ',"imageCount":' + p.imageCount +
              ',"categoryId":"' + p.categoryId.replace(/"/g, '\\"') +
              '","categoryName":"' + p.categoryName.replace(/"/g, '\\"') +
              '","likeCount":' + p.likeCount +
              ',"commentCount":' + p.commentCount +
              ',"createTime":' + p.createTime +
              ',"updateTime":' + p.updateTime +
              ',"deviceId":"' + p.deviceId.replace(/"/g, '\\"') + '"}';
          }
          postsJson += ']';
        }
        let commentsJson: string = '[]';
        if (unsyncedComments.length > 0) {
          commentsJson = '[';
          for (let ci = 0; ci < unsyncedComments.length; ci++) {
            const c: CommentModel = unsyncedComments[ci];
            if (ci > 0) commentsJson += ',';
            const content: string = c.content.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
            commentsJson += '{"commentId":"' + c.commentId.replace(/"/g, '\\"') +
              '","postId":"' + c.postId.replace(/"/g, '\\"') +
              '","userId":"' + c.userId.replace(/"/g, '\\"') +
              '","userName":"' + c.userName.replace(/"/g, '\\"') +
              '","content":"' + content + '","createTime":' + c.createTime +
              ',"deviceId":"' + c.deviceId.replace(/"/g, '\\"') + '"}';
          }
          commentsJson += ']';
        }
        uploadJson = '{"deviceId":"' + this.localDeviceId.replace(/"/g, '\\"') +
          '","posts":' + postsJson + ',"comments":' + commentsJson + '}';
      }

      console.info('[DistributedApi] 上传帖子: ' + unsyncedPosts.length + ' 条');
      if (unsyncedPosts.length > 0) {
        console.info('[DistributedApi] 第一条帖子 imagePaths: ' + unsyncedPosts[0].imagePaths);
      }

      const uploadResult: ServerResponse | null = await this.requestRaw('POST', '/api/sync/upload', uploadJson);

      if (uploadResult) {
        console.info('[DistributedApi] 上传响应: ' + JSON.stringify(uploadResult));
        const acceptedPostIds: string[] = uploadResult.acceptedPostIds || [];
        const acceptedCommentIds: string[] = uploadResult.acceptedCommentIds || [];

        for (let i = 0; i < acceptedPostIds.length; i++) {
          await postRepo.updatePostSyncStatus(acceptedPostIds[i], 1);
        }
        for (let i = 0; i < acceptedCommentIds.length; i++) {
          await commentRepo.updateCommentSyncStatus(acceptedCommentIds[i], 1);
        }

        totalSynced += acceptedPostIds.length + acceptedCommentIds.length;
      } else {
        console.error('[DistributedApi] 上传失败，服务器无响应');
      }

      const downloadBody: Record<string, Object> = {};
      downloadBody['lastSyncTimestamp'] = isFullSync ? 0 : (Date.now() - 3600000);
      downloadBody['deviceId'] = this.localDeviceId;

      const downloadResult: ServerResponse | null = await this.request('POST', '/api/sync/download', downloadBody);

      if (downloadResult && downloadResult.data) {
        const data: Record<string, Object> = downloadResult.data;

        let serverPosts: Record<string, Object>[] = [];
        const rawPosts: Object | undefined = data['posts'];
        if (rawPosts !== undefined) {
          if (typeof rawPosts === 'string') {
            try { serverPosts = JSON.parse(rawPosts as string) as Record<string, Object>[]; } catch (_) {}
          } else {
            serverPosts = rawPosts as Record<string, Object>[];
          }
        }

        let serverComments: Record<string, Object>[] = [];
        const rawComments: Object | undefined = data['comments'];
        if (rawComments !== undefined) {
          if (typeof rawComments === 'string') {
            try { serverComments = JSON.parse(rawComments as string) as Record<string, Object>[]; } catch (_) {}
          } else {
            serverComments = rawComments as Record<string, Object>[];
          }
        }

        for (let i = 0; i < serverPosts.length; i++) {
          const sp: Record<string, Object> = serverPosts[i];
          const spId: string = (sp['postId'] as string) || '';
          if (spId.length > 0) {
            const existingPost: PostModel | null = await postRepo.queryPostById(spId);
            if (existingPost === null) {
              const post: PostModel = new PostModel();
              post.postId = spId;
              post.userId = (sp['userId'] as string) || '';
              post.userName = (sp['userName'] as string) || '';
              post.userAvatar = (sp['userAvatar'] as string) || '';
              post.content = (sp['content'] as string) || '';
              const rawImagePaths: Object | undefined = sp['imagePaths'];
              if (typeof rawImagePaths === 'string') {
                post.imagePaths = rawImagePaths as string;
              } else {
                try {
                  post.imagePaths = JSON.stringify(rawImagePaths);
                } catch (_) {
                  post.imagePaths = '[]';
                }
              }
              post.imageCount = (sp['imageCount'] as number) || 0;
              post.categoryId = (sp['categoryId'] as string) || '';
              post.categoryName = (sp['categoryName'] as string) || '';
              post.likeCount = (sp['likeCount'] as number) || 0;
              post.commentCount = (sp['commentCount'] as number) || 0;
              post.createTime = (sp['createTime'] as number) || Date.now();
              post.updateTime = (sp['updateTime'] as number) || Date.now();
              post.deviceId = (sp['deviceId'] as string) || '';
              post.syncStatus = 1;
              await postRepo.insertPost(post);
              totalSynced++;
            }
          }
        }

        for (let i = 0; i < serverComments.length; i++) {
          const sc: Record<string, Object> = serverComments[i];
          const scId: string = (sc['commentId'] as string) || '';
          if (scId.length > 0) {
            const existingComment = await commentRepo.queryCommentById(scId);
            if (existingComment === null) {
              const comment: CommentModel = new CommentModel();
              comment.commentId = scId;
              comment.postId = (sc['postId'] as string) || '';
              comment.userId = (sc['userId'] as string) || '';
              comment.userName = (sc['userName'] as string) || '';
              comment.content = (sc['content'] as string) || '';
              comment.createTime = (sc['createTime'] as number) || Date.now();
              comment.deviceId = (sc['deviceId'] as string) || '';
              comment.syncStatus = 1;
              await commentRepo.insertComment(comment);
              totalSynced++;
            }
          }
        }
      }

      return {
        success: true,
        syncCount: totalSynced,
        errorMsg: ''
      };
    } catch (e) {
      const errorMsg: string = (e as Error).message;
      return {
        success: false,
        syncCount: totalSynced,
        errorMsg: errorMsg
      };
    }
  }

  private async requestRaw(method: string, path: string, jsonBody: string): Promise<ServerResponse | null> {
    const url: string = this.baseUrl + path;
    console.info('[DistributedApi] 发起请求(POST): ' + url);
    try {
      let requestMethod: http.RequestMethod = http.RequestMethod.POST;
      if (method === 'GET') {
        requestMethod = http.RequestMethod.GET;
      } else if (method === 'PUT') {
        requestMethod = http.RequestMethod.PUT;
      }

      const headers: Record<string, string> = {
        'Content-Type': 'application/json'
      };
      const token: string = this.getToken();
      if (token.length > 0) {
        headers['authorization'] = 'Bearer ' + token;
      }

      console.info('[DistributedApi] 请求体长度: ' + jsonBody.length + ' 字符');
      console.info('[DistributedApi] 请求体预览: ' + jsonBody.substring(0, 500));

      const requestOptions: http.HttpRequestOptions = {
        method: requestMethod,
        header: headers,
        extraData: jsonBody,
        connectTimeout: 15000,
        readTimeout: 15000
      };

      return new Promise<ServerResponse | null>((resolve: (value: ServerResponse | null) => void) => {
        const httpRequest: http.HttpRequest = http.createHttp();
        httpRequest.request(url, requestOptions, (err: Error, response: http.HttpResponse) => {
          httpRequest.destroy();
          if (err) {
            console.error('[DistributedApi] HTTP 请求失败: ' + err.message);
            resolve(null);
            return;
          }
          console.info('[DistributedApi] 响应状态码: ' + response.responseCode.toString());
          const rawResult: Object = response.result;
          if (response.responseCode === 200) {
            let parsedResult: ServerResponse | null = null;
            if (typeof rawResult === 'string') {
              try {
                parsedResult = JSON.parse(rawResult as string) as ServerResponse;
              } catch (parseErr) {
                console.error('[DistributedApi] JSON 解析失败: ' + (parseErr as Error).message);
                resolve(null);
                return;
              }
            } else {
              parsedResult = rawResult as ServerResponse;
            }
            console.info('[DistributedApi] 响应成功: ' + JSON.stringify(parsedResult).substring(0, 200));
            resolve(parsedResult);
          } else {
            console.error('[DistributedApi] 非200响应: ' + JSON.stringify(rawResult));
            resolve(null);
          }
        });
      });
    } catch (e) {
      console.error('[DistributedApi] requestRaw 异常: ' + (e as Error).message);
      return null;
    }
  }
}

export const distributedApi = new DistributedApi();