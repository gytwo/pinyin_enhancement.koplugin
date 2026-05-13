# pinyin_enhancement.koplugin

#### Description

KOReader plugin - Pinyin input method enhancement: displays a candidate word bar above the pinyin input method, tap to input Chinese characters.

#### Installation Instructions

After downloading and extracting, place the `pinyin_enhancement.koplugin` folder into the `koreader\plugins` directory.

#### Usage Instructions

1. [Settings] - [Enhanced Pinyin Input] - Enable Pinyin candidate words (enabled by default, can be disabled, supports shortcut gesture operations).
2. The Pinyin key on the left side of the candidate bar displays the user's current Pinyin input in real time:
   - **Tap**: Clear the current Pinyin state
   - **Long press**: Directly input the Pinyin and clear the candidate bar state
3. Menu Configuration Items:

| Option | Description |
|--------|-------------|
| Space to confirm | Tap to confirm the top candidate (or Pinyin if none, or space if neither); long press to confirm the Pinyin |
| Navigate candidates with arrow keys | Use arrow keys to switch candidates, space key to confirm (requires enabling the space key confirmation feature) |
| Candidate bar key background color | Options: White, Light gray |
| Candidate matching mode | **Precise mode** (stop on match); **Comprehensive mode** (match and append) - displays both exact and prefix match results together |
| Candidate word limit | Default 56 candidates, can be disabled (may affect performance) |
| Candidate key width mode | **Dynamic width** (fixed text size); **Fixed width** (text automatically shrinks) |
| Candidate dynamic width multiplier | 6 options from 0.5x to 1.0x (minimum width ≥ 0.8× width of a single key in the second row) |
| Clear candidate word history | Candidates are sorted by frequency by default (more frequent = higher). Clear history and restart KOReader to restore original sorting |

4. Candidate word sources:
   - KOReader source table: `ui/data/keyboardlayouts/zh_pinyin_data.lua`
   - Custom initial Pinyin code table: `zh_pinyin_data_abbr.lua`

#### Initial Pinyin Code Table Description

- Generated from KOReader source `ui/data/keyboardlayouts/zh_pinyin_data.lua`
- Generation tool: `Node.js`
- Helper module: [pinyin-pro](https://github.com/zh-lx/pinyin-pro)
- Format: `["aa"]={"啊啊"}`, `["bb"]={"爸爸","八百"}`
- You can add mappings in the same format, or replace the entire code table content

![Pinyin-Menu](picture/拼音-菜单.png)
![Pinyin-FixedWidth](picture/拼音-固定键宽.png)
![Pinyin-DynamicWidth-0.7](picture/拼音-动态键宽-0.7倍数.png)
![PinyinKey-Usage](picture/拼音键用法.png)
![Pinyin - Navigate candidates with arrow keys](picture/拼音-方向键切换候选词.png)
![MatchingMode-Precise](picture/匹配模式-精准匹配.png)
![MatchingMode-Comprehensive](picture/匹配模式-全面匹配.png)

#### Contributing

1. Fork this repository
2. Create a new Feat_xxx branch
3. Commit your code
4. Create a new Pull Request

#### Repository Links

- Gitee : https://gitee.com/gytwo/pinyin_enhancement.koplugin
- GitHub: https://github.com/gytwo/pinyin_enhancement.koplugin
