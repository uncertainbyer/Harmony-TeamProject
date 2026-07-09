import { CategoryModel } from '../model/CategoryModel';
import { CategoryConstants } from '../common/Constants';
import { ApiResult } from './PostApi';
import { ErrorCode } from '../common/Constants';

/** 分类名称映射项 */
class CategoryNameEntry {
  key: string = '';
  value: string = '';
}

class CategoryApi {
  private static instance: CategoryApi | null = null;

  static getInstance(): CategoryApi {
    if (!CategoryApi.instance) { CategoryApi.instance = new CategoryApi(); }
    return CategoryApi.instance;
  }

  /** 6 大系统预设分类（风景/人物/美食/动物/建筑/其他） */
  async getDefault(): Promise<ApiResult<CategoryModel[]>> {
    try {
      const list: CategoryModel[] = CategoryModel.getDefaultCategories();
      return { success: true, data: list, code: ErrorCode.SUCCESS, message: '' };
    } catch (e) {
      return { success: false, data: null, code: ErrorCode.SERVER_ERROR, message: (e as Error).message };
    }
  }

  /** 分类 ID → 中文名称映射表 */
  private static nameEntries: CategoryNameEntry[] = [
    { key: CategoryConstants.SCENERY, value: '风景' },
    { key: CategoryConstants.PERSON, value: '人物' },
    { key: CategoryConstants.FOOD, value: '美食' },
    { key: CategoryConstants.ANIMAL, value: '动物' },
    { key: CategoryConstants.BUILDING, value: '建筑' },
    { key: CategoryConstants.OTHER, value: '其他' },
  ];

  /** 根据分类 ID 获取中文名称 */
  static getName(categoryId: string): string {
    for (let i: number = 0; i < CategoryApi.nameEntries.length; i++) {
      if (CategoryApi.nameEntries[i].key === categoryId) {
        return CategoryApi.nameEntries[i].value;
      }
    }
    return '其他';
  }
}

export { CategoryApi };
export const categoryApi = CategoryApi.getInstance();