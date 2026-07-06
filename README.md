[![Release](https://github.com/gytwo/gitee-sync/actions/workflows/release.yml/badge.svg)](https://github.com/gytwo/gitee-sync/actions/workflows/release.yml)
[![Sync from Gitee to GitHub](https://github.com/gytwo/gitee-sync/actions/workflows/gitee-sync.yml/badge.svg)](https://github.com/gytwo/gitee-sync/actions/workflows/gitee-sync.yml)

# pinyin_enhancement.koplugin

#### 介绍

KOReader 插件 - 拼音输入法增强：在拼音输入法上方显示候选词栏，点击即可输入汉字。

#### 安装教程

下载解压后将 `pinyin_enhancement.koplugin` 文件夹放到 `koreader\plugins` 目录下。

#### 使用说明

1. [设置] - [拼音输入法增强] - 选择启用拼音候选词（默认启用，可关闭，支持快捷手势操作）。
2. 候选栏左侧拼音按键会实时显示用户输入的拼音：

   - **单击**：直接输入拼音并清空候选栏状态
   - **长按**：清空当前拼音状态

3. 菜单配置项目：

| 配置项 | 说明 |
|--------|------|
| 空格键上屏首选词/拼音 | 单击空格键上屏首选词（无则上屏拼音，均无则空格）；长按上屏拼音 |
| 换行键上屏拼音/首选词 | 单击换行键上屏拼音（无则换行）；长按上屏首选词 |
| 方向键切换候选词 | 用方向键切换候选词，空格键/换行键上屏（需开启空格键/换行键上屏功能） |
| 候选栏按键背景色 | 可选：白色、浅灰色 |
| 候选词匹配模式 | **精准模式**（匹配到即止）；**全面模式**（匹配追加），同时显示精确匹配和前缀匹配结果 |
| 候选词数量限制 | 默认 56 个，可取消（可能影响性能） |
| 候选词按键宽度模式 | **动态键宽**（文字大小固定）；**固定键宽**（文字自动缩小） |
| 候选词动态键宽倍数 | 0.5 ~ 1.0 共 6 档（最小宽度 ≥ 第二行单个按键宽度的 0.8 倍） |
| **扩展码表** | 开启加载扩展码表。**⚠️警告：大量加载码表会占用大量内存，可能会导致设备因内存不足而卡死。启用前请务必先备份完整 `koreader` 文件夹内容！** |
| 启用词频排序 | 开启后记录词频，按词频从高到底排序候选词，相同词频保持原始排序 |
| 清空候选词记录 | 清空后恢复候选词原始排序 |

4. 候选词来源：
   - KOReader 源码表：`ui/data/keyboardlayouts/zh_pinyin_data.lua`
   - 首字母拼音码表：`zh_pinyin_data_abbr.lua`
   - 扩展码表：`lexicon`

#### 首字母拼音码表说明

- 根据 KOReader 源码 `ui/data/keyboardlayouts/zh_pinyin_data.lua` 生成
- 生成工具：`Node.js`
- 辅助模块：[pinyin-pro](https://github.com/zh-lx/pinyin-pro)
- 格式说明：`["aa"]={"啊啊"}`、`["bb"]={"爸爸","八百"}`
- 可按照相同格式增加映射，或替换整个码表内容

#### 扩展码表说明

- 词汇来源：`https://pinyin.sogou.com/dict/`
- 转换工具：`node.js` （`scel`格式转换为koreader标准码表`lua`格式）
- 自定义码表：如果需要添加自定义码表，仅需将自制的码表文件（需确保格式正确）放到文件夹`lexicon`下，加载插件时会自动扫描该文件夹内的所有码表并出现在`扩展码表`菜单中，在菜单中找到该码表启用即可。

- **⚠️ 警告：大量加载码表会占用大量内存，可能会导致设备因内存不足而卡死。启用前请务必先备份完整`koreader`文件夹内容！**
- **⚠️ 警告：额外添加的自定义码表不能太大（超过1M），否则同样可能导致设备内存不足而卡死，启用前请务必先备份完整`koreader`文件夹内容！**


| 文件名 | 菜单中文名 | 类型 |
|--------|-----------|------|
| `Classical Poetry.lua` | 古诗词码表 | 文件 |
| `Finance.lua` | 财经金融码表 | 文件 |
| `Ideological.lua` | 思政专业术语码表 | 文件 |
| `Idiom` | 成语俗语码表 | 文件夹 |
| `Legal.lua` | 法律码表 | 文件 |
| `Neologisms.lua` | 新词集锦码表 | 文件 |
| `Three-Character Idiom.lua` | 三字成语码表 | 文件 |
| `WittySaying.lua` | 歇后语码表 | 文件 |


![拼音-菜单](picture/拼音-菜单.png)
![拼音-菜单-额外词库](picture/拼音-菜单-额外词库.png)
![拼音-固定键宽](picture/拼音-固定键宽.png)
![拼音-动态键宽-0.7倍数](picture/拼音-动态键宽-0.7倍数.png)
![拼音键用法](picture/拼音键用法.png)
![拼音-方向键切换候选词](picture/拼音-方向键切换候选词.png)
![匹配模式-精准匹配](picture/匹配模式-精准匹配.png)
![匹配模式-全面匹配](picture/匹配模式-全面匹配.png)

#### 参与贡献

1. Fork 本仓库
2. 新建 Feat_xxx 分支
3. 提交代码
4. 新建 Pull Request

#### 项目地址

- Gitee : https://gitee.com/gytwo/pinyin_enhancement.koplugin
- GitHub: https://github.com/gytwo/pinyin_enhancement.koplugin
