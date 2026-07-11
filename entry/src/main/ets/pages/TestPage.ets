// SocialMediaMain.ets
import { postApi } from '../api/PostApi';
import { commentApi } from '../api/CommentApi';
import { aiClassifyApi } from '../api/AIClassifyApi';
import { distributedApi } from '../api/DistributedApi';
import { Constants } from '../common/Constants';
import { promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
// ✅ 新增 import
import { SessionManager } from '../common/SessionManager';

interface TabItemType {
  title: string;
  icon: Resource;
  selectedIcon: Resource;
}

interface FeedItemType {
  id: number;
  postId: string;
  type: string;
  url: string;
  username: string;
  avatar: string;
  description: string;
  likes: number;
  comments: number;
  isLiked: boolean;
  commentsList: string[];
  categoryId: string;
  categoryName: string;
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

  handleImageClick(imageUrl: string): void {
    this.previewImageUrl = imageUrl;
    this.showGlobalImagePreview = true;
  }

  // ============ 生命周期 ============

  aboutToAppear(): void {
    try {
      this.uiContext = getContext(this);
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
    try {
      aiClassifyApi.preload(null).catch(() => {});
    } catch (_) {}

    // ✅ 自动登录
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
            likes: post.likeCount,
            comments: post.commentCount,
            isLiked: false,
            commentsList: [''],
            categoryId: post.categoryId,
            categoryName: post.categoryName,
          };
          try {
            const commentResult = await commentApi.getAllByPost(post.postId);
            if (commentResult.success && commentResult.data !== null) {
              const texts: string[] = [];
              for (let j = 0; j < commentResult.data.length; j++) {
                texts.push(commentResult.data[j].content);
              }
              item.commentsList = texts.length > 0 ? texts : [''];
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

  // ============ 发布帖子 ============

  async handlePublish(description: string, imageUrl: string): Promise<void> {
    try {
      const userId: string = AppStorage.get<string>('user_id') || 'local_user';
      const deviceId: string = AppStorage.get<string>('device_id') || 'local_device';
      const imagePaths: string[] = imageUrl.length > 0 ? [imageUrl] : [];

      const result = await postApi.publishWithAI(
        userId, '我', '', description, imagePaths, deviceId
      );

      if (result.success && result.data !== null) {
        const post = result.data;
        const images = post.getImagePathArray();
        const newPost: FeedItemType = {
          id: this.feedIdCounter++,
          postId: post.postId,
          type: 'image',
          url: images.length > 0 ? images[0] : '',
          username: '我',
          avatar: '',
          description: description || '分享我的生活',
          likes: 0,
          comments: 0,
          isLiked: false,
          commentsList: [''],
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
                onLoadMore: (): void => { this.loadFeed(false); }
              })
            }
          }
          if (this.currentTabIndex === 1) {
            CategoryView()
          }
          if (this.currentTabIndex === 2) {
            PublishView({
              onPublish: (description: string, imageUrl: string): void => {
                this.handlePublish(description, imageUrl);
              }
            })
          }
          if (this.currentTabIndex === 3) {
            AICameraView({ uiContext: this.uiContext })
          }
          if (this.currentTabIndex === 4) {
            ProfileView({ myWorks: this.myWorks })
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

  build() {
    List() {
      ForEach(this.feedData, (item: FeedItemType) => {
        ListItem() {
          FeedItem({ feed: item, onImageClick: this.onImageClick })
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
    description: '', likes: 0, comments: 0, isLiked: false, commentsList: [''],
    categoryId: '', categoryName: ''
  };
  onImageClick: (url: string) => void = () => {};
  @State isLiked: boolean = false;
  @State likeCount: number = 0;
  @State showCommentInput: boolean = false;
  @State commentText: string = '';
  @State commentsList: string[] = [];
  @State isSending: boolean = false;

  aboutToAppear(): void {
    this.isLiked = this.feed.isLiked;
    this.likeCount = this.feed.likes;

    const sourceList: string[] = this.feed.commentsList;
    const filtered: string[] = [];
    for (let i = 0; i < sourceList.length; i++) {
      if (sourceList[i].length > 0) {
        filtered.push(sourceList[i]);
      }
    }
    this.commentsList = filtered;
  }

  async handleLikeClick(): Promise<void> {
    try {
      if (this.feed.postId.length === 0) {
        this.isLiked = !this.isLiked;
        this.likeCount = this.isLiked ? this.likeCount + 1 : this.likeCount - 1;
        return;
      }
      const result = this.isLiked
        ? await postApi.unlike(this.feed.postId)
        : await postApi.like(this.feed.postId);
      if (result.success && result.data !== null) {
        this.isLiked = !this.isLiked;
        this.likeCount = result.data;
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
        const newList: string[] = [];
        for (let i = 0; i < this.commentsList.length; i++) {
          newList.push(this.commentsList[i]);
        }
        newList.push(trimmed);
        this.commentsList = newList;
        this.commentText = '';
        this.isSending = false;
        return;
      }

      const userId: string = AppStorage.get<string>('user_id') || 'local_user';
      const deviceId: string = AppStorage.get<string>('device_id') || 'local_device';
      const result = await commentApi.publish(
        this.feed.postId, userId, '我', '', trimmed, deviceId
      );
      if (result.success) {
        const newList: string[] = [];
        for (let i = 0; i < this.commentsList.length; i++) {
          newList.push(this.commentsList[i]);
        }
        newList.push(trimmed);
        this.commentsList = newList;
        this.commentText = '';
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
          Text(this.feed.username)
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#333333')
          Text('2小时前')
            .fontSize(12).fontColor('#999999')
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
      }
      .width('100%').padding({ left: 12, right: 12, top: 12 })

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
                .width('100%').margin({ bottom: 8 })
              ForEach(this.commentsList, (comment: string, index: number) => {
                Row() {
                  Text((index + 1) + '. ').fontSize(13).fontColor('#999999')
                  Text(comment).fontSize(14).fontColor('#333333')
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
  }

  build() {
    Column() {
      Stack() {
        Image($r('app.media.background'))
          .width('90%').height(300).borderRadius(16)
          .backgroundColor('#2D2D44').objectFit(ImageFit.Cover)
        Column() {
          Text('🔍').fontSize(50).margin({ bottom: 10 })
          if (this.recognizeResult.length > 0) {
            Text(this.recognizeResult)
              .fontSize(18).fontColor('#FFD700').fontWeight(FontWeight.Bold)
            Text(this.recognizeDetail)
              .fontSize(13).fontColor('rgba(255,255,255,0.7)').margin({ top: 6 })
          } else {
            Text('对准物体，AI将自动识别')
              .fontSize(16).fontColor(Color.White).fontWeight(FontWeight.Medium)
            Text('支持植物、动物、商品等')
              .fontSize(13).fontColor('rgba(255,255,255,0.7)').margin({ top: 6 })
          }
          if (this.isRecognizing) {
            LoadingProgress().width(40).height(40).margin({ top: 12 })
          }
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      }
      .width('100%').height(300).padding({ top: 20, bottom: 20 })

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
          .onClick(() => { promptAction.showToast({ message: '请拍照后自动识别', duration: 2000 }); })
      }

      Column() {
        Text('最近识别')
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor('#333333').width('90%')
          .margin({ top: 24, bottom: 10 })
        if (this.recognizeResult.length > 0) {
          Row() {
            Text(this.recognizeResult)
              .fontSize(14).fontColor('#FF9800').fontWeight(FontWeight.Medium)
          }
          .width('90%').margin({ top: 4 })
        } else {
          Text('点击上方「相册选择」按钮，选择一张图片进行 AI 识别')
            .fontSize(13).fontColor('#999999').width('90%').textAlign(TextAlign.Center)
        }
      }
      .width('100%').alignItems(HorizontalAlign.Center)

      Blank()
    }
    .width('100%').height('100%').backgroundColor('#F8F8FC')
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
  onPublish: (description: string, imageUrl: string) => void = () => {};

  build() {
    Column() {
      Column() {
        // 文本输入区
        Column() {
          TextArea({ placeholder: '分享你的想法...', text: this.description })
            .width('100%').height(120).backgroundColor('#F5F5F5').borderRadius(12)
            .padding(12).fontSize(16).placeholderColor('#AAAAAA')
            .onChange((value: string) => { this.description = value; })
        }
        .width('90%').margin({ top: 20 })

        // 添加图片区域
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
          .onClick(() => { this.hasSelectedImage = !this.hasSelectedImage; })
        }
        .width('90%').justifyContent(FlexAlign.Start).margin({ top: 16 })

        // 选项区域
        Row() {
          Button({ type: ButtonType.Circle }).width(20).height(20)
            .backgroundColor(this.isPressed1 ? '#FF0000' : '#FFD700')
            .onClick(() => { this.isPressed1 = !this.isPressed1; })
          Text('添加位置').fontSize(15).fontColor('#666666').margin({ left: 8 })
          Blank()
          Button({ type: ButtonType.Circle }).width(20).height(20)
            .backgroundColor(this.isPressed2 ? '#FF0000' : '#FFD700')
            .onClick(() => { this.isPressed2 = !this.isPressed2; })
          Text('公开').fontSize(15).fontColor('#666666').margin({ left: 8 })
        }
        .width('90%').padding({ top: 16, bottom: 16 })
        .borderWidth({ bottom: 1 }).borderColor('#EEEEEE')

        // 发布按钮
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

// ================== 我 Tab（带登录云端 + 自动保存凭据） ==================

@Component
struct ProfileView {
  @Prop myWorks: Array<FeedItemType> = [];

  @State isLoggedIn: boolean = false;
  @State showLoginDialog: boolean = false;
  @State isRegisterMode: boolean = false;
  @State loginUsername: string = '';
  @State loginPassword: string = '';
  @State registerConfirmPassword: string = '';
  @State isLoggingIn: boolean = false;
  @State isRegistering: boolean = false;
  @State syncStatusText: string = '';

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
        // ✅ 保存登录凭据，下次启动自动登录
        await SessionManager.saveCredentials(this.loginUsername.trim(), this.loginPassword.trim());

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

        this.isLoggedIn = true;
        this.closeAuthDialog();
        promptAction.showToast({ message: '注册成功，已开启云端同步', duration: 2000 });
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
        this.isLoggedIn = distributedApi.isReady() && !distributedApi.localDeviceId.startsWith('local_');
        promptAction.showToast({ message: '同步失败: ' + result.errorMsg, duration: 2000 });
      }
    } catch (err) {
      this.isLoggedIn = distributedApi.isReady() && !distributedApi.localDeviceId.startsWith('local_');
      promptAction.showToast({ message: '同步异常: ' + (err as Error).message, duration: 2000 });
    }
  }

  async handleLogout(): Promise<void> {
    try {
      await distributedApi.logout();
      // ✅ 清除保存的登录信息
      await SessionManager.clearCredentials();
    } catch (_) {}
    this.isLoggedIn = false;
    promptAction.showToast({ message: '已退出登录', duration: 2000 });
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

  build() {
    Stack() {
      // 主界面
      Column() {
        // 顶部个人信息
        Column() {
          Row() {
            Image($r('app.media.background'))
              .width(72).height(72).borderRadius(36)
              .border({ width: 2, color: Color.White }).margin({ right: 16 })
            Column() {
              Text('用户名')
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
              Text('个人简介 ✨ 热爱生活')
                .fontSize(14).fontColor('rgba(255,255,255,0.8)').margin({ top: 4 })
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
              Text('256').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
              Text('粉丝').fontSize(13).fontColor('rgba(255,255,255,0.7)')
            }.margin({ right: 30 })
            Column() {
              Text('89').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
              Text('获赞').fontSize(13).fontColor('rgba(255,255,255,0.7)')
            }
          }
          .width('90%').padding({ bottom: 16 }).justifyContent(FlexAlign.Start)

          // 登录/同步按钮
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
            Text('查看全部 >').fontSize(14).fontColor('#999999')
          }
          .width('90%').margin({ top: 20, bottom: 12 })

          Grid() {
            if (this.myWorks.length > 0) {
              ForEach(this.myWorks, (post: FeedItemType) => {
                GridItem() {
                  Image(this.getPostImage(post))
                    .width('100%').aspectRatio(1).borderRadius(8).backgroundColor('#E8E8E8')
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

      // ✅ 登录弹窗
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
    }
    .width('100%').height('100%')
  }
}
