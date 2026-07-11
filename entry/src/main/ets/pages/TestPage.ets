// SocialMediaMain.ets
import { postApi } from '../api/PostApi';
import { commentApi } from '../api/CommentApi';
import { aiClassifyApi } from '../api/AIClassifyApi';
import { distributedApi } from '../api/DistributedApi';
import { Constants } from '../common/Constants';
import { promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { LikedCache, PostLikedInfo } from '../common/LikedCache';
import { SessionManager } from '../common/SessionManager';
import { camera, cameraPicker } from '@kit.CameraKit';
import { PostModel } from '../model/PostModel';

interface TabItemType {
  title: string;
  icon: Resource;
  selectedIcon: Resource;
}

interface CommentItemType {
  username: string;
  content: string;
}

interface RecognizeRecord {
  result: string;
  detail: string;
  timestamp: number;
}

interface FeedItemType {
  id: number;
  postId: string;
  type: string;
  url: string;
  username: string;
  userId: string;
  avatar: string;
  description: string;
  createTime: number;
  likes: number;
  comments: number;
  isLiked: boolean;
  commentsList: CommentItemType[];
  categoryId: string;
  categoryName: string;
}

PersistentStorage.persistProp('ai_recognize_records', []);
PersistentStorage.persistProp('is_logged_in', false);
PersistentStorage.persistProp('display_nickname', '');
PersistentStorage.persistProp('display_avatar', '');
PersistentStorage.persistProp('display_bio', '这个人很懒，什么都没有写...');
PersistentStorage.persistProp('login_username', '');

function generateRandomNickname(): string {
  const adjectives: string[] = [
    '快乐', '阳光', '可爱', '温柔', '勇敢', '聪明', '活泼', '安静',
    '热情', '幽默', '大方', '善良', '自信', '独立', '坚强', '乐观',
    '文艺', '浪漫', '清新', '自然'
  ];
  const nouns: string[] = [
    '小猫', '小狗', '兔子', '小熊', '星星', '月亮', '太阳', '云朵',
    '风铃', '彩虹', '海豚', '鲸鱼', '燕子', '蝴蝶', '雪花', '叶子'
  ];
  const adj = adjectives[Math.floor(Math.random() * adjectives.length)];
  const noun = nouns[Math.floor(Math.random() * nouns.length)];
  const suffix = Math.floor(1000 + Math.random() * 9000).toString();
  return adj + noun + '_' + suffix;
}

@Entry
@Component
struct SocialMediaMain {
  @State currentTabIndex: number = 0;
  @State currentTitle: string = '首页';
  @State showGlobalImagePreview: boolean = false;
  @State previewImageUrl: string = '';
  @State myWorks: Array<FeedItemType> = [];
  @State feedData: Array<FeedItemType> = [];
  @State isLoadingFeed: boolean = false;
  @State loadError: string = '';
  @State initError: string = '';
  @State likedIds: string[] = [];

  @StorageLink('display_nickname') displayNickname: string = '';
  @StorageLink('display_avatar') displayAvatar: string = '';
  @StorageLink('display_bio') displayBio: string = '这个人很懒，什么都没有写...';
  @StorageLink('is_logged_in') isLoggedIn: boolean = false;

  private currentFeedPage: number = 1;
  private hasMoreFeed: boolean = true;
  private tabBarHeight: number = 72;
  private feedIdCounter: number = 1;
  private pollingTimer: number = -1;
  private uiContext?: common.Context;
  private initStarted: boolean = false;

  private tabItems: Array<TabItemType> = [
    { title: '首页', icon: $r('app.media.home'), selectedIcon: $r('app.media.home_selected') },
    { title: '分类', icon: $r('app.media.classify'), selectedIcon: $r('app.media.classify_selected') },
    { title: '发布', icon: $r('app.media.publish'), selectedIcon: $r('app.media.publish_selected') },
    { title: 'AI识图', icon: $r('app.media.ai'), selectedIcon: $r('app.media.ai_selected') },
    { title: '我', icon: $r('app.media.me'), selectedIcon: $r('app.media.me_selected') }
  ];

  private isPostLiked(postId: string): boolean {
    for (let i = 0; i < this.likedIds.length; i++) {
      if (this.likedIds[i] === postId) return true;
    }
    return false;
  }

  handleImageClick(imageUrl: string): void {
    this.previewImageUrl = imageUrl;
    this.showGlobalImagePreview = true;
  }

  // ★ 退出时清所有数据
  private clearPersonalData(): void {
    this.feedData = [];
    this.myWorks = [];
    this.likedIds = [];
    LikedCache.clearMemory();
    this.currentFeedPage = 1;
    this.hasMoreFeed = true;
    this.feedIdCounter = 1;
  }

  // 登录后刷新点赞回写 feed
  private async refreshLikedDataAfterLogin(): Promise<void> {
    const loginUsername: string = AppStorage.get<string>('login_username') || '';
    if (loginUsername.length === 0) return;

    LikedCache.setCurrentUser(loginUsername);
    this.likedIds = await LikedCache.getLikedIds();

    const updatedFeed: FeedItemType[] = [];
    for (let i = 0; i < this.feedData.length; i++) {
      const item = this.feedData[i];
      updatedFeed.push({
        id: item.id, postId: item.postId, type: item.type, url: item.url,
        username: item.username, userId: item.userId, avatar: item.avatar,
        description: item.description, createTime: item.createTime,
        likes: item.likes, comments: item.comments,
        isLiked: this.isPostLiked(item.postId),
        commentsList: item.commentsList, categoryId: item.categoryId,
        categoryName: item.categoryName
      });
    }
    this.feedData = updatedFeed;

    const updatedWorks: FeedItemType[] = [];
    for (let i = 0; i < this.myWorks.length; i++) {
      const item = this.myWorks[i];
      updatedWorks.push({
        id: item.id, postId: item.postId, type: item.type, url: item.url,
        username: item.username, userId: item.userId, avatar: item.avatar,
        description: item.description, createTime: item.createTime,
        likes: item.likes, comments: item.comments,
        isLiked: this.isPostLiked(item.postId),
        commentsList: item.commentsList, categoryId: item.categoryId,
        categoryName: item.categoryName
      });
    }
    this.myWorks = updatedWorks;
  }

  // ============ 生命周期 ============

  aboutToAppear(): void {
    if (this.initStarted) return;
    this.initStarted = true;

    try {
      this.uiContext = getContext(this);
      AppStorage.setOrCreate('globalAbilityContext', this.uiContext);
      const existingNickname: string = AppStorage.get<string>('display_nickname') || '';
      if (existingNickname.length === 0) {
      }
      this.initializeAsync();
    } catch (err) {
      this.initError = '初始化失败: ' + (err as Error).message;
    }
  }

  aboutToDisappear(): void {
    if (this.pollingTimer > 0) {
      clearInterval(this.pollingTimer);
      this.pollingTimer = -1;
    }
  }

  private async initializeAsync(): Promise<void> {
    try { aiClassifyApi.preload(null).catch(() => {}); } catch (_) {}

    try {
      const autoLoggedIn: boolean = await SessionManager.autoLogin();
      if (autoLoggedIn) {
        this.isLoggedIn = true;

        let loginUsername: string = AppStorage.get<string>('login_username') || '';
        if (loginUsername.length === 0) {
          try {
            const savedUsername = await SessionManager.getSavedUsername();
            if (savedUsername.length > 0) {
              loginUsername = savedUsername;
              AppStorage.set<string>('login_username', loginUsername);
            }
          } catch (_) {}
        }

        if (loginUsername.length > 0) {
          LikedCache.setCurrentUser(loginUsername);
          // ★ 从 Preferences 加载缓存的点赞数据
          this.likedIds = await LikedCache.loadFromStorage();
          console.info('[SocialMediaMain] 已加载点赞: ' + this.likedIds.length + ' 条');
        }

        // ★ 从服务器获取个人资料，如果失败则保留本地已有值
        try {
          const profile = await distributedApi.getProfile();
          if (profile.displayNickname.length > 0) {
            AppStorage.set<string>('display_nickname', profile.displayNickname);
          }
          if (profile.avatar.length > 0) {
            AppStorage.set<string>('display_avatar', profile.avatar);
          }
          if (profile.bio.length > 0) {
            AppStorage.set<string>('display_bio', profile.bio);
          }
        } catch (err) {
          console.warn('[SocialMediaMain] 加载个人资料失败，保留本地值:', (err as Error).message);
        }

        if (distributedApi.isReady() && !distributedApi.localDeviceId.startsWith('local_')) {
          await distributedApi.sync(true);
          this.startPolling();
        }
      } else {
        this.isLoggedIn = false;
      }
    } catch (err) {
      console.warn('[SocialMediaMain] 自动登录异常:', (err as Error).message);
      this.isLoggedIn = false;
    }

    await this.loadFeed(true);
  }

  private startPolling(): void {
    if (this.pollingTimer > 0) {
      clearInterval(this.pollingTimer);
    }
    this.pollingTimer = setInterval(() => {
      try {
        if (distributedApi.isReady()) {
          distributedApi.sync(false);
        }
      } catch (_) {}
    }, 30000);
  }

  // ============ 加载 Feed ============

  async loadFeed(refresh: boolean): Promise<void> {
    if (this.isLoadingFeed) return;
    this.isLoadingFeed = true;
    this.loadError = '';

    if (refresh) {
      this.currentFeedPage = 1;
      this.hasMoreFeed = true;
    }
    if (!this.hasMoreFeed && !refresh) {
      this.isLoadingFeed = false;
      return;
    }

    try {
      const result = await postApi.getList(this.currentFeedPage, Constants.PAGE_SIZE);
      if (result.success && result.data !== null) {
        const currentUserId: string = AppStorage.get<string>('login_username') || '';

        const newItems: FeedItemType[] = [];
        for (let i = 0; i < result.data.length; i++) {
          const post = result.data[i];
          const images: string[] = post.getImagePathArray();
          const postUserId: string = post.userId || post.userName;

          // ★ 改用 this.isPostLiked() 而不是 post.isLikedByUser()
          const serverIsLiked: boolean = this.isPostLiked(post.postId);

          const item: FeedItemType = {
            id: this.feedIdCounter++,
            postId: post.postId,
            type: 'image',
            url: images.length > 0 ? images[0] : '',
            username: post.userName,
            userId: postUserId,
            avatar: post.userAvatar,
            description: post.content,
            createTime: post.createTime || Date.now(),
            likes: post.likeCount,
            comments: post.commentCount,
            isLiked: serverIsLiked,
            commentsList: [],
            categoryId: post.categoryId,
            categoryName: post.categoryName,
          };

          try {
            const commentResult = await commentApi.getAllByPost(post.postId);
            if (commentResult.success && commentResult.data !== null) {
              const commentItems: CommentItemType[] = [];
              for (let j = 0; j < commentResult.data.length; j++) {
                const c = commentResult.data[j];
                commentItems.push({
                  username: c.userName || '用户',
                  content: c.content
                });
              }
              item.commentsList = commentItems.length > 0 ? commentItems : [];
            }
          } catch (_) {}
          newItems.push(item);
        }

        // ★ 更新 LikedCache 缓存（不再使用 likedBy）
        const currentLikedInfo: PostLikedInfo[] = [];
        for (let k = 0; k < this.likedIds.length; k++) {
          currentLikedInfo.push({ postId: this.likedIds[k], isLiked: true });
        }
        LikedCache.extractFromFeed(currentLikedInfo);

        if (refresh) {
          this.feedData = newItems;
        } else {
          const existingIds: string[] = [];
          for (let i = 0; i < this.feedData.length; i++) {
            existingIds.push(this.feedData[i].postId);
          }
          const uniqueNewItems: FeedItemType[] = [];
          for (let i = 0; i < newItems.length; i++) {
            let found: boolean = false;
            for (let j = 0; j < existingIds.length; j++) {
              if (newItems[i].postId === existingIds[j]) {
                found = true;
                break;
              }
            }
            if (!found) {
              uniqueNewItems.push(newItems[i]);
              existingIds.push(newItems[i].postId);
            }
          }
          this.feedData = [...this.feedData, ...uniqueNewItems];
        }

        this.hasMoreFeed = newItems.length >= Constants.PAGE_SIZE;
        if (this.hasMoreFeed) this.currentFeedPage++;
      } else {
        this.loadError = result.message;
      }
    } catch (err) {
      this.loadError = '加载失败: ' + (err as Error).message;
    }
    this.isLoadingFeed = false;
  }

  // ============ 点赞/评论状态同步 ============

  async handleLikeChange(postId: string, isLiked: boolean, newCount: number): Promise<void> {
    // ★ 服务器 API 已在 FeedItem.handleLikeClick 中调用
    // ★ 这里只更新本地缓存
    if (isLiked) {
      LikedCache.addToMemory(postId);
      let found: boolean = false;
      for (let i = 0; i < this.likedIds.length; i++) {
        if (this.likedIds[i] === postId) {
          found = true;
          break;
        }
      }
      if (!found) {
        this.likedIds.push(postId);
      }
    } else {
      LikedCache.removeFromMemory(postId);
      const newIds: string[] = [];
      for (let i = 0; i < this.likedIds.length; i++) {
        if (this.likedIds[i] !== postId) {
          newIds.push(this.likedIds[i]);
        }
      }
      this.likedIds = newIds;
    }

    // 更新 feedData
    const updatedFeed: FeedItemType[] = [];
    for (let i = 0; i < this.feedData.length; i++) {
      const item = this.feedData[i];
      if (item.postId === postId) {
        updatedFeed.push({
          id: item.id, postId: item.postId, type: item.type, url: item.url,
          username: item.username, userId: item.userId, avatar: item.avatar,
          description: item.description, createTime: item.createTime,
          likes: newCount, comments: item.comments, isLiked: isLiked,
          commentsList: item.commentsList, categoryId: item.categoryId,
          categoryName: item.categoryName
        });
      } else {
        updatedFeed.push({
          id: item.id, postId: item.postId, type: item.type, url: item.url,
          username: item.username, userId: item.userId, avatar: item.avatar,
          description: item.description, createTime: item.createTime,
          likes: item.likes, comments: item.comments, isLiked: item.isLiked,
          commentsList: item.commentsList, categoryId: item.categoryId,
          categoryName: item.categoryName
        });
      }
    }
    this.feedData = updatedFeed;

    // 更新 myWorks
    const updatedWorks: FeedItemType[] = [];
    for (let i = 0; i < this.myWorks.length; i++) {
      const item = this.myWorks[i];
      if (item.postId === postId) {
        updatedWorks.push({
          id: item.id, postId: item.postId, type: item.type, url: item.url,
          username: item.username, userId: item.userId, avatar: item.avatar,
          description: item.description, createTime: item.createTime,
          likes: newCount, comments: item.comments, isLiked: isLiked,
          commentsList: item.commentsList, categoryId: item.categoryId,
          categoryName: item.categoryName
        });
      } else {
        updatedWorks.push({
          id: item.id, postId: item.postId, type: item.type, url: item.url,
          username: item.username, userId: item.userId, avatar: item.avatar,
          description: item.description, createTime: item.createTime,
          likes: item.likes, comments: item.comments, isLiked: item.isLiked,
          commentsList: item.commentsList, categoryId: item.categoryId,
          categoryName: item.categoryName
        });
      }
    }
    this.myWorks = updatedWorks;
  }

  // ============ 删除帖子 ============

  async handleDelete(postId: string): Promise<void> {
    try {
      const result = await postApi.delete(postId);
      if (result.success) {
        const newFeedData: FeedItemType[] = [];
        for (let i = 0; i < this.feedData.length; i++) {
          if (this.feedData[i].postId !== postId) {
            newFeedData.push(this.feedData[i]);
          }
        }
        this.feedData = newFeedData;

        const newMyWorks: FeedItemType[] = [];
        for (let i = 0; i < this.myWorks.length; i++) {
          if (this.myWorks[i].postId !== postId) {
            newMyWorks.push(this.myWorks[i]);
          }
        }
        this.myWorks = newMyWorks;

        promptAction.showToast({ message: '已删除', duration: 1500 });
      } else {
        promptAction.showToast({ message: '删除失败: ' + result.message, duration: 2000 });
      }
    } catch (err) {
      promptAction.showToast({ message: '删除异常: ' + (err as Error).message, duration: 2000 });
    }
  }

  // ============ 发布帖子 ============

  async handlePublish(description: string, imageUrl: string): Promise<void> {
    try {
      const loginUsername: string = AppStorage.get<string>('login_username') || 'local_user';
      const deviceId: string = AppStorage.get<string>('device_id') || 'local_device';
      const imagePaths: string[] = imageUrl.length > 0 ? [imageUrl] : [];

      const publishName = this.displayNickname.length > 0 ? this.displayNickname : '用户';
      const publishAvatar = this.displayAvatar;

      const result = await postApi.publishWithAI(
        loginUsername, publishName, publishAvatar, description, imagePaths, deviceId
      );

      if (result.success && result.data !== null) {
        const post = result.data;
        const images: string[] = post.getImagePathArray();
        const newPost: FeedItemType = {
          id: this.feedIdCounter++,
          postId: post.postId,
          type: 'image',
          url: images.length > 0 ? images[0] : '',
          username: publishName,
          userId: loginUsername,
          avatar: publishAvatar,
          description: description || '分享我的生活',
          createTime: Date.now(),
          likes: 0,
          comments: 0,
          isLiked: false,
          commentsList: [],
          categoryId: post.categoryId,
          categoryName: post.categoryName,
        };

        this.feedData = [newPost, ...this.feedData];
        this.myWorks = [newPost, ...this.myWorks];
        this.currentTabIndex = 0;
        this.currentTitle = '首页';

        if (distributedApi.isReady()) {
          distributedApi.sync(false);
        }
      }
    } catch (err) {
      promptAction.showToast({ message: '发布失败: ' + (err as Error).message, duration: 2000 });
    }
  }

  // ============ 加载我的作品 ============

  async loadMyWorksFromApi(): Promise<void> {
    try {
      const result = await postApi.getList(1, 100);
      if (result.success && result.data !== null) {
        const currentUserId: string = AppStorage.get<string>('login_username') || '';
        const currentName: string = this.displayNickname.length > 0 ? this.displayNickname : '用户';

        const userPosts: FeedItemType[] = [];
        for (let i = 0; i < result.data.length; i++) {
          const post = result.data[i];
          const postUserId: string = post.userId || '';
          let isMyPost: boolean = false;

          if (currentUserId.length > 0 && postUserId.length > 0) {
            isMyPost = (postUserId === currentUserId);
          } else {
            isMyPost = (post.userName === currentName);
          }

          if (isMyPost) {
            const images: string[] = post.getImagePathArray();
            userPosts.push({
              id: this.feedIdCounter++,
              postId: post.postId,
              type: 'image',
              url: images.length > 0 ? images[0] : '',
              username: post.userName,
              userId: postUserId,
              avatar: post.userAvatar,
              description: post.content,
              createTime: post.createTime || Date.now(),
              likes: post.likeCount,
              comments: post.commentCount,
              isLiked: this.isPostLiked(post.postId),
              commentsList: [],
              categoryId: post.categoryId,
              categoryName: post.categoryName,
            });
          }
        }

        const existingIds: string[] = [];
        for (let i = 0; i < this.myWorks.length; i++) {
          existingIds.push(this.myWorks[i].postId);
        }
        for (let i = 0; i < userPosts.length; i++) {
          let found = false;
          for (let j = 0; j < existingIds.length; j++) {
            if (userPosts[i].postId === existingIds[j]) {
              found = true;
              break;
            }
          }
          if (!found) {
            this.myWorks.push(userPosts[i]);
            existingIds.push(userPosts[i].postId);
          }
        }
      }
    } catch (err) {
      console.warn('[SocialMediaMain] 加载我的作品失败:', (err as Error).message);
    }
  }

  // ============ 计算获赞总数 ============
  private getTotalLikes(): number {
    let total = 0;
    for (let i = 0; i < this.myWorks.length; i++) {
      total += this.myWorks[i].likes;
    }
    return total;
  }

  build() {
    Stack() {
      Column() {
        Stack() {
          if (this.initError.length > 0) {
            Column() {
              Text('⚠️ 初始化失败').fontSize(16).fontColor('#FF6B6B').margin({ bottom: 10 })
              Text(this.initError).fontSize(13).fontColor('#999999').textAlign(TextAlign.Center)
              Button('重试').width(100).height(36).fontSize(14).margin({ top: 10 })
                .onClick(() => { this.initError = ''; this.initStarted = false; this.aboutToAppear(); })
            }
            .width('100%').height('100%').justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.currentTabIndex === 0) {
            if (this.isLoadingFeed && this.feedData.length === 0) {
              Column() {
                LoadingProgress().width(40).height(40)
                Text('加载中...').fontSize(14).fontColor('#999999').margin({ top: 10 })
              }.width('100%').height('100%').justifyContent(FlexAlign.Center)
            } else if (this.loadError.length > 0 && this.feedData.length === 0) {
              Column() {
                Text('加载失败').fontSize(14).fontColor('#FF0000').margin({ bottom: 10 })
                Button('重试').width(100).height(36).fontSize(14)
                  .onClick(() => { this.loadFeed(true); })
              }.width('100%').height('100%').justifyContent(FlexAlign.Center)
            } else {
              FeedList({
                feedData: this.feedData,
                onImageClick: (url: string): void => this.handleImageClick(url),
                hasMore: this.hasMoreFeed,
                onLoadMore: (): void => { this.loadFeed(false); },
                onLikeChange: (postId: string, isLiked: boolean, newCount: number): void => {
                  this.handleLikeChange(postId, isLiked, newCount);
                },
                onCommentAdd: (postId: string, comment: CommentItemType): void => {
                  this.handleCommentAdd(postId, comment);
                },
                onDelete: (postId: string): void => {
                  this.handleDelete(postId);
                },
                displayNickname: this.displayNickname,
                isLoggedIn: this.isLoggedIn,
                onGoToProfile: (): void => { this.currentTabIndex = 4; }
              })
            }
          }
          if (this.currentTabIndex === 1) {
            CategoryView({
              isLoggedIn: this.isLoggedIn,
              onGoToProfile: (): void => { this.currentTabIndex = 4; }
            })
          }
          if (this.currentTabIndex === 2) {
            PublishView({
              uiContext: this.uiContext,
              onPublish: (description: string, imageUrl: string): void => {
                this.handlePublish(description, imageUrl);
              },
              isLoggedIn: this.isLoggedIn,
              onGoToProfile: (): void => { this.currentTabIndex = 4; }
            })
          }
          if (this.currentTabIndex === 3) {
            AICameraView({ uiContext: this.uiContext })
          }
          if (this.currentTabIndex === 4) {
            ProfileView({
              myWorks: this.myWorks,
              onLoadMyWorks: () => { this.loadMyWorksFromApi(); },
              onDeletePost: (postId: string): void => { this.handleDelete(postId); },
              totalLikes: this.getTotalLikes(),
              displayNickname: this.displayNickname,
              displayAvatar: this.displayAvatar,
              onNicknameChange: (newName: string): void => {
                this.displayNickname = newName;
              },
              onAvatarChange: (newAvatar: string): void => {
                this.displayAvatar = newAvatar;
              },
              onLogout: (): void => { this.clearPersonalData(); },
              onLogin: (): void => { this.refreshLikedDataAfterLogin(); }
            })
          }
        }
        .layoutWeight(1)

        Row() {
          ForEach(this.tabItems, (item: TabItemType, index: number) => {
            Column() {
              Image(this.currentTabIndex === index ? item.selectedIcon : item.icon)
                .width(28).height(28).objectFit(ImageFit.Contain).margin({ bottom: 2 })
              Text(item.title)
                .fontSize(11)
                .fontColor(this.currentTabIndex === index ? '#FFD700' : '#AAAAAA')
                .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal)
            }
            .width('20%').height(this.tabBarHeight)
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.currentTabIndex = index;
              this.currentTitle = item.title;
            })
          })
        }
        .width('100%').height(this.tabBarHeight)
        .backgroundColor('#1A1A2E').padding({ top: 6, bottom: 6 })
      }
      .width('100%').height('100%').backgroundColor('#F5F5F5')

      if (this.showGlobalImagePreview) {
        Stack() {
          Column()
            .width('100%').height('100%')
            .backgroundColor('rgba(0, 0, 0, 0.9)')
            .onClick(() => { this.showGlobalImagePreview = false; })
          Image(this.previewImageUrl)
            .width('90%').height('70%')
            .objectFit(ImageFit.Contain).borderRadius(8)
          Text('✕')
            .fontSize(30).fontColor(Color.White)
            .position({ x: '90%', y: '5%' })
            .onClick(() => { this.showGlobalImagePreview = false; })
        }
        .width('100%').height('100%').position({ x: 0, y: 0 }).zIndex(999)
      }
    }
    .width('100%').height('100%')
  }

  handleCommentAdd(postId: string, comment: CommentItemType) {
    throw new Error('Method not implemented.');
  }
}

// ================== 首页 - FeedList ==================

@Component
struct FeedList {
  @Prop feedData: Array<FeedItemType> = [];
  onImageClick: (url: string) => void = () => {};
  @Prop hasMore: boolean = false;
  onLoadMore?: () => void;
  onLikeChange: (postId: string, isLiked: boolean, newCount: number) => void = () => {};
  onCommentAdd: (postId: string, comment: CommentItemType) => void = () => {};
  onDelete: (postId: string) => void = () => {};
  @Prop displayNickname: string = '';
  @Prop isLoggedIn: boolean = false;
  onGoToProfile?: () => void;

  build() {
    if (!this.isLoggedIn) {
      Column() {
        Text('🔒').fontSize(50).margin({ bottom: 12 })
        Text('请先登录或注册')
          .fontSize(18).fontColor('#333333').fontWeight(FontWeight.Medium)
        Text('登录后可查看首页动态')
          .fontSize(14).fontColor('#999999').margin({ top: 6 })
        Button('去登录')
          .width(140).height(42)
          .backgroundColor('#FFD700').fontColor('#1A1A2E')
          .borderRadius(21).fontSize(15).fontWeight(FontWeight.Medium)
          .margin({ top: 20 })
          .onClick(() => {
            if (this.onGoToProfile) this.onGoToProfile();
          })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('#F5F5F5')
    } else {
      List() {
        ForEach(this.feedData, (item: FeedItemType) => {
          ListItem() {
            FeedItem({
              feed: item,
              onImageClick: this.onImageClick,
              onLikeChange: this.onLikeChange,
              onCommentAdd: this.onCommentAdd,
              onDelete: this.onDelete,
              displayNickname: this.displayNickname
            })
          }
          .margin({ bottom: 10 })
        })
        if (this.hasMore) {
          ListItem() {
            Row() {
              LoadingProgress().width(24).height(24).margin({ right: 8 })
              Text('加载更多...').fontSize(14).fontColor('#999999')
            }
            .width('100%').height(50).justifyContent(FlexAlign.Center)
            .onAppear(() => { if (this.onLoadMore) this.onLoadMore(); })
          }
        }
      }
      .width('100%').height('100%')
      .padding({ left: 12, right: 12, top: 10 })
      .backgroundColor('#F5F5F5')
    }
  }
}

// ================== 单条 FeedItem ==================

@Component
struct FeedItem {
  @Prop feed: FeedItemType = {
    id: 0, postId: '', type: 'image', url: '', username: '', userId: '',
    avatar: '', description: '', createTime: 0, likes: 0, comments: 0,
    isLiked: false, commentsList: [], categoryId: '', categoryName: ''
  };
  onImageClick: (url: string) => void = () => {};
  onLikeChange: (postId: string, isLiked: boolean, newCount: number) => void = () => {};
  onCommentAdd: (postId: string, comment: CommentItemType) => void = () => {};
  onDelete: (postId: string) => void = () => {};
  @State isLiked: boolean = false;
  @State likeCount: number = 0;
  @State showCommentInput: boolean = false;
  @State commentText: string = '';
  @State commentsList: CommentItemType[] = [];
  @State isSending: boolean = false;
  @Prop displayNickname: string = '';

  aboutToAppear(): void {
    this.isLiked = this.feed.isLiked;
    this.likeCount = this.feed.likes;

    const sourceList: CommentItemType[] = this.feed.commentsList;
    const filtered: CommentItemType[] = [];
    for (let i = 0; i < sourceList.length; i++) {
      if (sourceList[i].content.length > 0) {
        filtered.push(sourceList[i]);
      }
    }
    this.commentsList = filtered;
  }

  private getTimeDisplay(timestamp: number): string {
    if (timestamp <= 0) return '刚刚';
    const now = Date.now();
    const diffMs = now - timestamp;
    const diffMin = Math.floor(diffMs / 60000);
    const diffHour = Math.floor(diffMin / 60);
    const diffDay = Math.floor(diffHour / 24);
    if (diffMin < 1) return '刚刚';
    if (diffMin < 60) return diffMin + '分钟前';
    if (diffHour < 24) return diffHour + '小时前';
    if (diffDay < 7) return diffDay + '天前';
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return year + '-' + month + '-' + day + ' ' + hours + ':' + minutes;
  }

  // 统一辅助方法
  private isMyPost(): boolean {
    const currentUserId: string = AppStorage.get<string>('login_username') || '';
    if (currentUserId.length > 0 && this.feed.userId === currentUserId) {
      return true;
    }
    if (this.displayNickname.length > 0 && this.feed.username === this.displayNickname) {
      return true;
    }
    return false;
  }

  private isCurrentUserPost(): boolean {
    return this.isMyPost();
  }

  private isOwnPost(): boolean {
    return this.isMyPost();
  }

  async handleLikeClick(): Promise<void> {
    try {
      if (this.feed.postId.length === 0) {
        const newIsLiked: boolean = !this.isLiked;
        const newCount: number = newIsLiked ? this.likeCount + 1 : this.likeCount - 1;
        this.isLiked = newIsLiked;
        this.likeCount = newCount;
        this.onLikeChange(this.feed.postId, newIsLiked, newCount);
        return;
      }
      const result = this.isLiked
        ? await postApi.unlike(this.feed.postId)
        : await postApi.like(this.feed.postId);
      if (result.success && result.data !== null) {
        const newIsLiked: boolean = !this.isLiked;
        this.isLiked = newIsLiked;
        this.likeCount = result.data;
        this.onLikeChange(this.feed.postId, newIsLiked, result.data);
        if (distributedApi.isReady()) {
          distributedApi.sync(false);
        }
      }
    } catch (err) {
      console.warn('[FeedItem] 点赞失败:', (err as Error).message);
    }
  }

  async handleSendComment(): Promise<void> {
    const trimmed: string = this.commentText.trim();
    if (trimmed.length === 0) return;
    this.isSending = true;

    try {
      if (this.feed.postId.length === 0) {
        const displayName = this.displayNickname.length > 0 ? this.displayNickname : '我';
        const newComment: CommentItemType = { username: displayName, content: trimmed };
        this.isSending = false;
        this.onCommentAdd(this.feed.postId, newComment);
        return;
      }

      const loginUsername: string = AppStorage.get<string>('login_username') || 'local_user';
      const deviceId: string = AppStorage.get<string>('device_id') || 'local_device';
      const displayName = this.displayNickname.length > 0 ? this.displayNickname : '匿名用户';
      const result = await commentApi.publish(
        this.feed.postId, loginUsername, displayName, '', trimmed, deviceId
      );
      if (result.success) {
        const newList: CommentItemType[] = [];
        for (let i = 0; i < this.commentsList.length; i++) {
          newList.push(this.commentsList[i]);
        }
        const newComment: CommentItemType = { username: displayName, content: trimmed };
        newList.push(newComment);
        this.commentsList = newList;
        this.commentText = '';
        this.onCommentAdd(this.feed.postId, newComment);
        if (distributedApi.isReady()) {
          distributedApi.sync(false);
        }
      }
    } catch (err) {
      console.warn('[FeedItem] 评论失败:', (err as Error).message);
    }
    this.isSending = false;
  }

  private getImageSrc(): string | Resource {
    if (this.feed.url.length > 0) return this.feed.url;
    return $r('app.media.nai');
  }

  private getAvatarSrc(): string | Resource {
    if (this.feed.avatar.length > 0) return this.feed.avatar;
    return $r('app.media.nai');
  }

  build() {
    Column() {
      Row() {
        Image(this.getAvatarSrc())
          .width(44).height(44).borderRadius(22).margin({ right: 12 })
        Column() {
          Row() {
            Text(this.feed.username)
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
            if (this.isCurrentUserPost()) {
              Text('我')
                .fontSize(10).fontColor('#FFFFFF')
                .backgroundColor('#FFD700')
                .borderRadius(8).padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .margin({ left: 6 })
            }
          }
          Text(this.getTimeDisplay(this.feed.createTime))
            .fontSize(12).fontColor('#999999').margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.isOwnPost()) {
          Text('✕')
            .fontSize(18).fontColor('rgba(0,0,0,0.3)')
            .width(28).height(28).textAlign(TextAlign.Center)
            .borderRadius(14)
            .onClick(() => {
              promptAction.showDialog({
                title: '删除帖子',
                message: '确定要删除这条帖子吗？',
                buttons: [
                  { text: '取消', color: '#999999' },
                  { text: '删除', color: '#FF0000' }
                ]
              }).then((data: promptAction.ShowDialogSuccessResponse) => {
                if (data.index === 1) {
                  this.onDelete(this.feed.postId);
                }
              });
            })
        }
      }
      .width('100%').padding({ left: 12, right: 8, top: 12 })

      Text(this.feed.description)
        .fontSize(15).fontColor('#444444')
        .padding({ left: 12, right: 12, top: 8 }).width('100%')

      Stack() {
        Image(this.getImageSrc())
          .width('100%').height(200).objectFit(ImageFit.Cover)
          .borderRadius(8).margin({ top: 8 }).backgroundColor('#E0E0E0')
          .onClick(() => { this.onImageClick(this.feed.url); })
      }

      Row() {
        Row() {
          Image(this.isLiked ? $r('app.media.good_selected') : $r('app.media.good'))
            .width(20).height(20).fillColor('#FF6B6B')
          Text(this.likeCount.toString())
            .fontSize(13).fontColor(this.isLiked ? '#FF0000' : '#666666').margin({ left: 4 })
        }
        .margin({ right: 16 })
        .onClick(() => { this.handleLikeClick(); })

        Row() {
          Image($r('app.media.comment'))
            .width(20).height(20).fillColor('#666666')
          Text(this.commentsList.length.toString())
            .fontSize(13).fontColor('#666666').margin({ left: 4 })
        }
        .onClick(() => {
          this.showCommentInput = !this.showCommentInput;
          if (!this.showCommentInput) this.commentText = '';
        })

        Blank()
      }
      .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 12 })
      .backgroundColor(Color.White)

      if (this.showCommentInput) {
        Column() {
          if (this.commentsList.length > 0) {
            Column() {
              Text('评论列表 (' + this.commentsList.length + ')')
                .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#333333')
                .width('100%').margin({ top: 8, bottom: 8 })
              ForEach(this.commentsList, (comment: CommentItemType, index: number) => {
                Row() {
                  Row() {
                    Text(comment.username)
                      .fontSize(13).fontColor('#FF9800').fontWeight(FontWeight.Medium)
                    if (this.displayNickname.length > 0 && comment.username === this.displayNickname) {
                      Text('我')
                        .fontSize(10).fontColor('#FFFFFF')
                        .backgroundColor('#FFD700')
                        .borderRadius(8).padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .margin({ left: 4 })
                    }
                    Text(': ')
                      .fontSize(13).fontColor('#FF9800').fontWeight(FontWeight.Medium)
                  }
                  .margin({ right: 6 })

                  Text(comment.content)
                    .fontSize(14).fontColor('#333333')
                }
                .width('100%').padding({ top: 4, bottom: 4 })
                .alignItems(VerticalAlign.Center)
              })
            }
            .width('100%').padding({ bottom: 12 })
          } else {
            Text('暂无评论，来说点什么吧...')
              .fontSize(14).fontColor('#999999').width('100%')
              .padding({ bottom: 12 }).textAlign(TextAlign.Center)
          }

          Row() {
            TextInput({ placeholder: '说点什么...', text: this.commentText })
              .width('75%').height(40).backgroundColor('#F5F5F5').borderRadius(20)
              .padding({ left: 16, right: 16 }).fontSize(14).placeholderColor('#AAAAAA')
              .onChange((value: string) => { this.commentText = value; })

            Button(this.isSending ? '发送中' : '发送')
              .width('20%').height(40)
              .backgroundColor(this.isSending ? '#CCCCCC' : '#FFD700')
              .fontColor('#1A1A2E').borderRadius(20).fontSize(14).fontWeight(FontWeight.Medium)
              .enabled(!this.isSending)
              .onClick(() => { this.handleSendComment(); })
          }
          .width('100%').justifyContent(FlexAlign.SpaceBetween)
          .padding({ top: 8, bottom: 8 })
        }
        .width('100%').padding({ left: 12, right: 12, bottom: 12 })
        .backgroundColor('#FAFAFA')
        .borderRadius({ bottomLeft: 12, bottomRight: 12 })
      }
    }
    .width('100%').backgroundColor(Color.White).borderRadius(12)
    .shadow({ radius: 4, color: 'rgba(0, 0, 0, 0.05)', offsetX: 0, offsetY: 2 })
  }
}

// ================== AI识图Tab ==================

@Component
struct AICameraView {
  @State recognizeResult: string = '';
  @State recognizeDetail: string = '';
  @State isRecognizing: boolean = false;
  @StorageLink('ai_recognize_records') recognizeRecords: RecognizeRecord[] = [];
  @Prop uiContext?: common.Context;

  async recognizeFromAlbum(): Promise<void> {
    this.isRecognizing = true;
    this.recognizeResult = '正在打开相册...';
    this.recognizeDetail = '';
    try {
      if (this.uiContext === undefined) {
        this.recognizeResult = '无法获取上下文';
        this.isRecognizing = false;
        return;
      }
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.uiContext);
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await picker.select(options);
      const uris: string[] = result.photoUris;
      if (uris.length > 0) {
        await this.runClassify(uris[0]);
      } else {
        this.isRecognizing = false;
        this.recognizeResult = '';
        this.recognizeDetail = '';
      }
    } catch (err) {
      this.isRecognizing = false;
      this.recognizeResult = '打开相册失败';
      this.recognizeDetail = (err as Error).message;
      console.error('[AICameraView] 选择图片失败:', (err as Error).message);
    }
  }

  async recognizeFromCamera(): Promise<void> {
    this.isRecognizing = true;
    this.recognizeResult = '正在打开相机...';
    this.recognizeDetail = '';
    try {
      let abilityContext: common.Context | undefined =
        AppStorage.get<common.Context>('globalAbilityContext');
      if (abilityContext === undefined) {
        if (this.uiContext === undefined) {
          this.isRecognizing = false;
          this.recognizeResult = '相机启动失败';
          this.recognizeDetail = '无法获取应用上下文，请重新进入页面';
          return;
        }
        abilityContext = this.uiContext as common.Context;
      }
      const pickerProfile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const pickerResult: cameraPicker.PickerResult = await cameraPicker.pick(
        abilityContext,
        [cameraPicker.PickerMediaType.PHOTO],
        pickerProfile
      );
      if (pickerResult.resultCode === 0 && pickerResult.resultUri) {
        await this.runClassify(pickerResult.resultUri);
      } else {
        this.isRecognizing = false;
        this.recognizeResult = '';
        this.recognizeDetail = '';
      }
    } catch (err) {
      this.isRecognizing = false;
      this.recognizeResult = '';
      this.recognizeDetail = '';
      console.warn('[AICameraView] 相机调用失败:', (err as Error).message);
    }
  }

  async runClassify(imageUri: string): Promise<void> {
    this.recognizeResult = 'AI 识别中...';
    this.recognizeDetail = '';
    try {
      const result = await aiClassifyApi.classifyUri(imageUri);
      if (result.success && result.data !== null) {
        this.recognizeResult = result.data.categoryName + ' (' + result.data.confidence + '%)';
        this.recognizeDetail = result.data.success ? 'AI 推理成功' : 'AI 推理失败';
      } else {
        this.recognizeResult = '识别失败';
        this.recognizeDetail = result.message;
      }
    } catch (err) {
      this.recognizeResult = '识别异常';
      this.recognizeDetail = (err as Error).message;
    }
    this.isRecognizing = false;

    if (this.recognizeResult.length > 0 &&
      this.recognizeResult !== '识别异常' &&
      this.recognizeResult !== '识别失败' &&
      this.recognizeResult !== '等待识别图片') {
      const newRecord: RecognizeRecord = {
        result: this.recognizeResult,
        detail: this.recognizeDetail,
        timestamp: new Date().getTime()
      };
      const updated: RecognizeRecord[] = [newRecord, ...this.recognizeRecords].slice(0, 20);
      this.recognizeRecords = updated;
    }
  }

  clearRecords(): void {
    this.recognizeRecords = [];
    promptAction.showToast({ message: '最近识别已清空', duration: 1500 });
  }

  build() {
    Column() {
      Column() {
        Column() {
          Text('🔍').fontSize(50).margin({ bottom: 10 })
          if (this.recognizeResult.length > 0) {
            Text(this.recognizeResult)
              .fontSize(18).fontColor('#FF9800').fontWeight(FontWeight.Bold)
            Text(this.recognizeDetail)
              .fontSize(13).fontColor('#666666').margin({ top: 6 })
          } else {
            Text('等待识别图片')
              .fontSize(16).fontColor('#555555').fontWeight(FontWeight.Medium)
            Text('支持植物、动物、商品等')
              .fontSize(13).fontColor('#999999').margin({ top: 6 })
          }
          if (this.isRecognizing) {
            LoadingProgress().width(40).height(40).margin({ top: 12 })
          }
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      }
      .width('88%').height(280)
      .backgroundColor('#EAEAEA')
      .borderRadius(16)
      .margin({ top: 20, bottom: 10 })

      Row() {
        Button('相册选择')
          .width(120).height(44).backgroundColor('#FFD700')
          .fontColor('#1A1A2E').borderRadius(22).fontSize(15).fontWeight(FontWeight.Medium)
          .enabled(!this.isRecognizing)
          .onClick(() => { this.recognizeFromAlbum(); })

        Button('拍照识别')
          .width(120).height(44).backgroundColor('#1A1A2E')
          .fontColor(Color.White).borderRadius(22).fontSize(15).fontWeight(FontWeight.Medium)
          .margin({ left: 20 }).enabled(!this.isRecognizing)
          .onClick(() => { this.recognizeFromCamera(); })
      }
      .width('100%').justifyContent(FlexAlign.Center)
      .margin({ top: 20 })

      Column() {
        Row() {
          Text('最近识别')
            .fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor('#333333')
          Blank()
          if (this.recognizeRecords.length > 0) {
            Button('清空')
              .width(60).height(28)
              .backgroundColor('#F5F5F5')
              .fontColor('#999999')
              .fontSize(12).borderRadius(14)
              .onClick(() => { this.clearRecords(); })
          }
        }
        .width('90%').margin({ top: 20, bottom: 10 })

        if (this.recognizeRecords.length > 0) {
          ForEach(this.recognizeRecords, (record: RecognizeRecord, index: number) => {
            Row() {
              Text(this.formatTime(record.timestamp))
                .fontSize(12).fontColor('#BBBBBB')
                .margin({ right: 8 })
              Text(record.result)
                .fontSize(14).fontColor('#FF9800').fontWeight(FontWeight.Medium)
                .layoutWeight(1)
            }
            .width('90%').padding({ top: 6, bottom: 6 })
            .borderRadius(8).backgroundColor('#FAFAFA').padding({ left: 10, right: 10 })
          })
        } else {
          Text('点击上方「相册选择」或「拍照识别」按钮，选择一张图片进行 AI 识别')
            .fontSize(13).fontColor('#999999').width('90%').textAlign(TextAlign.Center)
        }
      }
      .width('100%').alignItems(HorizontalAlign.Center)

      Blank()
    }
    .width('100%').height('100%').backgroundColor('#F8F8FC')
  }

  private formatTime(timestamp: number): string {
    const now = new Date();
    const date = new Date(timestamp);
    const diffMs = now.getTime() - date.getTime();
    const diffMin = Math.floor(diffMs / 60000);
    if (diffMin < 1) return '刚刚';
    if (diffMin < 60) return diffMin + '分钟前';
    const diffHour = Math.floor(diffMin / 60);
    if (diffHour < 24) return diffHour + '小时前';
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return month + '-' + day;
  }
}

// ================== 发布Tab ==================

@Component
struct PublishView {
  @State description: string = '';
  @State selectedImage: string = '';
  @State hasSelectedImage: boolean = false;
  @State isPressed1: boolean = false;
  @State isPressed2: boolean = false;
  @State isPublishing: boolean = false;
  @Prop uiContext?: common.Context;
  onPublish: (description: string, imageUrl: string) => void = () => {};
  @Prop isLoggedIn: boolean = false;
  onGoToProfile?: () => void;

  async selectImage(): Promise<void> {
    try {
      if (this.uiContext === undefined) {
        promptAction.showToast({ message: '无法获取上下文', duration: 2000 });
        return;
      }
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.uiContext);
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await picker.select(options);
      const uris: string[] = result.photoUris;
      if (uris.length > 0) {
        this.selectedImage = uris[0];
        this.hasSelectedImage = true;
      }
    } catch (err) {
      promptAction.showToast({ message: '选择图片失败: ' + (err as Error).message, duration: 2000 });
    }
  }

  build() {
    if (!this.isLoggedIn) {
      Column() {
        Text('✏️').fontSize(50).margin({ bottom: 12 })
        Text('请先登录或注册')
          .fontSize(18).fontColor('#333333').fontWeight(FontWeight.Medium)
        Text('登录后即可发布动态')
          .fontSize(14).fontColor('#999999').margin({ top: 6 })
        Button('去登录')
          .width(140).height(42)
          .backgroundColor('#FFD700').fontColor('#1A1A2E')
          .borderRadius(21).fontSize(15).fontWeight(FontWeight.Medium)
          .margin({ top: 20 })
          .onClick(() => {
            if (this.onGoToProfile) this.onGoToProfile();
          })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('#F8F8FC')
    } else {
      Column() {
        Column() {
          Column() {
            TextArea({ placeholder: '分享你的想法...', text: this.description })
              .width('100%').height(120).backgroundColor('#F5F5F5').borderRadius(12)
              .padding(12).fontSize(16).placeholderColor('#AAAAAA')
              .onChange((value: string) => { this.description = value; })
          }
          .width('90%').margin({ top: 20 })

          Row() {
            Stack() {
              if (this.hasSelectedImage) {
                Image(this.selectedImage)
                  .width(80).height(80).borderRadius(8).objectFit(ImageFit.Cover)
              } else {
                Column() {
                  Text('+').fontSize(30).fontColor('#FFFFFF').fontWeight(FontWeight.Bold)
                  Text('添加图片').fontSize(12).fontColor('#FFFFFF').margin({ top: 4 })
                }
                .width(80).height(80).backgroundColor('#D0D0D0').borderRadius(8)
                .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
              }
            }
            .margin({ right: 10 })
            .onClick(() => { this.selectImage(); })
          }
          .width('90%').justifyContent(FlexAlign.Start).margin({ top: 16 })

          Row() {
            Stack() {
              Circle()
                .width(22).height(22)
                .fill(this.isPressed1 ? '#FFD700' : '#E0E0E0')
                .stroke(this.isPressed1 ? '#FFD700' : '#CCCCCC')
                .strokeWidth(1.5)
              if (this.isPressed1) {
                Text('✓')
                  .fontSize(14).fontColor(Color.White).fontWeight(FontWeight.Bold)
              }
            }
            .width(22).height(22)
            .onClick(() => { this.isPressed1 = !this.isPressed1; })
            .margin({ right: 8 })

            Text('添加位置').fontSize(15).fontColor('#666666')

            Blank()

            Stack() {
              Circle()
                .width(22).height(22)
                .fill(this.isPressed2 ? '#FFD700' : '#E0E0E0')
                .stroke(this.isPressed2 ? '#FFD700' : '#CCCCCC')
                .strokeWidth(1.5)
              if (this.isPressed2) {
                Text('✓')
                  .fontSize(14).fontColor(Color.White).fontWeight(FontWeight.Bold)
              }
            }
            .width(22).height(22)
            .onClick(() => { this.isPressed2 = !this.isPressed2; })
            .margin({ right: 8 })

            Text('公开').fontSize(15).fontColor('#666666')
          }
          .width('90%').padding({ top: 16, bottom: 16 })
          .borderWidth({ bottom: 1 }).borderColor('#EEEEEE')

          Button(this.isPublishing ? '发布中...' : '发布')
            .width('90%').height(50)
            .backgroundColor(this.isPublishing ? '#CCCCCC' : '#FFD700')
            .fontColor('#1A1A2E').fontSize(18).fontWeight(FontWeight.Bold)
            .borderRadius(25).margin({ top: 24 })
            .enabled(!this.isPublishing)
            .onClick(() => {
              if (this.description.trim().length === 0) {
                promptAction.showToast({ message: '请输入内容', duration: 2000 });
                return;
              }
              this.isPublishing = true;
              this.onPublish(this.description, this.selectedImage);
              this.description = '';
              this.hasSelectedImage = false;
              this.selectedImage = '';
              this.isPublishing = false;
            })
        }
        .width('100%').backgroundColor(Color.White)
        .borderRadius({ topLeft: 20, topRight: 20 })
        .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.06)', offsetY: -4 })
        .padding({ bottom: 20 })

        Blank()
      }
      .width('100%').height('100%').backgroundColor('#F8F8FC')
    }
  }
}

// ================== 分类Tab ==================

interface CategoryItemType {
  name: string;
  icon: string;
  categoryId: string;
}

interface PhotoItemType {
  id: number;
  image: string;
  postId: string;
}

interface HotTagType {
  tag: string;
  category: string;
  categoryId: string;
}

@Component
struct CategoryView {
  @State selectedCategory: string = '';
  @State showPhotos: boolean = false;
  @State currentPhotos: Array<PhotoItemType> = [];
  @State isLoadingCategory: boolean = false;
  @State categoryError: string = '';
  @Prop isLoggedIn: boolean = false;
  onGoToProfile?: () => void;

  private categories: Array<CategoryItemType> = [
    { name: '风景', icon: '🌲', categoryId: 'cat_scenery' },
    { name: '人物', icon: '👤', categoryId: 'cat_person' },
    { name: '美食', icon: '🍽', categoryId: 'cat_food' },
    { name: '动物', icon: '🐾', categoryId: 'cat_animal' },
    { name: '建筑', icon: '🏛', categoryId: 'cat_building' },
    { name: '其他', icon: '📁', categoryId: 'cat_other' },
  ];

  private hotTags: HotTagType[] = [
    { tag: '#城市记忆', category: '人物', categoryId: 'cat_person' },
    { tag: '#美食探店', category: '美食', categoryId: 'cat_food' },
    { tag: '#旅行日记', category: '风景', categoryId: 'cat_scenery' },
    { tag: '#摄影日常', category: '风景', categoryId: 'cat_scenery' },
    { tag: '#宠物生活', category: '动物', categoryId: 'cat_animal' },
    { tag: '#时尚穿搭', category: '人物', categoryId: 'cat_person' },
  ];

  async handleCategoryClick(name: string, categoryId: string): Promise<void> {
    this.selectedCategory = name;
    this.showPhotos = true;
    this.isLoadingCategory = true;
    this.categoryError = '';
    try {
      const result = await postApi.getByCategory(categoryId, 1, 30);
      if (result.success && result.data !== null) {
        const photos: PhotoItemType[] = [];
        for (let i = 0; i < result.data.length; i++) {
          const images: string[] = result.data[i].getImagePathArray();
          if (images.length > 0) {
            const photo: PhotoItemType = { id: i + 1, image: images[0], postId: result.data[i].postId };
            photos.push(photo);
          }
        }
        this.currentPhotos = photos;
      } else {
        this.categoryError = result.message;
      }
    } catch (err) {
      this.categoryError = '加载失败: ' + (err as Error).message;
    }
    this.isLoadingCategory = false;
  }

  handleTagClick(tag: HotTagType): void {
    this.handleCategoryClick(tag.category, tag.categoryId);
  }

  build() {
    if (!this.isLoggedIn) {
      Column() {
        Text('📂').fontSize(50).margin({ bottom: 12 })
        Text('请先登录或注册')
          .fontSize(18).fontColor('#333333').fontWeight(FontWeight.Medium)
        Text('登录后可查看分类浏览')
          .fontSize(14).fontColor('#999999').margin({ top: 6 })
        Button('去登录')
          .width(140).height(42)
          .backgroundColor('#FFD700').fontColor('#1A1A2E')
          .borderRadius(21).fontSize(15).fontWeight(FontWeight.Medium)
          .margin({ top: 20 })
          .onClick(() => {
            if (this.onGoToProfile) this.onGoToProfile();
          })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('#F8F8FC')
    } else {
      Column() {
        if (!this.showPhotos) {
          Grid() {
            ForEach(this.categories, (cat: CategoryItemType) => {
              GridItem() {
                Column() {
                  Text(cat.icon).fontSize(32).margin({ bottom: 8 })
                  Text(cat.name).fontSize(14).fontColor('#333333')
                }
                .width('100%').height(100)
                .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
                .onClick(() => { this.handleCategoryClick(cat.name, cat.categoryId); })
              }
            })
          }
          .columnsTemplate('1fr 1fr 1fr').rowsGap(12).columnsGap(12)
          .width('90%').height(220).padding(8)

          Column() {
            Text('热门标签')
              .fontSize(20).fontWeight(FontWeight.Medium)
              .fontColor('#1A1A2E').width('100%')
              .margin({ top: 20, bottom: 12 })
            Row() {
              ForEach(this.hotTags, (tagItem: HotTagType) => {
                Text(tagItem.tag)
                  .fontSize(13).fontColor('#666666')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor('#F0F0F0').borderRadius(16)
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => { this.handleTagClick(tagItem); })
              })
            }
            .width('100%')
          }
          .width('100%').alignItems(HorizontalAlign.Start)
          Blank()
        } else {
          Column() {
            Row() {
              Text('← 返回')
                .fontSize(15).fontColor('#FFD700')
                .onClick(() => { this.showPhotos = false; this.selectedCategory = ''; })
                .margin({ right: 12 })
              Text(this.selectedCategory)
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1A1A2E')
                .layoutWeight(1)
              if (this.isLoadingCategory) {
                LoadingProgress().width(20).height(20)
              }
            }
            .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .backgroundColor(Color.White)

            if (this.categoryError.length > 0) {
              Text(this.categoryError)
                .fontSize(13).fontColor('#FF0000').margin({ top: 20 })
            }

            Grid() {
              ForEach(this.currentPhotos, (photo: PhotoItemType) => {
                GridItem() {
                  Column() {
                    Image(photo.image)
                      .width('100%').aspectRatio(1).objectFit(ImageFit.Cover)
                      .borderRadius(8).backgroundColor('#E8E8E8')
                  }
                  .width('100%')
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr').rowsGap(12).columnsGap(12)
            .width('95%').padding({ top: 12, bottom: 12 }).layoutWeight(1)
          }
          .width('100%').height('100%').backgroundColor('#F8F8FC')
        }
      }
      .width('100%').height('100%').backgroundColor('#F8F8FC')
      .alignItems(HorizontalAlign.Center)
    }
  }
}

// ================== 我 Tab ==================

@Component
struct ProfileView {
  @Prop myWorks: Array<FeedItemType> = [];
  onLoadMyWorks: () => void = () => {};
  onDeletePost: (postId: string) => void = () => {};
  @Prop totalLikes: number = 0;
  @Prop displayNickname: string = '';
  @Prop displayAvatar: string = '';
  onNicknameChange: (newName: string) => void = () => {};
  onAvatarChange: (newAvatar: string) => void = () => {};
  onLogout?: () => void;
  onLogin?: () => void;

  @StorageLink('display_bio') displayBio: string = '这个人很懒，什么都没有写...';
  @StorageLink('is_logged_in') isLoggedIn: boolean = false;
  @State editBio: string = '';
  @State showEditBio: boolean = false;

  @State showLoginDialog: boolean = false;
  @State isRegisterMode: boolean = false;
  @State loginUsername: string = '';
  @State loginPassword: string = '';
  @State registerConfirmPassword: string = '';
  @State isLoggingIn: boolean = false;
  @State isRegistering: boolean = false;
  @State syncStatusText: string = '';

  @State showAllWorks: boolean = false;
  @State showPostDetail: boolean = false;
  @State detailPost: FeedItemType | null = null;

  @State showEditProfile: boolean = false;
  @State editNickname: string = '';

  @State showPostComments: boolean = false;
  @State postCommentText: string = '';
  @State isSendingPostComment: boolean = false;

  async aboutToAppear(): Promise<void> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      AppStorage.setOrCreate<object>('uiAbilityContext', context);
      await distributedApi.init(context);
    } catch (err) {
      console.warn('[ProfileView] 云同步初始化失败:', (err as Error).message);
    }
    this.onLoadMyWorks();
  }

  // ProfileView 中 — 替换 handleLogin
  async handleLogin(): Promise<void> {
    if (this.loginUsername.trim().length === 0 || this.loginPassword.trim().length === 0) {
      promptAction.showToast({ message: '请输入账号和密码', duration: 2000 });
      return;
    }
    this.isLoggingIn = true;
    try {
      const result = await distributedApi.login(
        this.loginUsername.trim(),
        this.loginPassword.trim()
      );

      if (result.success && result.data) {
        // ★ 登录成功 - distributedApi.login() 已经设置了 display_nickname/avatar/bio
        await SessionManager.saveCredentials(
          this.loginUsername.trim(),
          this.loginPassword.trim()
        );

        // ★ 从 AppStorage 读取分布式 API 已经设置好的值
        const nickname: string = AppStorage.get<string>('display_nickname') || '用户';
        const avatarUrl: string = AppStorage.get<string>('display_avatar') || '';
        const bioText: string = AppStorage.get<string>('display_bio') || '这个人很懒，什么都没有写...';

        // ★ 更新本地 props
        this.onNicknameChange(nickname);
        this.onAvatarChange(avatarUrl);

        const username = this.loginUsername.trim();
        AppStorage.set<string>('login_username', username);
        LikedCache.setCurrentUser(username);

        this.isLoggedIn = true;
        this.showLoginDialog = false;
        promptAction.showToast({ message: '登录成功', duration: 2000 });

        distributedApi.sync(true).catch(() => {});
        this.onLoadMyWorks();

        if (this.onLogin) {
          this.onLogin();
        }
      } else {
        promptAction.showToast({ message: '登录失败: ' + result.message, duration: 2000 });
      }
    } catch (err) {
      promptAction.showToast({ message: '登录异常: ' + (err as Error).message, duration: 2000 });
    }
    this.isLoggingIn = false;
  }

  // ProfileView 中 — 替换 handleRegister
  async handleRegister(): Promise<void> {
    const username: string = this.loginUsername.trim();
    const password: string = this.loginPassword.trim();
    const confirmPassword: string = this.registerConfirmPassword.trim();

    if (username.length === 0 || password.length === 0 || confirmPassword.length === 0) {
      promptAction.showToast({ message: '请输入账号、密码和确认密码', duration: 2000 });
      return;
    }
    if (password.length < 6) {
      promptAction.showToast({ message: '密码至少需要 6 位', duration: 2000 });
      return;
    }
    if (password !== confirmPassword) {
      promptAction.showToast({ message: '两次输入的密码不一致', duration: 2000 });
      return;
    }

    this.isRegistering = true;
    try {
      const result = await distributedApi.register(username, password);

      if (result.success && result.data) {
        await SessionManager.saveCredentials(username, password);

        // ★ distributedApi.register() 已经设置了 display_nickname/avatar/bio
        const newNickname: string = AppStorage.get<string>('display_nickname') || '用户';
        const newAvatar: string = AppStorage.get<string>('display_avatar') || '';

        AppStorage.set<string>('login_username', username);
        LikedCache.setCurrentUser(username);

        this.onNicknameChange(newNickname);
        this.onAvatarChange(newAvatar);

        this.isLoggedIn = true;
        this.closeAuthDialog();
        promptAction.showToast({ message: '注册成功！昵称: ' + newNickname, duration: 3000 });

        distributedApi.sync(true).catch(() => {});
        this.onLoadMyWorks();

        if (this.onLogin) {
          this.onLogin();
        }
      } else {
        promptAction.showToast({ message: '注册失败: ' + result.message, duration: 2000 });
      }
    } catch (err) {
      promptAction.showToast({ message: '注册异常: ' + (err as Error).message, duration: 2000 });
    }
    this.isRegistering = false;
  }

  async handleSync(): Promise<void> {
    if (!this.isLoggedIn) {
      promptAction.showToast({ message: '请先登录云端', duration: 2000 });
      return;
    }
    try {
      // ★ 调用 sync(true) 触发全量同步
      const result = await distributedApi.sync(true);
      if (result.success) {
        promptAction.showToast({ message: '同步成功，共 ' + result.syncCount + ' 条', duration: 2000 });
      } else {
        promptAction.showToast({ message: '同步失败: ' + result.errorMsg, duration: 2000 });
      }
    } catch (err) {
      promptAction.showToast({ message: '同步异常: ' + (err as Error).message, duration: 2000 });
    }
  }

  async handleLogout(): Promise<void> {
    try {
      await distributedApi.logout();
      await SessionManager.clearCredentials();
      // 保留点赞数据在 Preferences
    } catch (_) {}

    AppStorage.set<string>('display_nickname', '');
    AppStorage.set<string>('display_avatar', '');
    AppStorage.set<string>('display_bio', '这个人很懒，什么都没有写...');
    AppStorage.set<string>('login_username', '');
    AppStorage.set<string>('device_id', '');

    this.isLoggedIn = false;

    if (this.onLogout) {
      this.onLogout();
    }

    promptAction.showToast({ message: '已退出登录', duration: 2000 });
  }

  private async saveNickname(): Promise<void> {
    const trimmed = this.editNickname.trim();
    if (trimmed.length === 0) {
      promptAction.showToast({ message: '昵称不能为空', duration: 1500 });
      return;
    }
    if (trimmed.length > 20) {
      promptAction.showToast({ message: '昵称不能超过20个字符', duration: 1500 });
      return;
    }

    if (!this.isLoggedIn) {
      promptAction.showToast({ message: '请先登录云端', duration: 1500 });
      return;
    }
    try {
      const currentAvatar = AppStorage.get<string>('display_avatar') || '';
      const currentBio = AppStorage.get<string>('display_bio') || '';

      const result = await distributedApi.updateProfile({
        displayNickname: trimmed,
        avatar: currentAvatar,
        bio: currentBio
      });
      AppStorage.setOrCreate('display_nickname', result.displayNickname!);
      this.onNicknameChange(result.displayNickname!);
      this.showEditProfile = false;
      promptAction.showToast({ message: '昵称已更新', duration: 1500 });
    } catch (err) {
      promptAction.showToast({ message: '同步服务器失败: ' + (err as Error).message, duration: 2000 });
    }
  }

  private async selectAvatar(): Promise<void> {
    if (!this.isLoggedIn) {
      promptAction.showToast({ message: '请先登录云端', duration: 1500 });
      return;
    }
    try {
      const context = AppStorage.get<common.Context>('globalAbilityContext');
      if (!context) {
        promptAction.showToast({ message: '无法获取上下文', duration: 1500 });
        return;
      }
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await picker.select(options);
      if (result.photoUris.length > 0) {
        const uri = result.photoUris[0];

        const remoteUrls = await distributedApi.uploadImages([uri]);
        const remoteUrl = remoteUrls.length > 0 ? remoteUrls[0] : uri;

        const currentNickname = AppStorage.get<string>('display_nickname') || '';
        const currentBio = AppStorage.get<string>('display_bio') || '';

        const profileResult = await distributedApi.updateProfile({
          displayNickname: currentNickname,
          avatar: remoteUrl,
          bio: currentBio
        });

        AppStorage.setOrCreate('display_avatar', profileResult.avatar!);
        this.onAvatarChange(profileResult.avatar!);
        promptAction.showToast({ message: '头像已更新', duration: 1500 });
      }
    } catch (err) {
      console.warn('[ProfileView] 选择头像失败:', (err as Error).message);
      promptAction.showToast({ message: '头像更新失败: ' + (err as Error).message, duration: 2000 });
    }
  }

  private async handlePostComment(): Promise<void> {
    const trimmed = this.postCommentText.trim();
    if (trimmed.length === 0 || this.detailPost === null) return;
    this.isSendingPostComment = true;
    try {
      const loginUsername: string = AppStorage.get<string>('login_username') || 'local_user';
      const deviceId: string = AppStorage.get<string>('device_id') || 'local_device';
      const commentResult = await commentApi.publish(
        this.detailPost!.postId,
        loginUsername,
        this.displayNickname.length > 0 ? this.displayNickname : '我',
        '',
        trimmed,
        deviceId
      );
      if (commentResult.success) {
        const oldPost = this.detailPost!;
        const oldList = oldPost.commentsList;
        const newList: CommentItemType[] = [];
        for (let i = 0; i < oldList.length; i++) {
          newList.push(oldList[i]);
        }
        const newComment: CommentItemType = {
          username: this.displayNickname.length > 0 ? this.displayNickname : '我',
          content: trimmed
        };
        newList.push(newComment);

        const updatedPost: FeedItemType = {
          id: oldPost.id, postId: oldPost.postId, type: oldPost.type,
          url: oldPost.url, username: oldPost.username, userId: oldPost.userId,
          avatar: oldPost.avatar, description: oldPost.description,
          createTime: oldPost.createTime, likes: oldPost.likes,
          comments: newList.length, isLiked: oldPost.isLiked,
          commentsList: newList, categoryId: oldPost.categoryId,
          categoryName: oldPost.categoryName
        };
        this.detailPost = updatedPost;
        this.postCommentText = '';
        promptAction.showToast({ message: '评论已发送', duration: 1500 });
      }
    } catch (err) {
      promptAction.showToast({ message: '评论失败: ' + (err as Error).message, duration: 2000 });
    }
    this.isSendingPostComment = false;
  }

  private getAvatarSrc(): string | Resource {
    if (this.displayAvatar && this.displayAvatar.length > 0) {
      return this.displayAvatar;
    }
    return $r('app.media.background');
  }

  private getPostImage(post: FeedItemType): string | Resource {
    if (post.url.length > 0) return post.url;
    return $r('app.media.nai');
  }

  private openAuthDialog(registerMode: boolean): void {
    this.isRegisterMode = registerMode;
    this.showLoginDialog = true;
  }

  private closeAuthDialog(): void {
    this.showLoginDialog = false;
    this.loginUsername = '';
    this.loginPassword = '';
    this.registerConfirmPassword = '';
    this.isRegisterMode = false;
  }

  private getTimeDisplay(timestamp: number): string {
    if (timestamp <= 0) return '刚刚';
    const now = Date.now();
    const diffMs = now - timestamp;
    const diffMin = Math.floor(diffMs / 60000);
    const diffHour = Math.floor(diffMin / 60);
    const diffDay = Math.floor(diffHour / 24);
    if (diffMin < 1) return '刚刚';
    if (diffMin < 60) return diffMin + '分钟前';
    if (diffHour < 24) return diffHour + '小时前';
    if (diffDay < 7) return diffDay + '天前';
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return year + '-' + month + '-' + day + ' ' + hours + ':' + minutes;
  }

  build() {
    Stack() {
      if (this.showAllWorks) {
        Column() {
          Row() {
            Text('← ' + (this.showPostDetail ? '返回作品列表' : '返回个人主页'))
              .fontSize(15).fontColor('#FFD700')
              .onClick(() => {
                if (this.showPostDetail) {
                  this.showPostDetail = false;
                  this.detailPost = null;
                  this.showPostComments = false;
                } else {
                  this.showAllWorks = false;
                  this.showPostDetail = false;
                  this.detailPost = null;
                  this.showPostComments = false;
                }
              })
              .margin({ right: 12 })
            Text(this.showPostDetail ? '帖子详情' : '全部作品 (' + this.myWorks.length + ')')
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1A1A2E')
              .layoutWeight(1)
          }
          .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(Color.White)

          if (this.showPostDetail && this.detailPost !== null) {
            Scroll() {
              Column() {
                Image(this.getPostImage(this.detailPost!))
                  .width('100%').aspectRatio(1).objectFit(ImageFit.Cover)
                  .backgroundColor('#E8E8E8')

                Row() {
                  Image(this.detailPost!.avatar.length > 0 ? this.detailPost!.avatar : $r('app.media.nai'))
                    .width(36).height(36).borderRadius(18).margin({ right: 8 })
                  Column() {
                    Text(this.detailPost!.username)
                      .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
                    Text(this.getTimeDisplay(this.detailPost!.createTime))
                      .fontSize(12).fontColor('#999999')
                  }
                  .alignItems(HorizontalAlign.Start)
                  Blank()
                }
                .width('100%').padding({ left: 12, right: 12, top: 12 })

                Text(this.detailPost!.description)
                  .fontSize(15).fontColor('#444444')
                  .padding({ left: 12, right: 12, top: 8 }).width('100%')

                Row() {
                  Row() {
                    Image(this.detailPost!.isLiked ? $r('app.media.good_selected') : $r('app.media.good'))
                      .width(20).height(20).fillColor('#FF6B6B')
                    Text(this.detailPost!.likes.toString())
                      .fontSize(14).fontColor(this.detailPost!.isLiked ? '#FF0000' : '#666666')
                      .margin({ left: 4 })
                  }
                  .margin({ right: 24 })

                  Row() {
                    Image($r('app.media.comment'))
                      .width(20).height(20).fillColor('#666666')
                    Text(this.detailPost!.comments.toString())
                      .fontSize(14).fontColor('#666666').margin({ left: 4 })
                  }
                  .onClick(() => { this.showPostComments = !this.showPostComments; })

                  Blank()

                  Text('删除')
                    .fontSize(14).fontColor('#FF0000')
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(16).backgroundColor('#FFF0F0')
                    .onClick(() => {
                      promptAction.showDialog({
                        title: '删除帖子',
                        message: '确定要删除这条帖子吗？',
                        buttons: [{ text: '取消', color: '#999999' }, { text: '删除', color: '#FF0000' }]
                      }).then((data: promptAction.ShowDialogSuccessResponse) => {
                        if (data.index === 1) {
                          this.onDeletePost(this.detailPost!.postId);
                          this.showPostDetail = false;
                          this.detailPost = null;
                          this.showPostComments = false;
                        }
                      });
                    })
                }
                .width('100%').padding({ left: 12, right: 12, top: 16, bottom: 16 })
                .backgroundColor(Color.White).borderRadius(8).margin({ top: 8 })

                if (this.showPostComments && this.detailPost !== null) {
                  Column() {
                    if (this.detailPost!.commentsList.length > 0) {
                      Text('评论 (' + this.detailPost!.commentsList.length + ')')
                        .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333')
                        .width('100%').margin({ bottom: 8 })

                      ForEach(this.detailPost!.commentsList, (comment: CommentItemType, index: number) => {
                        Row() {
                          Row() {
                            Text(comment.username)
                              .fontSize(13).fontColor('#FF9800').fontWeight(FontWeight.Medium)
                            if (this.displayNickname.length > 0 && comment.username === this.displayNickname) {
                              Text('我')
                                .fontSize(10).fontColor('#FFFFFF')
                                .backgroundColor('#FFD700')
                                .borderRadius(8).padding({ left: 6, right: 6, top: 2, bottom: 2 })
                                .margin({ left: 4 })
                            }
                            Text(': ').fontSize(13).fontColor('#FF9800').fontWeight(FontWeight.Medium)
                          }
                          .margin({ right: 6 })

                          Text(comment.content).fontSize(14).fontColor('#333333')
                        }
                        .width('100%').padding({ top: 4, bottom: 4 })
                        .alignItems(VerticalAlign.Center)
                      })
                    } else {
                      Text('暂无评论').fontSize(14).fontColor('#999999').width('100%')
                        .padding({ top: 8, bottom: 8 }).textAlign(TextAlign.Center)
                    }

                    Row() {
                      TextInput({ placeholder: '说点什么...', text: this.postCommentText })
                        .width('75%').height(40).backgroundColor('#F5F5F5').borderRadius(20)
                        .padding({ left: 16, right: 16 }).fontSize(14).placeholderColor('#AAAAAA')
                        .onChange((v: string) => { this.postCommentText = v; })

                      Button(this.isSendingPostComment ? '发送中' : '发送')
                        .width('20%').height(40)
                        .backgroundColor(this.isSendingPostComment ? '#CCCCCC' : '#FFD700')
                        .fontColor('#1A1A2E').borderRadius(20).fontSize(14).fontWeight(FontWeight.Medium)
                        .enabled(!this.isSendingPostComment)
                        .onClick(() => { this.handlePostComment(); })
                    }
                    .width('100%').justifyContent(FlexAlign.SpaceBetween).padding({ top: 8 })
                  }
                  .width('100%').padding({ left: 12, right: 12, bottom: 12 })
                  .backgroundColor('#FAFAFA').borderRadius(8).margin({ top: 8 })
                }
              }
              .width('100%')
            }
            .layoutWeight(1)
          } else {
            Grid() {
              ForEach(this.myWorks, (post: FeedItemType) => {
                GridItem() {
                  Column() {
                    Image(this.getPostImage(post))
                      .width('100%').aspectRatio(1).objectFit(ImageFit.Cover)
                      .borderRadius(8).backgroundColor('#E8E8E8')
                    Row() {
                      Image($r('app.media.good')).width(12).height(12).fillColor('#FF6B6B')
                      Text(post.likes.toString()).fontSize(11).fontColor('#666666').margin({ left: 2 })
                      Image($r('app.media.comment')).width(12).height(12).fillColor('#666666').margin({ left: 8 })
                      Text(post.comments.toString()).fontSize(11).fontColor('#666666').margin({ left: 2 })
                    }
                    .width('100%').padding({ top: 4 }).justifyContent(FlexAlign.Start)
                  }
                  .width('100%')
                  .onClick(() => {
                    this.detailPost = post;
                    this.showPostComments = false;
                    this.postCommentText = '';
                    this.showPostDetail = true;
                  })
                }
              })
            }
            .columnsTemplate('1fr 1fr').rowsGap(12).columnsGap(12)
            .width('95%').padding({ top: 12, bottom: 12 }).layoutWeight(1)
          }
        }
        .width('100%').height('100%').backgroundColor('#F8F8FC')
      } else {
        Column() {
          Column() {
            if (!this.isLoggedIn) {
              Column() {
                Text('🔒').fontSize(40).margin({ bottom: 8 })
                Text('请登录以使用完整功能')
                  .fontSize(16).fontColor('rgba(255,255,255,0.8)')
                  .margin({ bottom: 16 })

                Row() {
                  Button('登录云端')
                    .width(120).height(44)
                    .backgroundColor('#FFD700').fontColor('#1A1A2E')
                    .fontSize(15).fontWeight(FontWeight.Medium).borderRadius(22)
                    .onClick(() => { this.openAuthDialog(false); })

                  Button('注册账号')
                    .width(120).height(44)
                    .backgroundColor('rgba(255,255,255,0.15)')
                    .fontColor(Color.White).fontSize(15).fontWeight(FontWeight.Medium).borderRadius(22)
                    .margin({ left: 16 })
                    .onClick(() => { this.openAuthDialog(true); })
                }
              }
              .width('100%')
              .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
              .padding({ top: 50, bottom: 50 })
            } else {
              Row() {
                Stack() {
                  Image(this.getAvatarSrc())
                    .width(72).height(72).borderRadius(36)
                    .border({ width: 2, color: Color.White }).margin({ right: 16 })
                }
                .onClick(() => { this.selectAvatar(); })

                Column() {
                  Text(this.displayNickname.length > 0 ? this.displayNickname : '未设置昵称')
                    .fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
                    .onClick(() => {
                      this.editNickname = this.displayNickname;
                      this.showEditProfile = true;
                    })
                  Text(this.displayBio)
                    .fontSize(14).fontColor('rgba(255,255,255,0.8)')
                    .margin({ top: 4 })
                    .onClick(() => {
                      this.editBio = this.displayBio;
                      this.showEditBio = true;
                    })
                }
                .alignItems(HorizontalAlign.Start)
                Blank()
                Image($r('app.media.arrow_right'))
                  .width(24).height(24).fillColor(Color.White)
              }
              .width('90%').padding({ top: 30, bottom: 20 })

              Row() {
                Column() {
                  Text('128').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  Text('关注').fontSize(13).fontColor('rgba(255,255,255,0.7)')
                }.margin({ right: 30 })
                Column() {
                  Text(this.myWorks.length.toString()).fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  Text('作品').fontSize(13).fontColor('rgba(255,255,255,0.7)')
                }.margin({ right: 30 })
                Column() {
                  Text(this.totalLikes.toString()).fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  Text('获赞').fontSize(13).fontColor('rgba(255,255,255,0.7)')
                }
              }
              .width('90%').padding({ bottom: 16 }).justifyContent(FlexAlign.Start)

              Row() {
                Button('同步到云端')
                  .width(120).height(36)
                  .backgroundColor('rgba(255,215,0,0.2)')
                  .fontColor('#FFD700').fontSize(13).fontWeight(FontWeight.Medium)
                  .borderRadius(18).margin({ right: 10 })
                  .onClick(() => { this.handleSync(); })
                Button('退出')
                  .width(80).height(36)
                  .backgroundColor('rgba(255,255,255,0.1)')
                  .fontColor('rgba(255,255,255,0.8)').fontSize(13).borderRadius(18)
                  .onClick(() => { this.handleLogout(); })

                Blank()
                Text(this.syncStatusText)
                  .fontSize(12).fontColor('rgba(255,255,255,0.6)').margin({ right: 8 })
              }
              .width('90%').padding({ bottom: 16 })
            }
          }
          .width('100%').backgroundColor('#1A1A2E')
          .borderRadius({ bottomLeft: 24, bottomRight: 24 })

          Column() {
            Row() {
              Text('我的作品').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#1A1A2E')
              Blank()
              if (this.isLoggedIn) {
                Text('查看全部 >')
                  .fontSize(14).fontColor('#FFD700').fontWeight(FontWeight.Medium)
                  .onClick(() => { this.showAllWorks = true; })
              }
            }
            .width('90%').margin({ top: 20, bottom: 12 })

            if (this.isLoggedIn) {
              Grid() {
                if (this.myWorks.length > 0) {
                  ForEach(this.myWorks.length > 6 ? this.myWorks.slice(0, 6) : this.myWorks, (post: FeedItemType) => {
                    GridItem() {
                      Image(this.getPostImage(post))
                        .width('100%').aspectRatio(1).borderRadius(8).backgroundColor('#E8E8E8')
                        .onClick(() => {
                          this.detailPost = post;
                          this.showPostComments = false;
                          this.postCommentText = '';
                          this.showAllWorks = true;
                          this.showPostDetail = true;
                        })
                    }
                  })
                } else {
                  GridItem() {
                    Column() {
                      Text('📷').fontSize(40).margin({ bottom: 8 })
                      Text('暂无作品').fontSize(14).fontColor('#999999')
                    }
                    .width('100%').aspectRatio(1)
                    .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
                    .backgroundColor('#F5F5F5').borderRadius(8)
                  }
                }
              }
              .columnsTemplate('1fr 1fr 1fr').rowsGap(12).columnsGap(12)
              .width('90%').padding({ bottom: 12 })
            } else {
              Column() {
                Text('🔒').fontSize(36).margin({ bottom: 8 })
                Text('请先登录或注册后查看')
                  .fontSize(15).fontColor('#999999')
                  .textAlign(TextAlign.Center)
                Text('点击上方按钮登录/注册')
                  .fontSize(13).fontColor('#BBBBBB')
                  .margin({ top: 4 })
                  .textAlign(TextAlign.Center)
              }
              .width('100%').padding({ top: 20, bottom: 30 })
              .alignItems(HorizontalAlign.Center)
            }
          }
          .width('100%').alignItems(HorizontalAlign.Center)
        }
        .width('100%').height('100%')
        .backgroundColor('#F8F8FC')
      }

      if (this.showLoginDialog) {
        Column() {
          Column() {
            Text(this.isRegisterMode ? '注册云端账号' : '登录云端')
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1A1A2E')
              .margin({ bottom: 20 })

            TextInput({ placeholder: '用户名', text: this.loginUsername })
              .width('100%').height(44).backgroundColor('#F5F5F5').borderRadius(10)
              .padding({ left: 16 }).fontSize(15)
              .onChange((v: string) => { this.loginUsername = v; })
              .margin({ bottom: 12 })

            TextInput({ placeholder: '密码', text: this.loginPassword })
              .width('100%').height(44).backgroundColor('#F5F5F5').borderRadius(10)
              .padding({ left: 16 }).fontSize(15).type(InputType.Password)
              .onChange((v: string) => { this.loginPassword = v; })
              .margin({ bottom: this.isRegisterMode ? 12 : 20 })

            if (this.isRegisterMode) {
              TextInput({ placeholder: '确认密码', text: this.registerConfirmPassword })
                .width('100%').height(44).backgroundColor('#F5F5F5').borderRadius(10)
                .padding({ left: 16 }).fontSize(15).type(InputType.Password)
                .onChange((v: string) => { this.registerConfirmPassword = v; })
                .margin({ bottom: 20 })
            }

            Button(this.isRegisterMode
              ? (this.isRegistering ? '注册中...' : '注册并登录')
              : (this.isLoggingIn ? '登录中...' : '登录'))
              .width('100%').height(44)
              .backgroundColor('#FFD700').fontColor('#1A1A2E')
              .fontSize(16).fontWeight(FontWeight.Bold).borderRadius(22)
              .enabled(!this.isLoggingIn && !this.isRegistering)
              .onClick(() => {
                if (this.isRegisterMode) {
                  this.handleRegister();
                } else {
                  this.handleLogin();
                }
              })

            Button(this.isRegisterMode ? '已有账号？去登录' : '没有账号？去注册')
              .width('100%').height(40)
              .backgroundColor(Color.Transparent).fontColor('#1A1A2E')
              .fontSize(14).borderRadius(20).margin({ top: 8 })
              .enabled(!this.isLoggingIn && !this.isRegistering)
              .onClick(() => {
                this.isRegisterMode = !this.isRegisterMode;
                this.registerConfirmPassword = '';
              })

            Button('取消').width('100%').height(44)
              .backgroundColor('#F5F5F5').fontColor('#999999')
              .fontSize(15).borderRadius(22).margin({ top: 8 })
              .onClick(() => { this.closeAuthDialog(); })
          }
          .width('80%').padding(24)
          .backgroundColor(Color.White).borderRadius(16)
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.15)' })
        }
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => { this.closeAuthDialog(); })
      }

      if (this.showEditProfile) {
        Column() {
          Column() {
            Text('修改昵称')
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1A1A2E')
              .margin({ bottom: 20 })

            TextInput({ placeholder: '输入新昵称', text: this.editNickname })
              .width('100%').height(44).backgroundColor('#F5F5F5').borderRadius(10)
              .padding({ left: 16 }).fontSize(15)
              .onChange((v: string) => { this.editNickname = v; })

            Row() {
              Button('取消')
                .width('45%').height(44)
                .backgroundColor('#F5F5F5').fontColor('#999999')
                .fontSize(15).borderRadius(22)
                .onClick(() => { this.showEditProfile = false; })

              Button('保存')
                .width('45%').height(44)
                .backgroundColor('#FFD700').fontColor('#1A1A2E')
                .fontSize(15).fontWeight(FontWeight.Bold).borderRadius(22)
                .onClick(() => { this.saveNickname(); })
            }
            .width('100%').justifyContent(FlexAlign.SpaceBetween).margin({ top: 20 })
          }
          .width('80%').padding(24)
          .backgroundColor(Color.White).borderRadius(16)
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.15)' })
        }
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => { this.showEditProfile = false; })
      }

      if (this.showEditBio) {
        Column() {
          Column() {
            Text('修改个性签名')
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1A1A2E')
              .margin({ bottom: 20 })

            TextArea({ placeholder: '输入个性签名', text: this.editBio })
              .width('100%').height(100).backgroundColor('#F5F5F5').borderRadius(10)
              .padding(12).fontSize(15)
              .onChange((v: string) => { this.editBio = v; })

            Row() {
              Button('取消')
                .width('45%').height(44)
                .backgroundColor('#F5F5F5').fontColor('#999999')
                .fontSize(15).borderRadius(22)
                .onClick(() => { this.showEditBio = false; })

              Button('保存')
                .width('45%').height(44)
                .backgroundColor('#FFD700').fontColor('#1A1A2E')
                .fontSize(15).fontWeight(FontWeight.Bold).borderRadius(22)
                .onClick(async () => {
                  const trimmed = this.editBio.trim();
                  if (!this.isLoggedIn) {
                    promptAction.showToast({ message: '请先登录云端', duration: 1500 });
                    return;
                  }
                  try {
                    const currentNickname = AppStorage.get<string>('display_nickname') || '';
                    const currentAvatar = AppStorage.get<string>('display_avatar') || '';

                    const result = await distributedApi.updateProfile({
                      displayNickname: currentNickname,
                      avatar: currentAvatar,
                      bio: trimmed
                    });
                    AppStorage.set<string>('display_bio', result.bio!);
                    this.showEditBio = false;
                    promptAction.showToast({ message: '个性签名已更新', duration: 1500 });
                  } catch (err) {
                    promptAction.showToast({ message: '更新失败: ' + (err as Error).message, duration: 2000 });
                  }
                })
            }
            .width('100%').justifyContent(FlexAlign.SpaceBetween).margin({ top: 20 })
          }
          .width('80%').padding(24)
          .backgroundColor(Color.White).borderRadius(16)
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.15)' })
        }
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => { this.showEditBio = false; })
      }
    }
    .width('100%').height('100%')
  }
}