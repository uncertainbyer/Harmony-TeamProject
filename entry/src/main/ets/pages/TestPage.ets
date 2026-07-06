import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { PostService } from '../service/PostService';
import { PostModel } from '../model/PostModel';

@Entry
@Component
struct TestPage {
  @State message: string = '点击按钮测试';
  @State postCount: number = 0;
  private postService: PostService = new PostService();

  async aboutToAppear(): Promise<void> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      await DatabaseHelper.getInstance().init(context);
      this.message = '数据库初始化成功';
    } catch (err) {
      const errorMsg: string = (err as Error).message;
      this.message = '初始化失败: ' + errorMsg;
    }
  }

  build() {
    Column() {
      Text('数据层测试页面')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20, bottom: 20 })

      Text(this.message)
        .fontSize(16)
        .fontColor('#666666')
        .margin({ bottom: 20 })

      Text('帖子数量: ' + this.postCount)
        .fontSize(16)
        .margin({ bottom: 20 })

      Button('测试发布帖子')
        .width('80%')
        .margin({ bottom: 10 })
        .onClick(async () => {
          try {
            const post: PostModel = await this.postService.publishPost(
              'user001',
              '测试用户',
              '',
              '这是一条测试帖子',
              [],
              'cat_scenery',
              '风景',
              'device001'
            );
            this.message = '发布成功: ' + post.postId;
          } catch (err) {
            const errorMsg: string = (err as Error).message;
            this.message = '发布失败: ' + errorMsg;
          }
        })

      Button('测试查询帖子')
        .width('80%')
        .margin({ bottom: 10 })
        .onClick(async () => {
          try {
            const posts: PostModel[] = await this.postService.getPostList(1, 10);
            this.postCount = posts.length;
            this.message = '查询成功，共 ' + posts.length + ' 条';
          } catch (err) {
            const errorMsg: string = (err as Error).message;
            this.message = '查询失败: ' + errorMsg;
          }
        })

      Button('测试删除帖子')
        .width('80%')
        .margin({ bottom: 10 })
        .onClick(async () => {
          try {
            const posts: PostModel[] = await this.postService.getPostList(1, 1);
            if (posts.length > 0) {
              const success: boolean = await this.postService.deletePost(posts[0].postId);
              this.message = success ? '删除成功' : '删除失败';
            } else {
              this.message = '没有可删除的帖子';
            }
          } catch (err) {
            const errorMsg: string = (err as Error).message;
            this.message = '删除失败: ' + errorMsg;
          }
        })

      Button('测试点赞')
        .width('80%')
        .margin({ bottom: 10 })
        .onClick(async () => {
          try {
            const posts: PostModel[] = await this.postService.getPostList(1, 1);
            if (posts.length > 0) {
              const newCount: number = await this.postService.likePost(posts[0].postId);
              this.message = '点赞成功，当前点赞数: ' + newCount;
            } else {
              this.message = '没有可点赞的帖子';
            }
          } catch (err) {
            const errorMsg: string = (err as Error).message;
            this.message = '点赞失败: ' + errorMsg;
          }
        })

      Button('获取帖子总数')
        .width('80%')
        .margin({ bottom: 10 })
        .onClick(async () => {
          try {
            const count: number = await this.postService.getPostCount();
            this.postCount = count;
            this.message = '总数: ' + count;
          } catch (err) {
            const errorMsg: string = (err as Error).message;
            this.message = '获取失败: ' + errorMsg;
          }
        })
    }
    .width('100%')
    .height('100%')
    .padding(20)
  }
}