-- main.lua

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Dispatcher = require("dispatcher")
local Notification = require("ui/widget/notification")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

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

-- 加载补丁（只执行一次）
local function loadPatch()
    if patch_loaded_flag then
        return
    end
    patch_loaded_flag = true
    
    UIManager:scheduleIn(0.5, function()
        local ok, err = pcall(dofile, "plugins/pinyin_enhancement.koplugin/candidate_bar.lua")
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
