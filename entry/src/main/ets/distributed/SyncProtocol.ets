import { commonType } from '@kit.ArkData';
import { PostModel } from '../model/PostModel';
import { CommentModel } from '../model/CommentModel';

export const SYNC_PROTOCOL_VERSION: number = 1;
export const CONTROL_SESSION_ID: string = 'SOCIAL_PHOTO_CONTROL_V1';
export const ASSET_PREFIX: string = 'asset://';

/** 固定控制会话中只传输一个原子公告字段。 */
export class SyncControlState {
  announcementJson: string = '';
}

/** 每个批次使用独立会话，文本与图片资产一起传输。 */
export class SyncTransferState {
  envelopeJson: string = '';
  images: commonType.Assets = [];
}

export class SyncAnnouncement {
  protocolVersion: number = SYNC_PROTOCOL_VERSION;
  batchId: string = '';
  sourceDeviceId: string = '';
  expectedAssetCount: number = 0;
  sentAt: number = 0;
}

export class SyncPostData {
  postId: string = '';
  userId: string = '';
  userName: string = '';
  userAvatar: string = '';
  content: string = '';
  imagePaths: string[] = [];
  categoryId: string = '';
  categoryName: string = '';
  likeCount: number = 0;
  commentCount: number = 0;
  createTime: number = 0;
  updateTime: number = 0;
  deviceId: string = '';
  isDeleted: boolean = false;

  static fromModel(post: PostModel): SyncPostData {
    const data: SyncPostData = new SyncPostData();
    data.postId = post.postId;
    data.userId = post.userId;
    data.userName = post.userName;
    data.userAvatar = post.userAvatar;
    data.content = post.content;
    data.imagePaths = post.getImagePathArray();
    data.categoryId = post.categoryId;
    data.categoryName = post.categoryName;
    data.likeCount = post.likeCount;
    data.commentCount = post.commentCount;
    data.createTime = post.createTime;
    data.updateTime = post.updateTime;
    data.deviceId = post.deviceId;
    data.isDeleted = post.isDeleted;
    return data;
  }

  toModel(assetPathMap: Map<string, string>): PostModel {
    const post: PostModel = new PostModel();
    post.postId = this.postId;
    post.userId = this.userId;
    post.userName = this.userName;
    post.userAvatar = this.userAvatar;
    post.content = this.content;
    const resolvedPaths: string[] = [];
    for (let i: number = 0; i < this.imagePaths.length; i++) {
      const path: string = this.imagePaths[i];
      if (path.startsWith(ASSET_PREFIX)) {
        const assetName: string = path.substring(ASSET_PREFIX.length);
        const localPath: string | undefined = assetPathMap.get(assetName);
        if (localPath !== undefined) {
          resolvedPaths.push(localPath);
        }
      } else {
        resolvedPaths.push(path);
      }
    }
    post.setImagePathArray(resolvedPaths);
    post.categoryId = this.categoryId;
    post.categoryName = this.categoryName;
    post.likeCount = this.likeCount;
    post.commentCount = this.commentCount;
    post.createTime = this.createTime;
    post.updateTime = this.updateTime;
    post.deviceId = this.deviceId;
    post.syncStatus = 1;
    post.isDeleted = this.isDeleted;
    return post;
  }
}

export class SyncCommentData {
  commentId: string = '';
  postId: string = '';
  userId: string = '';
  userName: string = '';
  userAvatar: string = '';
  content: string = '';
  parentId: string = '';
  replyToUserId: string = '';
  replyToUserName: string = '';
  level: number = 1;
  likeCount: number = 0;
  createTime: number = 0;
  deviceId: string = '';
  isDeleted: boolean = false;

  static fromModel(comment: CommentModel): SyncCommentData {
    const data: SyncCommentData = new SyncCommentData();
    data.commentId = comment.commentId;
    data.postId = comment.postId;
    data.userId = comment.userId;
    data.userName = comment.userName;
    data.userAvatar = comment.userAvatar;
    data.content = comment.content;
    data.parentId = comment.parentId;
    data.replyToUserId = comment.replyToUserId;
    data.replyToUserName = comment.replyToUserName;
    data.level = comment.level;
    data.likeCount = comment.likeCount;
    data.createTime = comment.createTime;
    data.deviceId = comment.deviceId;
    data.isDeleted = comment.isDeleted;
    return data;
  }

  toModel(): CommentModel {
    const comment: CommentModel = new CommentModel();
    comment.commentId = this.commentId;
    comment.postId = this.postId;
    comment.userId = this.userId;
    comment.userName = this.userName;
    comment.userAvatar = this.userAvatar;
    comment.content = this.content;
    comment.parentId = this.parentId;
    comment.replyToUserId = this.replyToUserId;
    comment.replyToUserName = this.replyToUserName;
    comment.level = this.level;
    comment.likeCount = this.likeCount;
    comment.createTime = this.createTime;
    comment.deviceId = this.deviceId;
    comment.syncStatus = 1;
    comment.isDeleted = this.isDeleted;
    return comment;
  }
}

export class SyncEnvelope {
  protocolVersion: number = SYNC_PROTOCOL_VERSION;
  batchId: string = '';
  sourceDeviceId: string = '';
  sentAt: number = 0;
  posts: SyncPostData[] = [];
  comments: SyncCommentData[] = [];
}

