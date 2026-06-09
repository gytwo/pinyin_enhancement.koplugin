-- main.lua

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Dispatcher = require("dispatcher")
local Notification = require("ui/widget/notification")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")
local logger = require("logger")
local LexiconManager = require("lexicon_manager")
local ConfirmBox = require("ui/widget/confirmbox")

local PinyinPatch = WidgetContainer:extend{}

-- 全局标志，确保补丁只加载一次
local patch_loaded_flag = false

-- 插件是否启用（从设置中读取）
local function isEnabled()
    local enabled = G_reader_settings:readSetting("pinyin_enhancement_enabled")
    if enabled == nil then
        G_reader_settings:saveSetting("pinyin_enhancement_enabled", true)
        return true
    end
    return enabled
end

-- 保存设置
local function setEnabled(enabled)
    G_reader_settings:saveSetting("pinyin_enhancement_enabled", enabled)
end

-- 获取候选词标准宽度倍数
local function getCandidateWidthMultiplier()
    local mult = G_reader_settings:readSetting("pinyin_candidate_width_multiplier")
    if mult == nil then
        return 0.7
    end
    return mult
end

-- 保存候选词标准宽度倍数
local function setCandidateWidthMultiplier(mult)
    G_reader_settings:saveSetting("pinyin_candidate_width_multiplier", mult)
end

-- 获取候选栏按键背景色
local function getCandidateBarBgColor()
    local color = G_reader_settings:readSetting("pinyin_candidate_bg_color")
    if color == nil then
        return "white"
    end
    return color
end

-- 保存候选栏按键背景色
local function setCandidateBarBgColor(color)
    G_reader_settings:saveSetting("pinyin_candidate_bg_color", color)
end

-- 获取匹配模式
local function getMatchMode()
    local mode = G_reader_settings:readSetting("pinyin_match_mode")
    if mode == nil then
        return "exact"
    end
    return mode
end

-- 保存匹配模式
local function setMatchMode(mode)
    G_reader_settings:saveSetting("pinyin_match_mode", mode)
end

-- 获取是否限制候选词数量
local function getLimitCandidates()
    local limit = G_reader_settings:readSetting("pinyin_limit_candidates")
    if limit == nil then
        return true
    end
    return limit
end

-- 保存是否限制候选词数量
local function setLimitCandidates(limit)
    G_reader_settings:saveSetting("pinyin_limit_candidates", limit)
end

-- 获取键盘宽度模式
local function getKeyWidthMode()
    local mode = G_reader_settings:readSetting("pinyin_key_width_mode")
    if mode == nil then
        return "dynamic"
    end
    return mode
end

-- 保存键盘宽度模式
local function setKeyWidthMode(mode)
    G_reader_settings:saveSetting("pinyin_key_width_mode", mode)
end

-- 获取是否启用空格键上屏
local function getSpaceCommit()
    local enabled = G_reader_settings:readSetting("pinyin_space_commit")
    if enabled == nil then
        return true
    end
    return enabled
end

-- 保存空格键上屏设置
local function setSpaceCommit(enabled)
    G_reader_settings:saveSetting("pinyin_space_commit", enabled)
end

-- 获取是否启用方向键选择候选词
local function getArrowSelect()
    local enabled = G_reader_settings:readSetting("pinyin_arrow_select")
    if enabled == nil then
        return false
    end
    return enabled
end

-- 保存方向键选择候选词设置
local function setArrowSelect(enabled)
    G_reader_settings:saveSetting("pinyin_arrow_select", enabled)
end

-- 获取是否启用词频排序
local function getFrequencySort()
    local enabled = G_reader_settings:readSetting("pinyin_frequency_sort")
    if enabled == nil then
        return true  -- 默认启用
    end
    return enabled
end

-- 保存词频排序设置
local function setFrequencySort(enabled)
    G_reader_settings:saveSetting("pinyin_frequency_sort", enabled)
end

-- ========== 扩展码表菜单 ==========
local function isLexiconEnabled(filename)
    local enabled = LexiconManager.getEnabledLexicons()
    for _, f in ipairs(enabled) do
        if f == filename then
            return true
        end
    end
    return false
end

-- 检查是否所有码表都已启用
local function isAllLexiconsEnabled()
    local lexicon_files = LexiconManager.scanLexiconFiles()
    if #lexicon_files == 0 then
        return false
    end
    local enabled = LexiconManager.getEnabledLexicons()
    for _, filename in ipairs(lexicon_files) do
        local found = false
        for _, f in ipairs(enabled) do
            if f == filename then
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end
    return true
end

-- 切换全部启用/禁用
local function toggleAllLexicons()
    local lexicon_files = LexiconManager.scanLexiconFiles()
    if #lexicon_files == 0 then
        UIManager:show(Notification:new{
            text = _("未找到码表文件"),
            timeout = 2,
        })
        return
    end
    
    local currently_enabled = isAllLexiconsEnabled()
    
    if currently_enabled then
        -- 当前全部已启用 → 全部禁用
        LexiconManager.setEnabledLexicons({})
        local msg = _("已禁用所有码表，需要重启 KOReader 才能生效。是否立即重启？")
        UIManager:show(ConfirmBox:new{
            text = msg,
            ok_text = _("重启"),
            cancel_text = _("稍后"),
            ok_callback = function()
                UIManager:restartKOReader()
            end
        })
    else
        -- 当前未全部启用 → 全部启用
        LexiconManager.setEnabledLexicons(lexicon_files)
        local msg = _("已启用所有码表，需要重启 KOReader 才能生效。是否立即重启？")
        UIManager:show(ConfirmBox:new{
            text = msg,
            ok_text = _("重启"),
            cancel_text = _("稍后"),
            ok_callback = function()
                UIManager:restartKOReader()
            end
        })
    end
    
    G_reader_settings:saveSetting("pinyin_need_reload_lexicon", true)
end

local function toggleLexicon(filename)
    local enabled = LexiconManager.getEnabledLexicons()
    local found = false
    for i, f in ipairs(enabled) do
        if f == filename then
            table.remove(enabled, i)
            found = true
            break
        end
    end
    if not found then
        table.insert(enabled, filename)
    end
    LexiconManager.setEnabledLexicons(enabled)
    G_reader_settings:saveSetting("pinyin_need_reload_lexicon", true)
    
    UIManager:show(ConfirmBox:new{
        text = string.format(_("码表「%s」已%s，需要重启 KOReader 才能生效。是否立即重启？"), 
            filename, 
            found and _("禁用") or _("启用")),
        ok_text = _("重启"),
        cancel_text = _("稍后"),
        ok_callback = function()
            UIManager:restartKOReader()
        end
    })
end

local function buildLexiconSubMenu()
    local lexicon_files = LexiconManager.scanLexiconFiles()
    if #lexicon_files == 0 then
        return {
            {
                text = _("未找到码表文件"),
                enabled = false,
            }
        }
    end
    
    local sub_menu = {}
    
    -- 启用所有码表（带勾选框）
    table.insert(sub_menu, {
        text = _("启用所有码表"),
        checked_func = function()
            return isAllLexiconsEnabled()
        end,
        callback = function()
            toggleAllLexicons()
        end,
        help_text = _("勾选时启用所有码表，取消勾选时禁用所有码表"),
    })
    
    -- 各码表项（使用 LexiconManager 的中文名称）
    for idx, filename in ipairs(lexicon_files) do
        -- 调用 LexiconManager.getDisplayName() 获取中文名称
        local display_name = LexiconManager.getDisplayName(filename)
        table.insert(sub_menu, {
            text = display_name,
            checked_func = function()
                return isLexiconEnabled(filename)
            end,
            callback = function()
                toggleLexicon(filename)
            end,
            help_text = string.format(_("启用/禁用码表: %s"), display_name),
        })
    end
    
    return sub_menu
end
-- ========== 扩展码表菜单 End ==========

-- 加载补丁（只执行一次）
local function loadPatch()
    if patch_loaded_flag then
        return
    end
    patch_loaded_flag = true
    
    UIManager:scheduleIn(0.5, function()
       local DataStorage = require("datastorage")
       local path = DataStorage:getFullDataDir()
       local ok, err = pcall(dofile, path .. "/plugins/pinyin_enhancement.koplugin/candidate_bar.lua")
        if not ok then
            print("拼音补丁加载失败:", err)
        end
    end)
end

-- 注册手势动作
local function registerGestures()
    Dispatcher:registerAction("pinyin_enhancement_toggle_reader", {
        category = "none",
        event = "PinyinEnhancementToggleReader",
        title = _("拼音增强-启用/禁用"),
        reader = true,
    })
    Dispatcher:registerAction("pinyin_enhancement_toggle_filemanager", {
        category = "none",
        event = "PinyinEnhancementToggleFileManager",
        title = _("拼音增强-启用/禁用"),
        filemanager = true,
    })
end

-- 构建设置菜单项
local function buildSettingsMenu()
    return {
        text = _("拼音输入法增强"),
        sub_item_table = {
            {
                text = _("启用拼音候选词"),
                checked_func = function()
                    local enabled = G_reader_settings:readSetting("pinyin_enhancement_enabled")
                    if enabled == nil then
                        return true
                    end
                    return enabled
                end,
                callback = function()
                    local new_state = not isEnabled()
                    setEnabled(new_state)
                    if new_state then
                        loadPatch()
                        UIManager:show(Notification:new{
                            text = _("拼音功能已启用"),
                            timeout = 2,
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("拼音功能已禁用，正在重启..."),
                            timeout = 2,
                        })
                        UIManager:scheduleIn(2, function()
                            UIManager:restartKOReader()
                        end)
                    end
                end,
                help_text = _("启用后，在中文输入法下输入拼音时会显示候选词栏。"),
            },
            {
                text = _("空格键上屏首选词/拼音"),
                checked_func = function() return getSpaceCommit() end,
                callback = function()
                    local current = getSpaceCommit()
                    setSpaceCommit(not current)
                    UIManager:show(Notification:new{
                        text = current and _("空格键上屏已关闭") or _("空格键上屏已开启"),
                        timeout = 2,
                    })
                end,
                help_text = _("开启后，单击空格键自动上屏候选词/拼音；长按空格键上屏拼音。"),
            },
            {
                text = _("换行键上屏拼音/首选词"),
                checked_func = function() 
                    local enabled = G_reader_settings:readSetting("pinyin_enter_commit")
                    if enabled == nil then return true end
                    return enabled
                end,
                callback = function()
                    local current = G_reader_settings:readSetting("pinyin_enter_commit")
                    if current == nil then current = true end
                    G_reader_settings:saveSetting("pinyin_enter_commit", not current)
                    UIManager:show(Notification:new{
                        text = (not current) and _("换行键上屏已开启") or _("换行键上屏已关闭"),
                        timeout = 2,
                    })
                end,
                help_text = _("开启后，单击换行键自动上屏拼音；长按换行键上屏候选词。"),
            },
            {
                text = _("方向键切换候选词"),
                checked_func = function() return getArrowSelect() end,
                callback = function()
                    local current = getArrowSelect()
                    setArrowSelect(not current)
                    UIManager:show(Notification:new{
                        text = current and _("方向键选择已关闭") or _("方向键选择已开启"),
                        timeout = 2,
                    })
                end,
                help_text = _("开启后，左右箭头键切换候选词，空格键/换行键上屏。"),
            },
            {
                text = _("候选栏按键背景色"),
                sub_item_table = {
                    {
                        text = _("白色"),
                        checked_func = function() return getCandidateBarBgColor() == "white" end,
                        callback = function()
                            setCandidateBarBgColor("white")
                            UIManager:show(Notification:new{
                                text = _("候选栏按键背景已设为白色"),
                                timeout = 2,
                            })
                        end,
                    },
                    {
                        text = _("浅灰色"),
                        checked_func = function() return getCandidateBarBgColor() == "lightgray" end,
                        callback = function()
                            setCandidateBarBgColor("lightgray")
                            UIManager:show(Notification:new{
                                text = _("候选栏按键背景已设为浅灰色"),
                                timeout = 2,
                            })
                        end,
                    },
                },
                help_text = _("设置候选栏按键的背景颜色。"),
            },
            {
                text = _("候选词匹配模式"),
                sub_item_table = {
                    {
                        text = _("精准模式（匹配到即止）"),
                        checked_func = function() return getMatchMode() == "exact" end,
                        callback = function()
                            setMatchMode("exact")
                            UIManager:show(Notification:new{
                                text = _("已切换至精准模式"),
                                timeout = 2,
                            })
                        end,
                        help_text = _("只显示精确匹配的候选词，匹配到即止。"),
                    },
                    {
                        text = _("全面模式（匹配追加）"),
                        checked_func = function() return getMatchMode() == "prefix" end,
                        callback = function()
                            setMatchMode("prefix")
                            UIManager:show(Notification:new{
                                text = _("已切换至全面模式"),
                                timeout = 2,
                            })
                        end,
                        help_text = _("显示精确匹配的候选词，并继续追加前缀匹配的候选词。"),
                    },
                },
                help_text = _("选择候选词的匹配方式。"),
            },
            {
                text = _("候选词数量限制"),
                checked_func = function() return getLimitCandidates() end,
                callback = function()
                    local current = getLimitCandidates()
                    setLimitCandidates(not current)
                    if current then
                        UIManager:show(Notification:new{
                            text = _("候选词数量限制已关闭（可能影响性能）"),
                            timeout = 2,
                        })
                    else
                        UIManager:show(Notification:new{
                            text = _("候选词数量限制已开启（最多56个）"),
                            timeout = 2,
                        })
                    end
                end,
                help_text = _("开启后最多显示56个候选词，关闭后显示所有匹配结果。"),
            },
            {
                text = _("候选栏按键宽度模式"),
                sub_item_table = {
                    {
                        text = _("动态键宽（文字大小固定）"),
                        checked_func = function() return getKeyWidthMode() == "dynamic" end,
                        callback = function()
                            setKeyWidthMode("dynamic")
                            UIManager:show(Notification:new{
                                text = _("已切换至动态键宽模式"),
                                timeout = 2,
                            })
                        end,
                        help_text = _("按键宽度根据文字长度变化，文字大小固定。"),
                    },
                    {
                        text = _("固定键宽（文字自动缩小）"),
                        checked_func = function() return getKeyWidthMode() == "fixed" end,
                        callback = function()
                            setKeyWidthMode("fixed")
                            UIManager:show(Notification:new{
                                text = _("已切换至固定键宽模式"),
                                timeout = 2,
                            })
                        end,
                        help_text = _("所有按键宽度相同，长文字自动缩小字体。"),
                    },
                },
                help_text = _("选择候选栏按键的宽度模式。"),
            },
            {
                text = _("候选词动态键宽倍数"),
                sub_item_table = {
                    {
                        text = _("0.5 倍"),
                        checked_func = function() return getCandidateWidthMultiplier() == 0.5 end,
                        callback = function()
                            setCandidateWidthMultiplier(0.5)
                            UIManager:show(Notification:new{
                                text = _("候选词动态键宽已设为 0.5 倍"),
                                timeout = 2,
                            })
                        end,
                    },
                    {
                        text = _("0.6 倍"),
                        checked_func = function() return getCandidateWidthMultiplier() == 0.6 end,
                        callback = function()
                            setCandidateWidthMultiplier(0.6)
                            UIManager:show(Notification:new{
                                text = _("候选词动态键宽已设为 0.6 倍"),
                                timeout = 2,
                            })
                        end,
                    },
                    {
                        text = _("0.7 倍"),
                        checked_func = function() return getCandidateWidthMultiplier() == 0.7 end,
                        callback = function()
                            setCandidateWidthMultiplier(0.7)
                            UIManager:show(Notification:new{
                                text = _("候选词动态键宽已设为 0.7 倍"),
                                timeout = 2,
                            })
                        end,
                    },
                    {
                        text = _("0.8 倍"),
                        checked_func = function() return getCandidateWidthMultiplier() == 0.8 end,
                        callback = function()
                            setCandidateWidthMultiplier(0.8)
                            UIManager:show(Notification:new{
                                text = _("候选词动态键宽已设为 0.8 倍"),
                                timeout = 2,
                            })
                        end,
                    },
                    {
                        text = _("0.9 倍"),
                        checked_func = function() return getCandidateWidthMultiplier() == 0.9 end,
                        callback = function()
                            setCandidateWidthMultiplier(0.9)
                            UIManager:show(Notification:new{
                                text = _("候选词动态键宽已设为 0.9 倍"),
                                timeout = 2,
                            })
                        end,
                    },
                    {
                        text = _("1.0 倍"),
                        checked_func = function() return getCandidateWidthMultiplier() == 1.0 end,
                        callback = function()
                            setCandidateWidthMultiplier(1.0)
                            UIManager:show(Notification:new{
                                text = _("候选词动态键宽已设为 1.0 倍"),
                                timeout = 2,
                            })
                        end,
                    },
                },
                help_text = _("调整候选词的动态键宽倍数，越小每页可显示越多候选词。"),
            },
            {
                text = _("扩展码表"),
                sub_item_table = buildLexiconSubMenu(),
                help_text = _("选择要启用的扩展拼音码表，全部不选则只使用默认码表。"),
            },
            {
                text = _("启用词频排序"),
                checked_func = function() return getFrequencySort() end,
                callback = function()
                    local current = getFrequencySort()
                    setFrequencySort(not current)
                    UIManager:show(Notification:new{
                        text = current and _("词频排序已关闭，恢复原始顺序") or _("词频排序已开启，按使用频率排序"),
                        timeout = 2,
                    })
                end,
                help_text = _("开启后，候选词按使用频率从高到低排序；关闭后按码表原始顺序显示。"),
            },
            {
                text = _("清空候选词使用记录"),
                callback = function()
                    G_reader_settings:saveSetting("pinyin_selection_history", {})
                    -- 立即清空内存中的缓存
                    if _G.pinyin_enhancement and _G.pinyin_enhancement.clearSelectionHistoryCache then
                        _G.pinyin_enhancement.clearSelectionHistoryCache()
                    end
                    UIManager:show(Notification:new{
                        text = _("候选词使用记录已清空"),
                        timeout = 2,
                    })
                end,
            },
            {
                text = _("检查更新"),
                callback = function()
                    local update = require("pinyin_update")
                    update.check_for_updates(false)
                end,
                separator = true,
            },
        },
    }
end

-- 注入设置菜单到文件管理器和阅读器
local function injectSettingsMenu()
    local FileManagerMenu = require("apps/filemanager/filemanagermenu")
    local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")

    local already_in_order = false
    for _, v in ipairs(FileManagerMenuOrder.setting) do
        if v == "pinyin_enhancement_config" then
            already_in_order = true
            break
        end
    end
    if not already_in_order then
        table.insert(FileManagerMenuOrder.setting, "----------------------------")
        table.insert(FileManagerMenuOrder.setting, "pinyin_enhancement_config")
    end

    local orig_fm_setUpdateItemTable = FileManagerMenu.setUpdateItemTable
    FileManagerMenu.setUpdateItemTable = function(self)
        self.menu_items.pinyin_enhancement_config = buildSettingsMenu()
        orig_fm_setUpdateItemTable(self)
    end

    local ReaderMenu = require("apps/reader/modules/readermenu")
    local ReaderMenuOrder = require("ui/elements/reader_menu_order")

    already_in_order = false
    for _, v in ipairs(ReaderMenuOrder.setting) do
        if v == "pinyin_enhancement_config" then
            already_in_order = true
            break
        end
    end
    if not already_in_order then
        table.insert(ReaderMenuOrder.setting, "----------------------------")
        table.insert(ReaderMenuOrder.setting, "pinyin_enhancement_config")
    end

    local orig_reader_setUpdateItemTable = ReaderMenu.setUpdateItemTable
    ReaderMenu.setUpdateItemTable = function(self)
        self.menu_items.pinyin_enhancement_config = buildSettingsMenu()
        orig_reader_setUpdateItemTable(self)
    end
end

function PinyinPatch:init()
    registerGestures()
    injectSettingsMenu()

    if G_reader_settings:readSetting("pinyin_enhancement_enabled") == nil then
        G_reader_settings:saveSetting("pinyin_enhancement_enabled", true)
        loadPatch()
    elseif isEnabled() then
        loadPatch()
    end
end

-- 阅读器手势回调
function PinyinPatch:onPinyinEnhancementToggleReader()
    local new_state = not isEnabled()
    setEnabled(new_state)
    if new_state then
        loadPatch()
        UIManager:show(Notification:new{
            text = _("拼音功能已启用"),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("拼音功能已禁用，正在重启..."),
            timeout = 2,
        })
        UIManager:scheduleIn(2, function()
            UIManager:restartKOReader()
        end)
    end
end

-- 文件管理器手势回调
function PinyinPatch:onPinyinEnhancementToggleFileManager()
    local new_state = not isEnabled()
    setEnabled(new_state)
    if new_state then
        loadPatch()
        UIManager:show(Notification:new{
            text = _("拼音功能已启用"),
            timeout = 2,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("拼音功能已禁用，正在重启..."),
            timeout = 2,
        })
        UIManager:scheduleIn(2, function()
            UIManager:restartKOReader()
        end)
    end
end

return PinyinPatch
