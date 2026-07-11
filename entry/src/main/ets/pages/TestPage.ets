// SocialMediaMain.ets
import { postApi } from '../api/PostApi';
import { commentApi } from '../api/CommentApi';
import { aiClassifyApi } from '../api/AIClassifyApi';
import { distributedApi } from '../api/DistributedApi';
import { Constants } from '../common/Constants';
import { promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { LikedCache } from '../common/LikedCache';
import { SessionManager } from '../common/SessionManager';

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

// ========== 工具函数：生成随机昵称 ==========
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

// ========== 初始化显示昵称和头像的持久化存储 ==========
PersistentStorage.persistProp('display_nickname', '');
PersistentStorage.persistProp('display_avatar', '');

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

  // ✅ 显示昵称和头像（持久化）
  @StorageLink('display_nickname') displayNickname: string = '';
  @StorageLink('display_avatar') displayAvatar: string = '';

  private currentFeedPage: number = 1;
  private hasMoreFeed: boolean = true;
  private tabBarHeight: number = 72;
  private feedIdCounter: number = 1;
  private pollingTimer: number = -1;
  private uiContext?: common.Context;

  private tabItems: Array<TabItemType> = [
    { title: '首页', icon: $r('app.media.home'), selectedIcon: $r('app.media.home_selected') },
    { title: '分类', icon: $r('app.media.classify'), selectedIcon: $r('app.media.classify_selected') },
    { title: '发布', icon: $r('app.media.publish'), selectedIcon: $r('app.media.publish_selected') },
    { title: 'AI识图', icon: $r('app.media.ai'), selectedIcon: $r('app.media.ai_selected') },
    { title: '我', icon: $r('app.media.me'), selectedIcon: $r('app.media.me_selected') }
  ];

  private likedIds: string[] = [];

  private async loadLikedIds(): Promise<void> {
    try {
      this.likedIds = await LikedCache.getLikedIds();
    } catch (_) {
      this.likedIds = [];
    }
  }

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

  // ============ 生命周期 ============

  aboutToAppear(): void {
    try {
      this.uiContext = getContext(this);
      AppStorage.setOrCreate('globalAbilityContext', this.uiContext);
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
    await this.loadLikedIds();
    try {
      aiClassifyApi.preload(null).catch(() => {});
    } catch (_) {}

    try {
      const autoLoggedIn: boolean = await SessionManager.autoLogin();
      if (autoLoggedIn) {
        console.info('[SocialMediaMain] 自动登录成功');
        if (distributedApi.isReady() && !distributedApi.localDeviceId.startsWith('local_')) {
          await distributedApi.sync(true);
          this.startPolling();
        }
      } else {
        console.info('[SocialMediaMain] 未登录，仅本地模式');
      }
    } catch (err) {
      console.warn('[SocialMediaMain] 自动登录异常:', (err as Error).message);
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
        const newItems: FeedItemType[] = [];
        for (let i = 0; i < result.data.length; i++) {
          const post = result.data[i];
          const images = post.getImagePathArray();
          const item: FeedItemType = {
            id: this.feedIdCounter++,
            postId: post.postId,
            type: 'image',
            url: images.length > 0 ? images[0] : '',
            username: post.userName,
            avatar: post.userAvatar,
            description: post.content,
            createTime: post.createTime || Date.now(),
            likes: post.likeCount,
            comments: post.commentCount,
            isLiked: this.isPostLiked(post.postId),
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
        this.feedData = refresh ? newItems : [...this.feedData, ...newItems];
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
    if (isLiked) {
      await LikedCache.addLikedId(postId);
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
      await LikedCache.removeLikedId(postId);
      const newIds: string[] = [];
      for (let i = 0; i < this.likedIds.length; i++) {
        if (this.likedIds[i] !== postId) {
          newIds.push(this.likedIds[i]);
        }
      }
      this.likedIds = newIds;
    }

    const newFeedData: FeedItemType[] = [];
    for (let i = 0; i < this.feedData.length; i++) {
      const item = this.feedData[i];
      if (item.postId === postId) {
        newFeedData.push({
          id: item.id, postId: item.postId, type: item.type, url: item.url,
          username: item.username, avatar: item.avatar, description: item.description,
          createTime: item.createTime,
          likes: newCount, comments: item.comments, isLiked: isLiked,
          commentsList: item.commentsList, categoryId: item.categoryId, categoryName: item.categoryName,
        });
      } else {
        newFeedData.push(item);
      }
    }
    this.feedData = newFeedData;

    // ✅ 同步更新 myWorks 中的点赞数据
    const newMyWorks: FeedItemType[] = [];
    for (let i = 0; i < this.myWorks.length; i++) {
      const w = this.myWorks[i];
      if (w.postId === postId) {
        newMyWorks.push({
          id: w.id, postId: w.postId, type: w.type, url: w.url,
          username: w.username, avatar: w.avatar, description: w.description,
          createTime: w.createTime,
          likes: newCount, comments: w.comments, isLiked: isLiked,
          commentsList: w.commentsList, categoryId: w.categoryId, categoryName: w.categoryName,
        });
      } else {
        newMyWorks.push(w);
      }
    }
    this.myWorks = newMyWorks;
  }

  handleCommentAdd(postId: string, comment: CommentItemType): void {
    const newFeedData: FeedItemType[] = [];
    for (let i = 0; i < this.feedData.length; i++) {
      const item = this.feedData[i];
      if (item.postId === postId) {
        const filtered: CommentItemType[] = [];
        for (let j = 0; j < item.commentsList.length; j++) {
          if (item.commentsList[j].content.length > 0) filtered.push(item.commentsList[j]);
        }
        filtered.push(comment);
        newFeedData.push({
          id: item.id, postId: item.postId, type: item.type, url: item.url,
          username: item.username, avatar: item.avatar, description: item.description,
          createTime: item.createTime,
          likes: item.likes, comments: filtered.length, isLiked: item.isLiked,
          commentsList: filtered, categoryId: item.categoryId, categoryName: item.categoryName,
        });
      } else {
        newFeedData.push(item);
      }
    }
    this.feedData = newFeedData;

    // ✅ 同步更新 myWorks
    const newMyWorks: FeedItemType[] = [];
    for (let i = 0; i < this.myWorks.length; i++) {
      const w = this.myWorks[i];
      if (w.postId === postId) {
        const filtered: CommentItemType[] = [];
        for (let j = 0; j < w.commentsList.length; j++) {
          if (w.commentsList[j].content.length > 0) filtered.push(w.commentsList[j]);
        }
        filtered.push(comment);
        newMyWorks.push({
          id: w.id, postId: w.postId, type: w.type, url: w.url,
          username: w.username, avatar: w.avatar, description: w.description,
          createTime: w.createTime,
          likes: w.likes, comments: filtered.length, isLiked: w.isLiked,
          commentsList: filtered, categoryId: w.categoryId, categoryName: w.categoryName,
        });
      } else {
        newMyWorks.push(w);
      }
    }
    this.myWorks = newMyWorks;
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

  // ============ 发布帖子（使用显示昵称和头像） ============

  async handlePublish(description: string, imageUrl: string): Promise<void> {
    try {
      const userId: string = AppStorage.get<string>('user_id') || 'local_user';
      const deviceId: string = AppStorage.get<string>('device_id') || 'local_device';
      const imagePaths: string[] = imageUrl.length > 0 ? [imageUrl] : [];

      // ✅ 使用显示昵称和头像
      // ⚠️ 注意：服务器存储了 post.userName，修改昵称后旧帖仍显示旧名
      const publishName = this.displayNickname.length > 0 ? this.displayNickname : '用户';
      const publishAvatar = this.displayAvatar;

      const result = await postApi.publishWithAI(
        userId, publishName, publishAvatar, description, imagePaths, deviceId
      );

      if (result.success && result.data !== null) {
        const post = result.data;
        const images = post.getImagePathArray();
        const newPost: FeedItemType = {
          id: this.feedIdCounter++,
          postId: post.postId,
          type: 'image',
          url: images.length > 0 ? images[0] : '',
          username: publishName,
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
        // ✅ 匹配当前显示昵称
        const currentName = this.displayNickname.length > 0 ? this.displayNickname : '用户';
        const userPosts: FeedItemType[] = [];
        for (let i = 0; i < result.data.length; i++) {
          const post = result.data[i];
          if (post.userName === currentName) {
            const images = post.getImagePathArray();
            userPosts.push({
              id: this.feedIdCounter++,
              postId: post.postId,
              type: 'image',
              url: images.length > 0 ? images[0] : '',
              username: post.userName,
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
        // 合并去重
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
                .onClick(() => { this.initError = ''; this.aboutToAppear(); })
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
                displayNickname: this.displayNickname
              })
            }
          }
          if (this.currentTabIndex === 1) {
            CategoryView()
          }
          if (this.currentTabIndex === 2) {
            PublishView({
              uiContext: this.uiContext,
              onPublish: (description: string, imageUrl: string): void => {
                this.handlePublish(description, imageUrl);
              }
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
              }
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

  build() {
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

// ================== 单条 FeedItem ==================

@Component
struct FeedItem {
  @Prop feed: FeedItemType = {
    id: 0, postId: '', type: 'image', url: '', username: '', avatar: '',
    description: '', createTime: 0, likes: 0, comments: 0, isLiked: false,
    commentsList: [], categoryId: '', categoryName: ''
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
        const newList: CommentItemType[] = [];
        for (let i = 0; i < this.commentsList.length; i++) {
          newList.push(this.commentsList[i]);
        }
        const newComment: CommentItemType = { username: '我', content: trimmed };
        newList.push(newComment);
        this.commentsList = newList;
        this.commentText = '';
        this.isSending = false;
        this.onCommentAdd(this.feed.postId, newComment);
        return;
      }

      const userId: string = AppStorage.get<string>('user_id') || 'local_user';
      const deviceId: string = AppStorage.get<string>('device_id') || 'local_device';
      const result = await commentApi.publish(
        this.feed.postId, userId, '我', '', trimmed, deviceId
      );
      if (result.success) {
        const newList: CommentItemType[] = [];
        for (let i = 0; i < this.commentsList.length; i++) {
          newList.push(this.commentsList[i]);
        }
        const newComment: CommentItemType = { username: '我', content: trimmed };
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

  // 判断是否为当前用户的帖子（使用显示昵称）
  private isCurrentUserPost(): boolean {
    return this.displayNickname.length > 0 && this.feed.username === this.displayNickname;
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
                  Text(comment.username + ': ')
                    .fontSize(13).fontColor('#FF9800').fontWeight(FontWeight.Medium)
                  Text(comment.content)
                    .fontSize(14).fontColor('#333333')
                }
                .width('100%').padding({ top: 4, bottom: 4 })
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
        Button('选择图片/拍照')
          .width(180).height(44).backgroundColor('#FFD700')
          .fontColor('#1A1A2E').borderRadius(22).fontSize(15).fontWeight(FontWeight.Medium)
          .enabled(!this.isRecognizing)
          .onClick(() => { this.recognizeFromAlbum(); })
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
          Text('点击上方「选择图片/拍照」按钮，选择照片或拍照进行 AI 识别')
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
          const images = result.data[i].getImagePathArray();
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

// ================== 我 Tab（完整修改版） ==================

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

  @State isLoggedIn: boolean = false;
  @State showLoginDialog: boolean = false;
  @State isRegisterMode: boolean = false;
  @State loginUsername: string = '';
  @State loginPassword: string = '';
  @State registerConfirmPassword: string = '';
  @State isLoggingIn: boolean = false;
  @State isRegistering: boolean = false;
  @State syncStatusText: string = '';

  // 查看全部相关
  @State showAllWorks: boolean = false;
  @State showPostDetail: boolean = false;
  @State detailPost: FeedItemType | null = null;

  // 编辑资料相关
  @State showEditProfile: boolean = false;
  @State editNickname: string = '';

  async aboutToAppear(): Promise<void> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      AppStorage.setOrCreate<object>('uiAbilityContext', context);
      await distributedApi.init(context);
      this.isLoggedIn = distributedApi.isReady() && !distributedApi.localDeviceId.startsWith('local_');
    } catch (err) {
      console.warn('[ProfileView] 云同步初始化失败:', (err as Error).message);
      this.isLoggedIn = false;
    }
    this.onLoadMyWorks();
  }

  async handleLogin(): Promise<void> {
    if (this.loginUsername.trim().length === 0 || this.loginPassword.trim().length === 0) {
      promptAction.showToast({ message: '请输入账号和密码', duration: 2000 });
      return;
    }
    this.isLoggingIn = true;
    try {
      const result = await distributedApi.login(this.loginUsername.trim(), this.loginPassword.trim());
      if (result.success) {
        await SessionManager.saveCredentials(this.loginUsername.trim(), this.loginPassword.trim());

        // ✅ 登录成功，分配随机显示昵称（只在首次分配）
        const currentNickname = AppStorage.get<string>('display_nickname');
        if (!currentNickname || currentNickname.length === 0) {
          const newNickname = generateRandomNickname();
          AppStorage.setOrCreate('display_nickname', newNickname);
          this.onNicknameChange(newNickname);
        }

        this.isLoggedIn = true;
        this.showLoginDialog = false;
        promptAction.showToast({ message: '登录成功，数据已开启云端同步', duration: 2000 });
        distributedApi.sync(true).catch(() => {});
      } else {
        promptAction.showToast({ message: '登录失败: ' + result.message, duration: 2000 });
      }
    } catch (err) {
      promptAction.showToast({ message: '登录异常: ' + (err as Error).message, duration: 2000 });
    }
    this.isLoggingIn = false;
  }

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
      if (result.success) {
        await SessionManager.saveCredentials(username, password);

        // ✅ 注册成功后自动分配显示昵称和默认头像
        const newNickname = generateRandomNickname();
        AppStorage.setOrCreate('display_nickname', newNickname);
        AppStorage.setOrCreate('display_avatar', '');
        this.onNicknameChange(newNickname);
        this.onAvatarChange('');

        this.isLoggedIn = true;
        this.closeAuthDialog();
        promptAction.showToast({ message: '注册成功！你的显示昵称为: ' + newNickname, duration: 3000 });
        distributedApi.sync(true).catch(() => {});
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
      promptAction.showToast({ message: '请先登录', duration: 2000 });
      return;
    }
    try {
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
      await LikedCache.clearAll();
    } catch (_) {}
    this.isLoggedIn = false;
    promptAction.showToast({ message: '已退出登录', duration: 2000 });
  }

  // ✅ 保存昵称修改
  private saveNickname(): void {
    const trimmed = this.editNickname.trim();
    if (trimmed.length === 0) {
      promptAction.showToast({ message: '昵称不能为空', duration: 1500 });
      return;
    }
    if (trimmed.length > 20) {
      promptAction.showToast({ message: '昵称不能超过20个字符', duration: 1500 });
      return;
    }
    AppStorage.setOrCreate('display_nickname', trimmed);
    this.onNicknameChange(trimmed);
    this.showEditProfile = false;
    promptAction.showToast({ message: '昵称已更新', duration: 1500 });
  }

  // ✅ 选择头像
  private async selectAvatar(): Promise<void> {
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
        AppStorage.setOrCreate('display_avatar', uri);
        this.onAvatarChange(uri);
        promptAction.showToast({ message: '头像已更新', duration: 1500 });
      }
    } catch (err) {
      console.warn('[ProfileView] 选择头像失败:', (err as Error).message);
    }
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
      // ========== 查看全部作品界面 ==========
      if (this.showAllWorks) {
        Column() {
          Row() {
            Text('← ' + (this.showPostDetail ? '返回作品列表' : '返回个人主页'))
              .fontSize(15).fontColor('#FFD700')
              .onClick(() => {
                if (this.showPostDetail) {
                  this.showPostDetail = false;
                  this.detailPost = null;
                } else {
                  this.showAllWorks = false;
                  this.showPostDetail = false;
                  this.detailPost = null;
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
            // ========== 帖子详情视图 ==========
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

                // ✅ 正确显示点赞和评论数
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

                  Blank()

                  // ✅ 删除按钮
                  Text('删除')
                    .fontSize(14).fontColor('#FF0000')
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(16)
                    .backgroundColor('#FFF0F0')
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
                          const postId = this.detailPost!.postId;
                          this.onDeletePost(postId);
                          this.showPostDetail = false;
                          this.detailPost = null;
                        }
                      });
                    })
                }
                .width('100%').padding({ left: 12, right: 12, top: 16, bottom: 16 })
                .backgroundColor(Color.White).borderRadius(8).margin({ top: 8 })
              }
              .width('100%')
            }
            .layoutWeight(1)
          } else {
            // ========== 全部作品网格视图 ==========
            Grid() {
              ForEach(this.myWorks, (post: FeedItemType) => {
                GridItem() {
                  Column() {
                    Image(this.getPostImage(post))
                      .width('100%').aspectRatio(1).objectFit(ImageFit.Cover)
                      .borderRadius(8).backgroundColor('#E8E8E8')
                    Row() {
                      Image($r('app.media.good'))
                        .width(12).height(12).fillColor('#FF6B6B')
                      Text(post.likes.toString())
                        .fontSize(11).fontColor('#666666').margin({ left: 2 })
                      Image($r('app.media.comment'))
                        .width(12).height(12).fillColor('#666666').margin({ left: 8 })
                      Text(post.comments.toString())
                        .fontSize(11).fontColor('#666666').margin({ left: 2 })
                    }
                    .width('100%').padding({ top: 4 }).justifyContent(FlexAlign.Start)
                  }
                  .width('100%')
                  .onClick(() => {
                    this.detailPost = post;
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
        // ========== 主界面 ==========
        Column() {
          // 顶部个人信息
          Column() {
            Row() {
              // ✅ 显示可修改的头像（点击可更换）
              Stack() {
                Image(this.getAvatarSrc())
                  .width(72).height(72).borderRadius(36)
                  .border({ width: 2, color: Color.White }).margin({ right: 16 })
              }
              .onClick(() => {
                if (this.isLoggedIn) {
                  this.selectAvatar();
                } else {
                  promptAction.showToast({ message: '请先登录以修改头像', duration: 1500 });
                }
              })

              Column() {
                // ✅ 显示显示昵称（点击可修改）
                Text(this.displayNickname.length > 0 ? this.displayNickname : '未设置昵称')
                  .fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  .onClick(() => {
                    if (this.isLoggedIn) {
                      this.editNickname = this.displayNickname;
                      this.showEditProfile = true;
                    } else {
                      promptAction.showToast({ message: '请先登录以修改昵称', duration: 1500 });
                    }
                  })
                Text('个人简介 ✨ 热爱生活')
                  .fontSize(14).fontColor('rgba(255,255,255,0.8)').margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              Blank()
              Image($r('app.media.arrow_right'))
                .width(24).height(24).fillColor(Color.White)
            }
            .width('90%').padding({ top: 30, bottom: 20 })

            // ✅ 获赞数：从 myWorks 统计得出
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
              if (this.isLoggedIn) {
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
              } else {
                Button('登录云端')
                  .width(100).height(36)
                  .backgroundColor('rgba(255,215,0,0.2)')
                  .fontColor('#FFD700').fontSize(13).fontWeight(FontWeight.Medium)
                  .borderRadius(18).margin({ right: 10 })
                  .onClick(() => { this.openAuthDialog(false); })
                Button('注册账号')
                  .width(100).height(36)
                  .backgroundColor('rgba(255,255,255,0.1)')
                  .fontColor('rgba(255,255,255,0.8)').fontSize(13)
                  .borderRadius(18)
                  .onClick(() => { this.openAuthDialog(true); })
              }
              Blank()
              Text(this.syncStatusText)
                .fontSize(12).fontColor('rgba(255,255,255,0.6)').margin({ right: 8 })
            }
            .width('90%').padding({ bottom: 16 })
          }
          .width('100%').backgroundColor('#1A1A2E')
          .borderRadius({ bottomLeft: 24, bottomRight: 24 })

          // 我的作品
          Column() {
            Row() {
              Text('我的作品').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#1A1A2E')
              Blank()
              Text('查看全部 >')
                .fontSize(14).fontColor('#FFD700').fontWeight(FontWeight.Medium)
                .onClick(() => { this.showAllWorks = true; })
            }
            .width('90%').margin({ top: 20, bottom: 12 })

            Grid() {
              if (this.myWorks.length > 0) {
                ForEach(this.myWorks.length > 6 ? this.myWorks.slice(0, 6) : this.myWorks, (post: FeedItemType) => {
                  GridItem() {
                    Image(this.getPostImage(post))
                      .width('100%').aspectRatio(1).borderRadius(8).backgroundColor('#E8E8E8')
                      .onClick(() => {
                        this.detailPost = post;
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
          }
          .width('100%').alignItems(HorizontalAlign.Center)
        }
        .width('100%').height('100%')
        .backgroundColor('#F8F8FC')
      }

      // ========== 登录弹窗 ==========
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
              .onClick(() => {
                this.closeAuthDialog();
              })
          }
          .width('80%').padding(24)
          .backgroundColor(Color.White).borderRadius(16)
          .shadow({ radius: 12, color: 'rgba(0,0,0,0.15)' })
        }
        .width('100%').height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.closeAuthDialog();
        })
      }

      // ========== 编辑昵称弹窗 ==========
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
        .onClick(() => {
          this.showEditProfile = false;
        })
      }
    }
    .width('100%').height('100%')
  }
}