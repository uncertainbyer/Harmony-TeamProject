import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { PostService } from '../service/PostService';
import { CommentService } from '../service/CommentService';
import {
  DistributedService,
  DistributedSyncState,
  SyncConnectionState,
  SyncDeviceInfo,
  SyncStateListener
} from '../service/DistributedService';
import { PostModel } from '../model/PostModel';
import { CommentModel } from '../model/CommentModel';
import { RemoteDataListener, SyncEventBus } from '../distributed/SyncEventBus';
import { AIClassifyService } from '../service/AIClassifyService';

@Entry
@Component
struct TestPage {
  @State message: string = '正在初始化分布式同步';
  @State devices: SyncDeviceInfo[] = [];
  @State posts: PostModel[] = [];
  @State comments: CommentModel[] = [];
  @State selectedImages: string[] = [];
  @State postContent: string = '';
  @State commentContent: string = '';
  @State syncState: SyncConnectionState = SyncConnectionState.IDLE;
  @State transferProgress: number = 0;
  @State receivedSummary: string = '接收帖子 0，评论 0';

  private postService: PostService = new PostService();
  private commentService: CommentService = new CommentService();
  private distributedService: DistributedService = DistributedService.getInstance();
  private eventBus: SyncEventBus = SyncEventBus.getInstance();

  private stateListener: SyncStateListener = (state: DistributedSyncState): void => {
    this.devices = state.devices;
    this.syncState = state.state;
    this.transferProgress = state.transferProgress < 0 ? 0 : state.transferProgress;
    this.message = state.lastMessage;
    this.receivedSummary = '接收帖子 ' + state.receivedPostCount + '，评论 ' + state.receivedCommentCount;
  };

  private remoteDataListener: RemoteDataListener = (): void => {
    this.loadPosts();
  };

  async aboutToAppear(): Promise<void> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const dbResult = await DatabaseHelper.getInstance().init(context);
      if (!dbResult.success) {
        throw new Error(dbResult.errorMsg);
      }
      if (!this.distributedService.isReady()) {
        await this.distributedService.init(context);
      }
      this.distributedService.onStateChanged(this.stateListener);
      this.eventBus.onRemoteDataChanged(this.remoteDataListener);
      await this.loadPosts();
    } catch (err) {
      this.message = '初始化失败: ' + (err as Error).message;
    }
  }

  aboutToDisappear(): void {
    this.distributedService.offStateChanged(this.stateListener);
    this.eventBus.offRemoteDataChanged(this.remoteDataListener);
  }

  private async loadPosts(): Promise<void> {
    this.posts = await this.postService.getPostList(1, 50);
    if (this.posts.length > 0) {
      this.comments = await this.commentService.getAllComments(this.posts[0].postId);
    } else {
      this.comments = [];
    }
  }

  private async selectImages(): Promise<void> {
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 9;
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      this.selectedImages = result.photoUris;
      this.message = '已选择 ' + result.photoUris.length + ' 张图片';
    } catch (err) {
      this.message = '选择图片失败: ' + (err as Error).message;
    }
  }

  private async publishPost(): Promise<void> {
    if (this.postContent.trim().length === 0 && this.selectedImages.length === 0) {
      this.message = '请输入文字或选择图片';
      return;
    }
    try {
      // 使用 AI 自动分类发布
      const post: PostModel = await this.postService.publishPostWithAIClassify(
        'demo_user',
        '演示用户',
        '',
        this.postContent,
        this.selectedImages,
        this.distributedService.getLocalDeviceId()
      );
      this.message = '发布成功！AI 分类: ' + post.categoryName;
      this.postContent = '';
      this.selectedImages = [];
      await this.loadPosts();
      await this.distributedService.syncNow(false);
    } catch (err) {
      this.message = '发布失败: ' + (err as Error).message;
    }
  }

  private async publishComment(): Promise<void> {
    if (this.posts.length === 0 || this.commentContent.trim().length === 0) {
      this.message = '请先发布帖子并输入评论';
      return;
    }
    try {
      await this.commentService.publishComment(
        this.posts[0].postId,
        'demo_user',
        '演示用户',
        '',
        this.commentContent,
        this.distributedService.getLocalDeviceId()
      );
      this.commentContent = '';
      await this.loadPosts();
      await this.distributedService.syncNow(false);
    } catch (err) {
      this.message = '评论失败: ' + (err as Error).message;
    }
  }

  private stateText(): string {
    switch (this.syncState) {
      case SyncConnectionState.DISCOVERING:
        return '发现设备';
      case SyncConnectionState.CONNECTING:
        return '连接中';
      case SyncConnectionState.CONNECTED:
        return '已连接';
      case SyncConnectionState.SYNCING:
        return '同步中';
      case SyncConnectionState.ERROR:
        return '异常';
      default:
        return '待连接';
    }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('SocialPhoto 分布式同步演示')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .width('100%')

        Row() {
          Text('状态：' + this.stateText())
            .fontColor(this.syncState === SyncConnectionState.ERROR ? '#D9485F' : '#1677FF')
          Blank()
          Text(this.receivedSummary)
            .fontSize(13)
            .fontColor('#666666')
        }
        .width('100%')

        Text(this.message)
          .fontSize(14)
          .fontColor('#666666')
          .width('100%')

        Progress({ value: this.transferProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .visibility(this.syncState === SyncConnectionState.SYNCING ? Visibility.Visible : Visibility.Hidden)

        Row({ space: 8 }) {
          Button('搜索设备')
            .layoutWeight(1)
            .onClick(() => {
              try {
                this.distributedService.startDiscovery();
              } catch (err) {
                this.message = (err as Error).message;
              }
            })
          Button('立即全量同步')
            .layoutWeight(1)
            .onClick(async () => {
              await this.distributedService.syncNow(true);
            })
        }
        .width('100%')

        Text('附近与可信设备')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .width('100%')

        if (this.devices.length === 0) {
          Text('暂未发现设备。请确保两台真机在同一局域网并安装相同应用。')
            .fontSize(13)
            .fontColor('#999999')
            .width('100%')
        }

        ForEach(this.devices, (device: SyncDeviceInfo) => {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text(device.deviceName)
                .fontWeight(FontWeight.Medium)
              Text(device.connected ? '已连接，可自动同步' : (device.trusted ? '可信设备' : '待授权'))
                .fontSize(12)
                .fontColor(device.connected ? '#16A34A' : '#888888')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button(device.connected ? '同步' : '连接')
              .onClick(async () => {
                try {
                  await this.distributedService.connectDevice(device.deviceId);
                } catch (err) {
                  this.message = (err as Error).message;
                }
              })
          }
          .width('100%')
          .padding(10)
          .backgroundColor('#F5F7FA')
          .borderRadius(8)
        }, (device: SyncDeviceInfo) => device.deviceId)

        Divider()

        Text('设备A：发布图文')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .width('100%')

        TextInput({ text: this.postContent, placeholder: '输入文字，发布后自动同步到设备B' })
          .onChange((value: string) => {
            this.postContent = value;
          })

        Row({ space: 8 }) {
          Button('选择图片 (' + this.selectedImages.length + ')')
            .layoutWeight(1)
            .onClick(async () => {
              await this.selectImages();
            })
          Button('发布并同步')
            .layoutWeight(1)
            .onClick(async () => {
              await this.publishPost();
            })
        }
        .width('100%')

        if (this.selectedImages.length > 0) {
          Image(this.selectedImages[0])
            .width(140)
            .height(100)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        }

        Divider()

        Text('共享内容（设备B接收后自动刷新）')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .width('100%')

        ForEach(this.posts, (post: PostModel) => {
          Column({ space: 6 }) {
            Row() {
              Text(post.userName)
                .fontWeight(FontWeight.Medium)
              Blank()
              Text(post.deviceId === this.distributedService.getLocalDeviceId() ? '本机' : '其他设备')
                .fontSize(12)
                .fontColor('#1677FF')
            }
            .width('100%')
            Text(post.content)
              .width('100%')
            if (post.getImagePathArray().length > 0) {
              Image(post.getImagePathArray()[0])
                .width('100%')
                .height(180)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
            }
            Text('评论 ' + post.commentCount + ' · ' + post.categoryName)
              .fontSize(12)
              .fontColor('#888888')
              .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#E5E7EB' })
          .borderRadius(10)
        }, (post: PostModel) => post.postId)

        TextInput({ text: this.commentContent, placeholder: '评论最新一条帖子' })
          .onChange((value: string) => {
            this.commentContent = value;
          })
        Button('发表评论并同步')
          .width('100%')
          .onClick(async () => {
            await this.publishComment();
          })

        ForEach(this.comments, (comment: CommentModel) => {
          Text(comment.userName + '：' + comment.content)
            .fontSize(14)
            .width('100%')
            .padding(8)
            .backgroundColor('#F5F7FA')
            .borderRadius(6)
        }, (comment: CommentModel) => comment.commentId)
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
  }
}
