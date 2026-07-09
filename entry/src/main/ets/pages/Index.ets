
import router from '@ohos.router';

interface TabItemType  {
  title: string;
  icon: Resource;
  selectedIcon: Resource;
}

interface FeedItemType  {
  id: number;
  type: string;
  url: Resource;
  username: string;
  avatar: Resource;
  description: string;
  likes: number;
  comments: number;
  isLiked?: boolean;
  commentsList?: string[];
}


interface GeneratedObjectLiteralInterface_1 {
  username: string;
  avatar: Resource;
}

@Entry
@Component
struct SocialMediaMain {
  // 当前选中的Tab页签索引
  @State currentTabIndex: number = 0;
  @State currentTitle: string = '首页';
  @State showGlobalImagePreview: boolean = false;
  @State previewImageUrl: Resource = $r('app.media.background');
  @State myWorks: Array<FeedItemType> = [];

  // Tab数据模型
  private tabItems: Array<TabItemType> = [
    { title: '首页', icon: $r('app.media.home'), selectedIcon: $r('app.media.home_selected') },
    { title: '分类', icon: $r('app.media.classify'), selectedIcon: $r('app.media.classify_selected') },
    { title: '发布', icon: $r('app.media.publish'), selectedIcon: $r('app.media.publish_selected') },
    { title: 'AI识图', icon: $r('app.media.ai'), selectedIcon: $r('app.media.ai_selected')},
    { title: '我', icon: $r('app.media.me'), selectedIcon: $r('app.media.me_selected') }
  ];

  // 模拟内容数据（图片/视频缩略图）
  @State feedData: Array<FeedItemType> = [
    { id: 1, type: 'image', url: $r('app.media.nai'), username: '旅行达人', avatar: $r('app.media.nai'), description: '今日份夕阳美景 ', likes: 128, comments: 23, isLiked: false, commentsList: ['太美了！', '在哪里拍的？', '好想去']},
    { id: 2, type: 'video', url: $r('app.media.background'), username: '美食侦探', avatar: $r('app.media.nai'), description: '街头小吃大合集 ', likes: 256, comments: 45, isLiked: false, commentsList: ['想吃！', '地址在哪里？']},
    { id: 3, type: 'image', url: $r('app.media.background'), username: '城市记录者', avatar: $r('app.media.nai'), description: '雨后城市的倒影', likes: 89, comments: 12, isLiked: false, commentsList: ['想吃！', '地址在哪里？']},
    { id: 4, type: 'video', url: $r('app.media.background'), username: '萌宠日记', avatar: $r('app.media.nai'), description: '小猫咪的日常 ', likes: 512, comments: 67, isLiked: false, commentsList: ['想吃！', '地址在哪里？']},
    { id: 5, type: 'image', url: $r('app.media.background'), username: '艺术爱好者', avatar: $r('app.media.nai'), description: '街头涂鸦艺术 ', likes: 175, comments: 31, isLiked: false, commentsList: ['想吃！', '地址在哪里？']},
    { id: 6, type: 'image', url: $r('app.media.background'), username: '自然风光', avatar: $r('app.media.nai'), description: '山间晨雾', likes: 342, comments: 54, isLiked: false, commentsList: ['想吃！', '地址在哪里？']}
  ];

  // 底部Tab组件高度（参考抖音风格，更高一些）
  private tabBarHeight: number = 72;
  handleImageClick(imageUrl: Resource) {
    this.previewImageUrl = imageUrl;
    this.showGlobalImagePreview = true;
  }
  private currentUser: GeneratedObjectLiteralInterface_1 = {
    username: '我',
    avatar: $r('app.media.nai')
  };
  handlePublish(description: string, imageUrl: Resource) {
    const newPost: FeedItemType = {
      id: this.feedData.length + 1,
      type: 'image',
      url: imageUrl || $r('app.media.nai'),
      username: this.currentUser.username,
      avatar: this.currentUser.avatar,
      description: description || '分享我的生活',
      likes: 0,
      comments: 0,
      isLiked: false,
      commentsList: []
    };

    this.feedData = [newPost, ...this.feedData];
    this.myWorks = [newPost, ...this.myWorks];
    this.currentTabIndex = 0;
    this.currentTitle = '首页';
  }
  build() {
    Stack(){
    Column() {
      // 主要内容区域（不同Tab展示不同内容）
      Stack() {
        // 首页Tab - 图片/视频瀑布流（参考微信朋友圈）
        if (this.currentTabIndex === 0) {
          FeedList({ feedData: this.feedData, onImageClick: (url: Resource): void => this.handleImageClick(url) })
        }
        // AI识图Tab - 展示AI识别功能界面（UI设计示意）
        if (this.currentTabIndex === 1) {
          CategoryView()
        }
        // 发布Tab - 发布内容界面（UI设计示意）
        if (this.currentTabIndex === 2) {
          PublishView({ onPublish: (description: string, imageUrl: Resource): void => this.handlePublish(description,
            imageUrl) })
        }
        // 分类Tab - 内容分类浏览（UI设计示意）
        if (this.currentTabIndex === 3) {
          AICameraView()
        }
        // 我Tab - 个人主页（UI设计示意）
        if (this.currentTabIndex === 4) {
          ProfileView({ myWorks: this.myWorks })
        }
      }
      .layoutWeight(1)

      // 底部Tab组件（参考抖音底部Tab风格 - 大图标+文字）
      Row() {
        ForEach(this.tabItems, (item: TabItemType, index: number) => {
          Column() {
            Image(this.currentTabIndex === index ? item.selectedIcon : item.icon)
              .width(28)
              .height(28)
              .objectFit(ImageFit.Contain)
              .margin({ bottom: 2 })
            Text(item.title)
              .fontSize(11)
              .fontColor(this.currentTabIndex === index ? '#FFD700' : '#AAAAAA')
              .fontWeight(this.currentTabIndex === index ? FontWeight.Medium : FontWeight.Normal)
          }
          .width('20%')
          .height(this.tabBarHeight)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.currentTabIndex = index;
            this.currentTitle = item.title;
          })
        })
      }
      .width('100%')
      .height(this.tabBarHeight)
      .backgroundColor('#1A1A2E')
      .padding({ top: 6, bottom: 6 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
      if (this.showGlobalImagePreview) {
        Stack() {
          // 半透明背景
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0, 0, 0, 0.9)')
            .onClick(() => {
              this.showGlobalImagePreview = false;
            })

          // 放大的图片
          Image(this.previewImageUrl)
            .width('90%')
            .height('70%')
            .objectFit(ImageFit.Contain)
            .borderRadius(8)

          // 关闭按钮
          Text('✕')
            .fontSize(30)
            .fontColor(Color.White)
            .position({ x: '90%', y: '5%' })
            .onClick(() => {
              this.showGlobalImagePreview = false;
            })
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(999)
      }
    }
    .width('100%')
    .height('100%')
  }
}

// ================== 首页 - 朋友圈风格列表 ==================

@Component
struct FeedList {
  @Prop feedData: Array<FeedItemType>;
  onImageClick: (url: Resource) => void = () => {};

  build() {
    List() {
      ForEach(this.feedData, (item: FeedItemType) => {
        ListItem() {
          FeedItem({ feed: item, onImageClick: this.onImageClick })
        }
        .margin({ bottom: 10 })
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 10 })
    .backgroundColor('#F5F5F5')
  }
}

// 单条朋友圈内容（含图片/视频缩略图）

@Component
struct FeedItem {
  @Prop feed: FeedItemType;
  onImageClick: (url: Resource) => void = () => {};
  @State isLiked: boolean = false;
  @State likeCount: number = 0;
  @State showCommentInput: boolean = false;
  @State commentText: string = '';
  @State commentsList: string[] = [];

  aboutToAppear() {
    this.isLiked = this.feed.isLiked || false;
    this.likeCount = this.feed.likes;
    //this.commentCount = this.feed.comments;
    this.commentsList = this.feed.commentsList || [];
  }
  build() {
    Column() {
      // 用户信息行
      Row() {
        Image(this.feed.avatar)
          .width(44)
          .height(44)
          .borderRadius(22)
          .margin({ right: 12 })
        Column() {
          Text(this.feed.username)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
          Text('2小时前')
            .fontSize(12)
            .fontColor('#999999')
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12 })

      // 描述文字
      Text(this.feed.description)
        .fontSize(15)
        .fontColor('#444444')
        .padding({ left: 12, right: 12, top: 8 })
        .width('100%')

      // 图片/视频内容（模拟缩略图）
      Stack() {
        if (this.feed.type === 'image') {
          Image(this.feed.url)
            .width('100%')
            .height(200)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .margin({ top: 8 })
            .backgroundColor('#E0E0E0')
            .onClick(() => {
              // 点击图片，显示放大预览
              this.onImageClick(this.feed.url);
            })
        } else {
          // 视频播放器占位（模拟）
          Image(this.feed.url)
            .width('100%')
            .height(200)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .margin({ top: 8 })
            .backgroundColor('#1A1A2E')
            .onClick(() => {
              // 点击视频，显示放大预览
              this.onImageClick(this.feed.url);
            })
          // 视频播放按钮（模拟）
          Image($r('app.media.background'))
            .width(48)
            .height(48)
            .position({ x: '50%', y: '50%' })
            .translate({ x: -24, y: -24 })
            .fillColor(Color.White)
        }
      }

      // 互动区域（点赞）
      Row() {
        Row() {
          Image(this.isLiked ? $r('app.media.good_selected') : $r('app.media.good'))
            .width(20)
            .height(20)
            .fillColor('#FF6B6B')
          Text(this.likeCount.toString())
            .fontSize(13)
            .fontColor(this.isLiked ? '#FF0000' : '#666666')
            .margin({ left: 4 })
        }
        .margin({ right: 16 })
        .onClick(() => { // 添加点击事件
          this.isLiked = !this.isLiked;
          this.likeCount = this.isLiked ? this.likeCount + 1 : this.likeCount - 1;
        })

        // 互动区域（评论）
        Row() {
          Image($r('app.media.comment'))
            .width(20)
            .height(20)
            .fillColor('#666666')
          Text(this.commentsList.length.toString())
            .fontSize(13)
            .fontColor('#666666')
            .margin({ left: 4 })
        }
        .onClick(() => { // 点击评论
          this.showCommentInput = !this.showCommentInput;
          // 如果关闭输入框，清空评论内容
          if (!this.showCommentInput) {
            this.commentText = '';
          }
        })

        Blank()
      }
      .width('100%')
      .padding({
        left: 12,
        right: 12,
        top: 10,
        bottom: 12
      })
      .backgroundColor(Color.White)

      if (this.showCommentInput) {
        Column() {
          // 显示已有评论
          if (this.commentsList.length > 0) {
            Column() {
              Text('评论列表 (' + this.commentsList.length + ')')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333')
                .width('100%')
                .margin({ bottom: 8 })

              ForEach(this.commentsList, (comment: string, index: number) => {
                Row() {
                  Text((index + 1) + '. ')
                    .fontSize(13)
                    .fontColor('#999999')
                  Text(comment)
                    .fontSize(14)
                    .fontColor('#333333')
                }
                .width('100%')
                .padding({ top: 4, bottom: 4 })
                .margin({ bottom: 4 })
              })
            }
            .width('100%')
            .padding({ bottom: 12 })
          } else {
            // 没有评论时
            Text('暂无评论，来说点什么吧...')
              .fontSize(14)
              .fontColor('#999999')
              .width('100%')
              .padding({ bottom: 12 })
              .textAlign(TextAlign.Center)
          }

          // 评论输入框（参考发布页面的样式）
          Row() {
            TextInput({ placeholder: '说点什么...', text: this.commentText })
              .width('75%')
              .height(40)
              .backgroundColor('#F5F5F5')
              .borderRadius(20)
              .padding({ left: 16, right: 16 })
              .fontSize(14)
              .placeholderColor('#AAAAAA')
              .onChange((value: string) => {
                this.commentText = value;
              })

            Button('发送')
              .width('20%')
              .height(40)
              .backgroundColor('#FFD700')
              .fontColor('#1A1A2E')
              .borderRadius(20)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .onClick(() => {
                if (this.commentText.trim() !== '') {
                  // 添加评论
                  this.commentsList.push(this.commentText.trim());
                  // 清空输入框
                  this.commentText = '';
                  // 显示成功提示
                  console.log('评论成功！当前评论数：' + this.commentsList.length);
                }
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ top: 8, bottom: 8 })
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12 })
        .backgroundColor('#FAFAFA')
        .borderRadius({ bottomLeft: 12, bottomRight: 12 })
      }
    }
    .width('100%')
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({
      radius: 4,
      color: 'rgba(0, 0, 0, 0.05)',
      offsetX: 0,
      offsetY: 2
    })
  }
}

// ================== AI识图Tab ==================
@Component
struct AICameraView {
  build() {
    Column() {
      // 识别区域（模拟相机取景框）
      Stack() {
        Image($r('app.media.background'))
          .width('90%')
          .height(300)
          .borderRadius(16)
          .backgroundColor('#2D2D44')
          .objectFit(ImageFit.Cover)

        // 扫描框动画（UI示意）
        Column() {
          Text('🔍')
            .fontSize(50)
            .margin({ bottom: 10 })
          Text('对准物体，AI将自动识别')
            .fontSize(16)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
          Text('支持植物、动物、商品等')
            .fontSize(13)
            .fontColor('rgba(255,255,255,0.7)')
            .margin({ top: 6 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height(300)
      .padding({ top: 20, bottom: 20 })
      // 功能按钮
      Row() {
        Button('相册选择')
          .width(120)
          .height(44)
          .backgroundColor('#FFD700')
          .fontColor('#1A1A2E')
          .borderRadius(22)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
        Button('拍照识别')
          .width(120)
          .height(44)
          .backgroundColor('#1A1A2E')
          .fontColor(Color.White)
          .borderRadius(22)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 20 })
      }

      // 历史识别记录（示例）
      Column() {
        Text('最近识别')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .width('90%')
          .margin({ top: 24, bottom: 10 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8FC')
  }
}

// ================== 发布Tab ==================
@Component
struct PublishView {
  @State description: string = '';
  @State selectedImage: Resource = $r('app.media.nai');
  @State hasSelectedImage: boolean = false;
  @State isPressed1: boolean = false;
  @State isPressed2: boolean = false;
  onPublish: (description: string, imageUrl: Resource) => void = () => {};
  build() {
    Column() {
      // 发布内容区域
      Column() {
        // 文本输入区（模拟）
        Column() {
          TextArea({ placeholder: '分享你的想法...', text: this.description })
            .width('100%')
            .height(120)
            .backgroundColor('#F5F5F5')
            .borderRadius(12)
            .padding(12)
            .fontSize(16)
            .placeholderColor('#AAAAAA')
            .onChange((value: string) => {
              this.description = value;
            })
        }
        .width('90%')
        .margin({ top: 20 })

        // 添加媒体（图片/视频）
        Row() {
          Stack() {
            if (this.hasSelectedImage) {
              Image(this.selectedImage)
                .width(80)
                .height(80)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
            } else {
              Column() {
                Text('+')
                  .fontSize(30)
                  .fontColor('#FFFFFF')
                  .fontWeight(FontWeight.Bold)
                Text('添加图片')
                  .fontSize(12)
                  .fontColor('#FFFFFF')
                  .margin({ top: 4 })
              }
              .width(80)
              .height(80)
              .backgroundColor('#D0D0D0')
              .borderRadius(8)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
          }
          .margin({ right: 10 })
          .onClick(() => {
            // 模拟选择图片（实际开发中调用相册选择）
            this.hasSelectedImage = !this.hasSelectedImage;
          })
        }
        .width('90%')
        .justifyContent(FlexAlign.Start)
        .margin({ top: 16 })

        // 位置与可见性

        Row() {
          Button({ type: ButtonType.Circle })
            .width(20)
            .height(20)
            .backgroundColor(this.isPressed1 ? '#FF0000' : '#FFD700')  // 点击后变红
            .onClick(() => {
              this.isPressed1 = !this.isPressed1;  // 切换状态
            })
          Text('添加位置')
            .fontSize(15)
            .fontColor('#666666')
            .margin({ left: 8 })
          Blank()
          Button({ type: ButtonType.Circle })
            .width(20)
            .height(20)
            .backgroundColor(this.isPressed2 ? '#FF0000' : '#FFD700')  // 点击后变红
            .onClick(() => {
              this.isPressed2 = !this.isPressed2;  // 切换状态
            })
          Text('公开')
            .fontSize(15)
            .fontColor('#666666')
            .margin({ left: 8 })
        }
        .width('90%')
        .padding({ top: 16, bottom: 16 })
        .borderWidth({ bottom: 1 })
        .borderColor('#EEEEEE')

        // 发布按钮
        Button('发布')
          .onClick(() => {
            this.onPublish(this.description, this.selectedImage);
            // 清空表单
            this.description = '';
            this.hasSelectedImage = false;
          })
          .width('90%')
          .height(50)
          .backgroundColor('#FFD700')
          .fontColor('#1A1A2E')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .borderRadius(25)
          .margin({ top: 24 })
      }
      .width('100%')
      .backgroundColor(Color.White)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .shadow({
        radius: 8,
        color: 'rgba(0, 0, 0, 0.06)',
        offsetY: -4
      })
      .padding({ bottom: 20 })

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8FC')
  }
}

// ================== 分类Tab ==================
interface CategoryItemType {
  name: string;
  icon: Resource;  // 图片资源
}
// 照片数据类型
interface PhotoItemType {
  id: number;
  image: Resource;
}
// 分类照片数据
interface CategoryPhotosType {
  categoryName: string;
  photos: Array<PhotoItemType>;
}
interface HotTagType {
  tag: string;
  category: string;
}

@Component
struct CategoryView {
  @State selectedCategory: string = ''; // 选中的分类
  @State showPhotos: boolean = false; // 是否显示照片列表

  private categories: Array<CategoryItemType> = [
    { name: '推荐', icon: $r('app.media.recommend') },
    { name: '旅行', icon: $r('app.media.travel') },
    { name: '美食', icon: $r('app.media.food') },
    { name: '摄影', icon: $r('app.media.photography') },
    { name: '时尚', icon: $r('app.media.fashion') },
    { name: '科技', icon: $r('app.media.technology') },
    { name: '宠物', icon: $r('app.media.pet') },
    { name: '艺术', icon: $r('app.media.art') }
  ];
  private hotTags: HotTagType[] = [
    { tag: '#城市记忆', category: '摄影' },
    { tag: '#美食探店', category: '美食' },
    { tag: '#旅行日记', category: '旅行' },
    { tag: '#摄影日常', category: '摄影' },
    { tag: '#宠物生活', category: '宠物' },
    { tag: '#时尚穿搭', category: '时尚' }
  ];
  private categoryPhotos: Array<CategoryPhotosType> = [
    {
      categoryName: '推荐',
      photos: [
        { id: 1, image: $r('app.media.nai')},
        { id: 2, image: $r('app.media.nai')},
        { id: 3, image: $r('app.media.nai')},
        { id: 4, image: $r('app.media.nai')},
        { id: 5, image: $r('app.media.nai')},
        { id: 6, image: $r('app.media.nai')}
      ]
    },
    {
      categoryName: '旅行',
      photos: [
        { id: 1, image: $r('app.media.nai')},
        { id: 2, image: $r('app.media.nai')},
        { id: 3, image: $r('app.media.nai')},
        { id: 4, image: $r('app.media.nai')}
      ]
    },
    {
      categoryName: '美食',
      photos: [
        { id: 1, image: $r('app.media.nai')},
        { id: 2, image: $r('app.media.nai')},
        { id: 3, image: $r('app.media.nai')}
      ]
    },
    // 为其他分类也添加数据...
    {
      categoryName: '摄影',
      photos: [
        { id: 1, image: $r('app.media.nai')},
        { id: 2, image: $r('app.media.nai')}
      ]
    },
    {
      categoryName: '时尚',
      photos: [
        { id: 1, image: $r('app.media.nai')},
        { id: 2, image: $r('app.media.nai')}
      ]
    },
    {
      categoryName: '科技',
      photos: [
        { id: 1, image: $r('app.media.nai')},
        { id: 2, image: $r('app.media.nai')}
      ]
    },
    {
      categoryName: '宠物',
      photos: [
        { id: 1, image: $r('app.media.nai')},
        { id: 2, image: $r('app.media.nai')}
      ]
    },
    {
      categoryName: '艺术',
      photos: [
        { id: 1, image: $r('app.media.nai')},
        { id: 2, image: $r('app.media.nai')}
      ]
    }
  ];
  getCurrentPhotos(): Array<PhotoItemType> {
    const category = this.categoryPhotos.find(item => item.categoryName === this.selectedCategory);
    return category ? category.photos : [];
  }
  handleTagClick(tag: string) {
    const tagData = this.hotTags.find(item => item.tag === tag);
    if (tagData) {
      this.selectedCategory = tagData.category;
      this.showPhotos = true;
    }
  }

  build() {
    Column() {
      // 分类网格（图标+文字，模拟）
      if (!this.showPhotos) {
        Grid() {
          ForEach(this.categories, (category: CategoryItemType, index: number) => {
            GridItem() {
              Column() {
                Image(category.icon)
                  .width(56)
                  .height(56)
                  .borderRadius(28)  // 圆形裁剪
                  .objectFit(ImageFit.Cover)
                  .margin({ bottom: 8 })
                Text(category.name)
                  .fontSize(14)
                  .fontColor('#333333')
              }
              .width('100%')
              .height(100)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                // 点击分类，跳转到照片列表
                this.selectedCategory = category.name;
                this.showPhotos = true;
              })
            }
          })
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsGap(12)
        .columnsGap(12)
        .width('90%')
        .height(220)
        .padding(8)

        // 热门标签
        Column() {
          Text('热门标签')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A2E')
            .width('100%')
            .margin({ top: 20, bottom: 12 })

          Row() {
            ForEach(this.hotTags, (tagItem: HotTagType, index: number) => {
              Text(tagItem.tag)
                .fontSize(13)
                .fontColor('#666666')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor('#F0F0F0')
                .borderRadius(16)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.handleTagClick(tagItem.tag);
                })
            })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Blank()
      } else {
        // 显示照片列表页面
        Column() {
          // 顶部导航栏
          Row() {
            // 返回按钮
            Image($r('app.media.arrow_left'))  // 需要准备返回图标
              .width(24)
              .height(24)
              .onClick(() => {
                this.showPhotos = false;
                this.selectedCategory = '';
              })
              .margin({ right: 12 })

            Text(this.selectedCategory)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1A1A2E')
              .layoutWeight(1)

            Blank()
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 12,
            bottom: 12
          })
          .backgroundColor(Color.White)

          // 照片网格
          Grid() {
            ForEach(this.getCurrentPhotos(), (photo: PhotoItemType) => {
              GridItem() {
                Column() {
                  Image(photo.image)
                    .width('100%')
                    .aspectRatio(1)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(8)
                    .backgroundColor('#E8E8E8')
                }
                .width('100%')
              }
            })
          }
          .columnsTemplate('1fr 1fr 1fr')
          .rowsGap(12)
          .columnsGap(12)
          .width('95%')
          .padding({ top: 12, bottom: 12 })
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F8F8FC')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8FC')
    .alignItems(HorizontalAlign.Center)
  }
}

// ================== 我 Tab（个人主页） ==================
@Component
struct ProfileView {
  @Prop myWorks: Array<FeedItemType> = [];
  onViewPost: (post: FeedItemType) => void = () => {};
  build() {
    Column() {
      // 头部背景
      Column() {
        // 用户信息
        Row() {
          Image($r('app.media.background'))
            .width(72)
            .height(72)
            .borderRadius(36)
            .border({ width: 2, color: Color.White })
            .margin({ right: 16 })
          Column() {
            Text('用户名')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text('个人简介 ✨ 热爱生活')
              .fontSize(14)
              .fontColor('rgba(255,255,255,0.8)')
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Image($r('app.media.arrow_right'))
            .width(24)
            .height(24)
            .fillColor(Color.White)
        }
        .width('90%')
        .padding({ top: 30, bottom: 20 })

        // 统计数据
        Row() {
          Column() {
            Text('128')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text('关注')
              .fontSize(13)
              .fontColor('rgba(255,255,255,0.7)')
          }
          .margin({ right: 30 })

          Column() {
            Text('256')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text('粉丝')
              .fontSize(13)
              .fontColor('rgba(255,255,255,0.7)')
          }
          .margin({ right: 30 })

          Column() {
            Text('89')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text('获赞')
              .fontSize(13)
              .fontColor('rgba(255,255,255,0.7)')
          }
        }
        .width('90%')
        .padding({ bottom: 24 })
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .backgroundColor('#1A1A2E')
      .borderRadius({ bottomLeft: 24, bottomRight: 24 })

      // 作品列表（模拟）
      Column() {
        Row() {
          Text('我的作品')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A2E')
          Blank()
          Text('查看全部 >')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('90%')
        .margin({ top: 20, bottom: 12 })

        Grid() {
          if (this.myWorks.length > 0){
            ForEach(this.myWorks, (post: FeedItemType, index: number) => {
              GridItem() {
                Image(post.url)
                  .width('100%')
                  .aspectRatio(1)
                  .borderRadius(8)
                  .backgroundColor('#E8E8E8')
              }
              .onClick(() => {
                this.onViewPost(post);
              })
            })
          }else{
            GridItem() {
              Column() {
                Text('📷')
                  .fontSize(40)
                  .margin({ bottom: 8 })
                Text('暂无作品')
                  .fontSize(14)
                  .fontColor('#999999')
              }
              .width('100%')
              .aspectRatio(1)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .backgroundColor('#F5F5F5')
              .borderRadius(8)
            }
          }
        }
        .columnsTemplate('1fr 1fr 1fr')
        .rowsGap(12)
        .columnsGap(12)
        .width('90%')
        .padding({ bottom: 12 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
  }
}