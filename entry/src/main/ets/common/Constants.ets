/**
 * 应用常量定义类
 * 存储应用中使用的各种常量
 */
export class Constants {
  /** 应用名称 */
  static readonly APP_NAME: string = 'SocialPhoto';

  /** 应用版本 */
  static readonly APP_VERSION: string = '1.0.0';

  /** 数据库名称 */
  static readonly DB_NAME: string = 'SocialPhoto.db';

  /** 数据库版本 */
  static readonly DB_VERSION: number = 1;

  /** 默认分页大小 */
  static readonly PAGE_SIZE: number = 20;

  /** 最大图片上传数量 */
  static readonly MAX_IMAGE_COUNT: number = 9;

  /** 图片最大尺寸（像素） */
  static readonly MAX_IMAGE_SIZE: number = 4096;

  /** 图片压缩质量（0-100） */
  static readonly IMAGE_QUALITY: number = 80;

  /** 网络请求超时时间（毫秒） */
  static readonly NETWORK_TIMEOUT: number = 30000;

  /** 连接超时时间（毫秒） */
  static readonly CONNECT_TIMEOUT: number = 10000;

  /** 读取超时时间（毫秒） */
  static readonly READ_TIMEOUT: number = 60000;

  /** Toast显示时长（毫秒） */
  static readonly TOAST_DURATION: number = 2000;

  /** 动画时长（毫秒） */
  static readonly ANIMATION_DURATION: number = 300;
}

/**
 * 分类相关常量
 */
export class CategoryConstants {
  /** 风景分类ID */
  static readonly SCENERY: string = 'cat_scenery';

  /** 人物分类ID */
  static readonly PERSON: string = 'cat_person';

  /** 美食分类ID */
  static readonly FOOD: string = 'cat_food';

  /** 动物分类ID */
  static readonly ANIMAL: string = 'cat_animal';

  /** 建筑分类ID */
  static readonly BUILDING: string = 'cat_building';

  /** 其他分类ID */
  static readonly OTHER: string = 'cat_other';
}

/**
 * 同步状态常量
 */
export class SyncConstants {
  /** 未同步 */
  static readonly UNSYNCED: number = 0;

  /** 已同步 */
  static readonly SYNCED: number = 1;

  /** 同步中 */
  static readonly SYNCING: number = 2;

  /** 同步失败 */
  static readonly FAILED: number = 3;
}

/**
 * 错误码常量
 */
export class ErrorCode {
  /** 成功 */
  static readonly SUCCESS: number = 0;

  /** 网络错误 */
  static readonly NETWORK_ERROR: number = 1001;

  /** 数据库错误 */
  static readonly DB_ERROR: number = 1002;

  /** 文件错误 */
  static readonly FILE_ERROR: number = 1003;

  /** 参数错误 */
  static readonly PARAM_ERROR: number = 1004;

  /** 权限错误 */
  static readonly PERMISSION_ERROR: number = 1005;

  /** 服务器错误 */
  static readonly SERVER_ERROR: number = 2001;

  /** 数据不存在 */
  static readonly DATA_NOT_FOUND: number = 2002;

  /** 数据已存在 */
  static readonly DATA_EXISTS: number = 2003;
}

/**
 * 存储键常量
 */
export class StorageKey {
  /** 用户ID */
  static readonly USER_ID: string = 'user_id';

  /** 用户昵称 */
  static readonly USER_NAME: string = 'user_name';

  /** 用户头像 */
  static readonly USER_AVATAR: string = 'user_avatar';

  /** 设备ID */
  static readonly DEVICE_ID: string = 'device_id';

  /** 登录状态 */
  static readonly IS_LOGGED_IN: string = 'is_logged_in';

  /** 最后同步时间 */
  static readonly LAST_SYNC_TIME: string = 'last_sync_time';

  /** 主题模式 */
  static readonly THEME_MODE: string = 'theme_mode';

  /** 语言设置 */
  static readonly LANGUAGE: string = 'language';
}

/**
 * AI 模型推理相关常量
 * 基于 MindSpore Lite + MobileNetV2 实现图像分类
 */
export class AIConstants {
  /** 模型文件名 */
  static readonly MODEL_NAME: string = 'mobilenetv2.ms';

  /** 模型输入高度 */
  static readonly MODEL_INPUT_HEIGHT: number = 224;

  /** 模型输入宽度 */
  static readonly MODEL_INPUT_WIDTH: number = 224;

  /** 数组缓冲区大小 */
  static readonly ARRAY_BUFFER_SIZE: number = 4096000;

  /** 最大缩放值 */
  static readonly MAX_ZOOM_VALUE: number = 256;

  /** 图像左上角裁剪 x 坐标 */
  static readonly CROP_X: number = 16;

  /** 图像左上角裁剪 y 坐标 */
  static readonly CROP_Y: number = 16;

  /** RGB 最大值 */
  static readonly RGB_MAX: number = 255;

  /** 一万（用于百分比转换） */
  static readonly TEN_THOUSAND: number = 10000;

  /** 返回的 Top-K 分类结果数 */
  static readonly TOP_K: number = 4;

  /** 均值（RGB 归一化） */
  static readonly MEANS: number[] = [0.485, 0.456, 0.406];

  /** 标准差（RGB 归一化） */
  static readonly STDS: number[] = [0.229, 0.224, 0.225];

  /** 置信度阈值（低于此值的分类结果归入"其他"） */
  static readonly CONFIDENCE_THRESHOLD: number = 0.3;

  /** ImageNet 分类标签名数组（与 MobileNetV2 模型输出对应） */
  static readonly LABELS_NAME_MAP: string[] = [
    'Herd', 'Safari', 'Bangle', 'Cushion', 'Countertop',
    'Prom', 'Branch', 'Sports', 'Sky', 'Community',
    'Wheel', 'Cola', 'Tuxedo', 'Flowerpot', 'Team',
    'Computer', 'Unicycle', 'Brig', 'Aerospace engineering', 'Scuba diving',
    'Goggles', 'Fruit', 'Badminton', 'Horse', 'Sunglasses',
    'Fun', 'Prairie', 'Poster', 'Flag', 'Speedboat',
    'Eyelash', 'Veil', 'Mobile phone', 'Wheelbarrow', 'Saucer',
    'Leather', 'Drawer', 'Paper', 'Pier', 'Waterfowl',
    'Tights', 'Rickshaw', 'Vegetable', 'Handrail', 'Ice',
    'Metal', 'Flower', 'Wing', 'Silverware', 'Event',
    'Skyline', 'Money', 'Comics', 'Handbag', 'Porcelain',
    'Rodeo', 'Curtain', 'Tile', 'Human mouth', 'Army',
    'Menu', 'Boat', 'Snowboarding', 'Cairn terrier', 'Net',
    'Pasteles', 'Cup', 'Rugby', 'Pho', 'Cap',
    'Human hair', 'Surfing', 'Loveseat', 'Museum', 'Shipwreck',
    'Trunk (Tree)', 'Plush', 'Monochrome', 'Volcano', 'Rock',
    'Pillow', 'Presentation', 'Nebula', 'Subwoofer', 'Lake',
    'Sledding', 'Bangs', 'Tablecloth', 'Necklace', 'Swimwear',
    'Standing', 'Jeans', 'Carnival', 'Softball', 'Centrepiece',
    'Skateboarder', 'Cake', 'Dragon', 'Aurora', 'Skiing',
    'Bathroom', 'Dog', 'Needlework', 'Umbrella', 'Church',
    'Fire', 'Piano', 'Denim', 'Bridle', 'Cabinetry',
    'Lipstick', 'Ring', 'Television', 'Roller', 'Seal',
    'Concert', 'Product', 'News', 'Fast food', 'Horn (Animal)',
    'Tattoo', 'Bird', 'Bridegroom', 'Love', 'Helmet',
    'Dinosaur', 'Icing', 'Miniature', 'Tire', 'Toy',
    'Icicle', 'Jacket', 'Coffee', 'Mosque', 'Rowing',
    'Wetsuit', 'Camping', 'Underwater', 'Christmas', 'Gelato',
    'Whiteboard', 'Field', 'Ragdoll', 'Construction', 'Lampshade',
    'Palace', 'Meal', 'Factory', 'Cage', 'Clipper (Boat)',
    'Gymnastics', 'Turtle', 'Human foot', 'Marriage', 'Web page',
    'Human beard', 'Fog', 'Wool', 'Cappuccino', 'Lighthouse',
    'Lego', 'Sparkler', 'Sari', 'Model', 'Temple',
    'Beanie', 'Building', 'Waterfall', 'Penguin', 'Cave',
    'Stadium', 'Smile', 'Human hand', 'Park', 'Desk',
    'Shetland sheepdog', 'Bar', 'Eating', 'Neon', 'Dalmatian',
    'Crocodile', 'Wakeboarding', 'Longboard', 'Road', 'Race',
    'Kitchen', 'Odometer', 'Cliff', 'Fiction', 'School',
    'Interaction', 'Bullfighting', 'Boxer', 'Gown', 'Aquarium',
    'Superhero', 'Pie', 'Asphalt', 'Surfboard', 'Cheeseburger',
    'Screenshot', 'Supper', 'Laugh', 'Lunch', 'Party ',
    'Glacier', 'Bench', 'Grandparent', 'Sink', 'Pomacentridae',
    'Blazer', 'Brick', 'Space', 'Backpacking', 'Stuffed toy',
    'Sushi', 'Glitter', 'Bonfire', 'Castle', 'Marathon',
    'Pizza', 'Beach', 'Human ear', 'Racing', 'Sitting',
    'Iceberg', 'Shelf', 'Vehicle', 'Pop music', 'Playground',
    'Clown', 'Car', 'Rein', 'Fur', 'Musician',
    'Casino', 'Baby', 'Alcohol', 'Strap', 'Reef',
    'Balloon', 'Outerwear', 'Cathedral', 'Competition', 'Joker',
    'Blackboard', 'Bunk bed', 'Bear', 'Moon', 'Archery',
    'Polo', 'River', 'Fishing', 'Ferris wheel', 'Mortarboard',
    'Bracelet', 'Flesh', 'Statue', 'Farm', 'Desert',
    'Chain', 'Aircraft', 'Textile', 'Hot dog', 'Knitting',
    'Singer', 'Juice', 'Circus', 'Chair', 'Musical instrument',
    'Room', 'Crochet', 'Sailboat', 'Newspaper', 'Santa claus',
    'Swamp', 'Skyscraper', 'Skin', 'Rocket', 'Aviation',
    'Airliner', 'Garden', 'Ruins', 'Storm', 'Glasses',
    'Balance', 'Nail (Body part)', 'Rainbow', 'Soil ', 'Vacation ',
    'Moustache', 'Doily', 'Food', 'Bride ', 'Cattle',
    'Pocket', 'Infrastructure', 'Train', 'Gerbil', 'Fireworks',
    'Pet', 'Dam', 'Crew', 'Couch', 'Bathing',
    'Quilting', 'Motorcycle', 'Butterfly', 'Sled', 'Watercolor paint',
    'Rafting', 'Monument', 'Lightning', 'Sunset', 'Bumper',
    'Shoe', 'Waterskiing', 'Sneakers', 'Tower', 'Insect',
    'Pool', 'Placemat', 'Airplane', 'Plant', 'Jungle',
    'Armrest', 'Duck', 'Dress', 'Tableware', 'Petal',
    'Bus', 'Hanukkah', 'Forest', 'Hat', 'Barn',
    'Tubing', 'Snorkeling', 'Cool', 'Cookware and bakeware', 'Cycling',
    'Swing (Seat)', 'Muscle', 'Cat', 'Skateboard', 'Star',
    'Toe', 'Junk', 'Bicycle', 'Bedroom', 'Person',
    'Sand', 'Canyon', 'Tie', 'Twig', 'Sphynx',
    'Supervillain', 'Nightclub', 'Ranch', 'Pattern', 'Shorts',
    'Himalayan', 'Wall', 'Leggings', 'Windsurfing', 'Deejay',
    'Dance', 'Van', 'Bento', 'Sleep', 'Wine',
    'Picnic', 'Leisure', 'Dune', 'Crowd', 'Kayak',
    'Ballroom', 'Selfie', 'Graduation', 'Frigate', 'Mountain',
    'Dude', 'Windshield', 'Skiff', 'Class', 'Scarf',
    'Bull', 'Soccer', 'Bag', 'Basset hound', 'Tractor',
    'Swimming', 'Running', 'Track', 'Helicopter', 'Pitch',
    'Clock', 'Song', 'Jersey', 'Stairs', 'Flap',
    'Jewellery', 'Bridge', 'Cuisine', 'Bread', 'Caving',
    'Shell', 'Wreath', 'Roof', 'Cookie', 'Canoe',
  ];

  /**
   * 标签关键词 → App 分类 ID 映射规则
   * 用于将 MobileNetV2 细粒度标签归入 App 的 6 大分类
   */
  private static readonly CATEGORY_KEYWORDS: Record<string, string[]> = {
    'cat_scenery': [
      'Sky', 'Prairie', 'Skyline', 'Volcano', 'Lake', 'Nebula', 'Aurora',
      'Mountain', 'Field', 'Desert', 'Beach', 'River', 'Forest', 'Waterfall',
      'Canyon', 'Glacier', 'Iceberg', 'Cave', 'Cliff', 'Dune', 'Sunset',
      'Rainbow', 'Storm', 'Lightning', 'Fog', 'Garden', 'Moon', 'Star',
      'Space', 'Ocean', 'Sea', 'Reef', 'Swamp', 'Jungle', 'Ruins', 'Snow',
      'Icicle', 'Underwater', 'Sand', 'Himalayan', 'Ranch', 'Farm', 'Park',
      'Branch', 'Flower', 'Plant', 'Petal', 'Trunk (Tree)', 'Twig', 'Monochrome',
      'Safari', 'Herd', 'Dam', 'Soil', 'Vacation',
    ],
    'cat_person': [
      'Person', 'Crowd', 'Baby', 'Grandparent', 'Bride', 'Bridegroom', 'Dude',
      'Selfie', 'Smile', 'Human mouth', 'Human hair', 'Human beard', 'Human ear',
      'Human hand', 'Human foot', 'Nail (Body part)', 'Flesh', 'Skin', 'Muscle',
      'Toe', 'Eyelash', 'Bangs', 'Moustache', 'Tattoo', 'Army', 'Team',
      'Crew', 'Class', 'Graduation', 'Marriage', 'Prom', 'Party', 'Fun',
      'Concert', 'Carnival', 'Event', 'Competition', 'Superhero', 'Supervillain',
      'Clown', 'Joker', 'Musician', 'Singer', 'Deejay', 'Model', 'Dance',
      'Ballroom', 'Circus', 'Nightclub', 'Sitting', 'Standing', 'Sleep',
      'Laugh', 'Interaction', 'Selfie', 'Love', 'Community', 'Presentation',
      'Gymnastics', 'Scuba diving', 'Badminton', 'Snowboarding', 'Rugby',
      'Surfing', 'Skiing', 'Rowing', 'Swimming', 'Running', 'Cycling',
      'Rodeo', 'Bullfighting', 'Boxer', 'Archery', 'Marathon', 'Polo',
      'Soccer', 'Softball', 'Skateboarder', 'Skateboard', 'Sledding',
      'Wakeboarding', 'Windsurfing', 'Waterskiing', 'Snorkeling', 'Tubing',
      'Rafting', 'Kayak', 'Caving', 'Backpacking', 'Camping', 'Fishing',
      'Jersey', 'Bathing', 'Leisure', 'Picnic', 'Swing (Seat)',
    ],
    'cat_food': [
      'Food', 'Fruit', 'Vegetable', 'Meal', 'Cake', 'Bread', 'Cookie',
      'Pie', 'Pizza', 'Cheeseburger', 'Hot dog', 'Sandwich', 'Fast food',
      'Sushi', 'Bento', 'Pasteles', 'Pho', 'Supper', 'Lunch', 'Eating',
      'Cuisine', 'Coffee', 'Cappuccino', 'Gelato', 'Ice', 'Juice', 'Cola',
      'Wine', 'Alcohol', 'Cup', 'Saucer', 'Tableware', 'Silverware',
      'Menu', 'Placemat', 'Cookware and bakeware', 'Kitchen', 'Bar', 'Picnic',
      'Icing', 'Glitter', 'Candle', 'Bonfire', 'Centrepiece',
    ],
    'cat_animal': [
      'Horse', 'Dog', 'Cat', 'Bird', 'Bear', 'Fish', 'Cattle', 'Bull',
      'Duck', 'Turtle', 'Seal', 'Penguin', 'Butterfly', 'Insect', 'Dragon',
      'Dinosaur', 'Crocodile', 'Gerbil', 'Pet', 'Waterfowl', 'Wing',
      'Cairn terrier', 'Dalmatian', 'Basset hound', 'Shetland sheepdog',
      'Sphynx', 'Ragdoll', 'Pomacentridae', 'Horn (Animal)', 'Fur',
      'Flock', 'Safari', 'Herd', 'Zoo', 'Aquarium', 'Cage',
    ],
    'cat_building': [
      'Building', 'Church', 'Mosque', 'Temple', 'Palace', 'Castle',
      'Museum', 'Stadium', 'Skyscraper', 'Tower', 'Bridge', 'Lighthouse',
      'Cathedral', 'Barn', 'Factory', 'School', 'Casino', 'Library',
      'Infrastructure', 'Construction', 'Room', 'Bedroom', 'Bathroom',
      'Kitchen', 'Arch', 'Roof', 'Wall', 'Stairs', 'Door', 'Window',
      'Brick', 'Tile', 'Cabinetry', 'Shelf', 'Drawer', 'Sink', 'Countertop',
      'Handrail', 'Armrest', 'Pier', 'Dam', 'Monument', 'Statue',
      'Ferris wheel', 'Playground', 'Whiteboard', 'Blackboard', 'Desk',
      'Couch', 'Loveseat', 'Chair', 'Bunk bed', 'Bench', 'Cushion', 'Pillow',
    ],
  };

  /** 预计算的标签索引 → 分类 ID 映射缓存 */
  private static labelCategoryCache: Map<number, string> | null = null;

  /**
   * 根据标签名称获取对应的 App 分类 ID
   * @param labelName 模型输出的标签名称
   * @returns App 分类 ID
   */
  static getCategoryForLabelName(labelName: string): string {
    const normalizedLabel: string = labelName.trim().toLowerCase();
    const categoryEntries: [string, string[]][] = Object.entries(AIConstants.CATEGORY_KEYWORDS);

    for (let i: number = 0; i < categoryEntries.length; i++) {
      const categoryId: string = categoryEntries[i][0];
      const keywords: string[] = categoryEntries[i][1];
      for (let j: number = 0; j < keywords.length; j++) {
        if (normalizedLabel === keywords[j].toLowerCase()) {
          return categoryId;
        }
      }
    }
    return 'cat_other';
  }

  /**
   * 获取预计算的标签索引 → 分类 ID 映射表
   * @returns 映射表
   */
  static getLabelCategoryMap(): Map<number, string> {
    if (AIConstants.labelCategoryCache !== null) {
      return AIConstants.labelCategoryCache;
    }

    const cache: Map<number, string> = new Map<number, string>();
    const labels: string[] = AIConstants.LABELS_NAME_MAP;

    for (let i: number = 0; i < labels.length; i++) {
      cache.set(i, AIConstants.getCategoryForLabelName(labels[i]));
    }

    AIConstants.labelCategoryCache = cache;
    return cache;
  }
}

export default Constants;