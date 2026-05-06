# pinyin_enhancement.koplugin

#### Description

KOReader plugin - Pinyin input method enhancement: displays a candidate word bar above the pinyin input method, tap to input Chinese characters.

#### Installation Instructions

After downloading and extracting, place the `pinyin_enhancement.koplugin` folder into the `koreader\plugins` directory.

#### Usage Instructions

1. [Settings] - [Enhanced Pinyin Input] - Enable Pinyin candidate words (enabled by default, can be disabled, supports shortcut gesture operations)
2. The Pinyin key on the left side of the candidate bar displays the user's current Pinyin input in real time. Single-click this key to clear the current Pinyin state. Long-press to directly input Pinyin and clear the candidate bar state.
3. Menu Configuration Items

   - **Space to confirm**: Single-click to confirm the top candidate word (if no top candidate exists, confirm the Pinyin; if neither exists, insert a space). Long-press to confirm the Pinyin.
   - **Navigate candidates with arrow keys**: Click the arrow keys to switch between candidates and highlight the selected candidate. Press the space key (requires enabling the space key confirmation feature) to confirm and output that candidate.
   - **Candidate bar key background color**: White, Light gray (blends with keyboard background color)
   - **Candidate matching mode**: Precise mode (stop on match), Comprehensive mode (match and append). Select the candidate matching behavior. Default matching priority: exact match → prefix match. If an exact match is found, matching stops. To display both exact and prefix match results together, enable Comprehensive mode (match and append).
   - **Candidate word limit**: Default 56 candidates; can be disabled, but may affect performance.
   - **Candidate key width mode**: Dynamic width (fixed text size), Fixed width (text automatically shrinks)
   - **Candidate dynamic width multiplier**: 6 options from 0.5x to 1.0x. Adjusts candidate key width (minimum width ≥ 0.8× width of a single key in the second row).

4. Candidate words are sourced from koreader's source table in `ui/data/keyboardlayouts/zh_pinyin_data`. Theoretically, replacing the source table (i.e., adding initial-letter mapping) can enable first-letter Pinyin mode.

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

#### Special Features

1. Use `Readme_XXX.md` to support different languages, e.g., `Readme_en.md`, `Readme_zh.md`
2. Gitee official blog: [blog.gitee.com](https://blog.gitee.com)
3. Explore outstanding open-source projects on Gitee: [https://gitee.com/explore](https://gitee.com/explore)
4. [GVP](https://gitee.com/gvp) – Gitee's Most Valuable Open Source Project award
5. Gitee official user manual: [https://gitee.com/help](https://gitee.com/help)
6. Gitee Cover Story: [https://gitee.com/gitee-stars/](https://gitee.com/gitee-stars/)
