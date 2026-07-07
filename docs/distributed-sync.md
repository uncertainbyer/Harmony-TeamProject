# 分布式同步功能说明

## 功能范围

- 使用 `distributedDeviceManager` 搜索同一局域网中的 HarmonyOS 设备。
- 对未建立信任关系的设备发起 PIN 授权绑定。
- 使用 ArkData `distributedDataObject` 同步帖子文本、分类、点赞、评论和删除状态。
- 图片先复制到应用的 `distributedFilesDir`，再作为 Asset 随同步批次传输。
- 接收端将远端数据合并到本地 RDB，并通过事件总线通知页面立即刷新。
- 新设备连接时执行一次全量同步；日常发布、评论和修改只发送增量数据。

## 同步链路

```text
设备A发布帖子/评论
        ↓
PostService / CommentService 发出同步信号
        ↓
DistributedService 收集 sync_status=0 的数据
        ↓
固定控制会话发布批次ID
        ↓
独立批次会话传输 JSON + 图片 Asset
        ↓
设备B接收、冲突判断、写入本地 RDB
        ↓
SyncEventBus 通知页面重新查询
        ↓
设备B立即看到相同帖子、图片和评论
```

## 双真机演示步骤

1. 在 DevEco Studio 中为项目配置有效的调试签名，保证两台设备安装的是相同 bundleName 和相同版本应用。
2. 两台 HarmonyOS 真机打开开发者模式，连接到同一个局域网。
3. 在设备 A、设备 B 上分别启动应用并授予“分布式数据同步”权限。
4. 在设备 A 点击“搜索设备”，在设备列表中点击设备 B 的“连接”。
5. 根据系统提示在两端确认授权或输入 PIN，页面显示“已连接，可自动同步”。
6. 在设备 A 选择图片、输入文字，点击“发布并同步”。
7. 设备 B 收到批次后会自动落库并刷新，无需手动点击刷新。
8. 在设备 B 对最新帖子发表评论，设备 A 应自动显示相同评论。

## 运行条件

- HarmonyOS 6.1.0 / API 23 SDK。
- 真机具备 `SystemCapability.DistributedHardware.DeviceManager` 和
  `SystemCapability.DistributedDataManager.DataObject.DistributedObject`。
- 两台设备处于同一局域网，且系统允许附近设备发现。
- `module.json5` 已声明 `ohos.permission.DISTRIBUTED_DATASYNC`。
- 分布式设备发现和 Asset 传输应使用真机验证，模拟器不能代表实际组网效果。

## 数据一致性策略

- 帖子以 `postId` 为主键，优先保留 `updateTime` 较新的版本。
- 评论以 `commentId` 为主键；本机尚未同步的评论修改不会被远端旧数据覆盖。
- 远端写入统一标记为 `sync_status=1`，避免接收后再次立即回传。
- 删除采用软删除并同步 `isDeleted`，因此另一台设备也会隐藏对应数据。
- 新设备连接后发送全量快照，避免只收到连接后的新内容。

## 关键代码

- `entry/src/main/ets/service/DistributedService.ets`：设备发现、绑定、控制会话、批次和图片同步。
- `entry/src/main/ets/distributed/SyncProtocol.ets`：同步协议和数据转换。
- `entry/src/main/ets/distributed/SyncEventBus.ets`：业务触发与接收端刷新通知。
- `entry/src/main/ets/pages/TestPage.ets`：双设备演示界面。

