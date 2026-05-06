-- candidate_bar.lua

--[[
    拼音候选词（动态按键宽度，只重建第一行）
]]

local logger = require("logger")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = Device.screen
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Size = require("ui/size")
local VerticalSpan = require("ui/widget/verticalspan")

logger.info("[CANDIDATE_BAR] 候选词栏模块加载")

local patched = false
local class_hooked = false
local current_ime = nil
local current_inputbox = nil
local current_keyboard = nil
local code_map = nil

local current_pinyin = ""
local current_candidates = nil
local current_page = 1
local total_pages = 1

-- 是否启用拼音功能
local pinyin_enabled = false

-- 中间区域标准宽度（7个标准宽度）
local CANDIDATE_STD_WIDTH = 7

-- 保存原始按键高度
local original_key_height = nil

-- 最小理论宽度倍数（0.8倍标准宽度）
local MIN_WIDTH_RATIO = 0.8

-- 键盘宽度模式
local key_width_mode = "dynamic"

-- 固定宽度模式使用的按键引用
local candidate_key_refs = {}
local pinyin_key = nil
local prev_page_key = nil
local next_page_key = nil

-- 获取候选词标准宽度倍数配置
local function getCandidateWidthMultiplier()
    local mult = G_reader_settings:readSetting("pinyin_candidate_width_multiplier")
    if mult == nil then
        return 0.7
    end
    return mult
end

-- 获取是否启用空格键上屏
local function getSpaceCommit()
    local enabled = G_reader_settings:readSetting("pinyin_space_commit")
    if enabled == nil then
        return true  -- 默认开启
    end
    return enabled
end

-- 获取候选栏按键背景色
local function getCandidateBarBgColor()
    local color = G_reader_settings:readSetting("pinyin_candidate_bg_color")
    if color == "lightgray" then
        return Blitbuffer.COLOR_LIGHT_GRAY
    else
        return Blitbuffer.COLOR_WHITE
    end
end

-- 获取匹配模式
local function getMatchMode()
    local mode = G_reader_settings:readSetting("pinyin_match_mode")
    if mode == nil then
        return "exact"
    end
    return mode
end

-- 获取是否限制候选词数量
local function getLimitCandidates()
    local limit = G_reader_settings:readSetting("pinyin_limit_candidates")
    if limit == nil then
        return true
    end
    return limit
end

-- 获取键盘宽度模式
local function getKeyWidthMode()
    local mode = G_reader_settings:readSetting("pinyin_key_width_mode")
    if mode == nil then
        return "dynamic"
    end
    return mode
end

-- 更新键盘宽度模式
local function updateKeyWidthMode()
    key_width_mode = getKeyWidthMode()
end

-- 根据文本长度计算合适的字体大小
local function getAdjustedFontSizeForText(text, max_width, base_font_size)
    if not text or text == "" then
        return base_font_size
    end
    
    local face = Font:getFace("infont", base_font_size)
    local temp_widget = TextWidget:new{
        text = text,
        face = face,
        bold = false,
    }
    
    local text_width = temp_widget:getWidth()
    temp_widget:free()
    
    if text_width <= max_width then
        return base_font_size
    end
    
    local new_size = base_font_size
    while new_size > 8 do
        new_size = new_size - 1
        local test_face = Font:getFace("infont", new_size)
        local test_widget = TextWidget:new{
            text = text,
            face = test_face,
            bold = false,
        }
        local test_width = test_widget:getWidth()
        test_widget:free()
        
        if test_width <= max_width then
            return new_size
        end
    end
    
    return 8
end

-- 计算中文字符的理论宽度权重
local function getWordWidth(word)
    if not word or word == "" then
        return 0
    end
    return #word * 2 / 9
end

-- 从码表获取候选词列表（原始，未分页）
local function getRawCandidatesFromCodeMap(pinyin)
    if not pinyin or pinyin == "" or not code_map then
        return nil
    end
    
    local match_mode = getMatchMode()
    local limit_enabled = getLimitCandidates()
    local max_results = CANDIDATE_STD_WIDTH * 8
    
    local result = {}
    local seen = {}
    
    -- 优先级1：精确匹配
    local exact_candi = code_map[pinyin]
    if exact_candi then
        if type(exact_candi) == "table" then
            for _, word in ipairs(exact_candi) do
                if not seen[word] then
                    table.insert(result, word)
                    seen[word] = true
                end
            end
        elseif type(exact_candi) == "string" then
            if not seen[exact_candi] then
                table.insert(result, exact_candi)
                seen[exact_candi] = true
            end
        end
    end
    
    -- 根据匹配模式决定是否继续前缀匹配
    local should_continue = false
    if match_mode == "exact" then
        should_continue = (#result == 0)
    else
        should_continue = true
    end
    
    -- 优先级2：前缀匹配
    if should_continue then
        local prefix_matches = {}
        for py, words in pairs(code_map) do
            if py ~= pinyin and py:find("^" .. pinyin) then
                local first_word
                if type(words) == "table" then
                    first_word = words[1]
                elseif type(words) == "string" then
                    first_word = words
                else
                    goto continue
                end
                if first_word and not seen[first_word] then
                    table.insert(prefix_matches, {py = py, word = first_word})
                    seen[first_word] = true
                end
            end
            ::continue::
        end
        
        table.sort(prefix_matches, function(a, b)
            return a.py < b.py
        end)
        
        for _, v in ipairs(prefix_matches) do
            table.insert(result, v.word)
        end
    end
    
    -- 限制结果数量
    if limit_enabled and #result > max_results then
        local limited = {}
        for i = 1, max_results do
            table.insert(limited, result[i])
        end
        result = limited
    end
    
    return result
end

-- 自定义 VirtualKey（动态宽度模式使用）
local MyVirtualKey = InputContainer:extend{
    label = nil,
    keyboard = nil,
    width = 0,
    height = 0,
    bordersize = 0,
    focused_bordersize = Size.border.default,
    radius = 0,
    face = nil,
    is_pinyin_key = false,
}

function MyVirtualKey:init()
    local label_font_size = G_reader_settings:readSetting("keyboard_key_font_size", 22)
    
    if self.is_pinyin_key and self.label and self.label ~= "[]" and self.label ~= "" then
        local max_width = self.width - 2*self.bordersize - 2*Size.padding.small
        label_font_size = getAdjustedFontSizeForText(self.label, max_width, label_font_size)
    end
    
    self.face = Font:getFace("infont", label_font_size)
    
    local label_widget = TextWidget:new{
        text = self.label,
        face = self.face,
        bold = false,
    }

    local bg_color = getCandidateBarBgColor()

    self[1] = FrameContainer:new{
        margin = 0,
        bordersize = 0,
        background = bg_color,
        radius = 0,
        padding = 0,
        allow_mirroring = false,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width - 2*self.bordersize,
                h = self.height - 2*self.bordersize,
            },
            label_widget,
        },
    }
    
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = self.height,
    }
    
    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldSelect = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },
    }
end

function MyVirtualKey:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    if self[1] then
        self[1]:paintTo(bb, x, y)
        if self[1].dimen then
            self[1].dimen.x = x
            self[1].dimen.y = y
        end
    end
    if self.keyboard and self.keyboard.key_padding then
        local coords_padding = math.floor(self.keyboard.key_padding / 2)
        local dims_padding = self.keyboard.key_padding
        self.dimen.x = self.dimen.x - coords_padding
        self.dimen.w = self[1].dimen.w + dims_padding
        self.dimen.y = self.dimen.y - coords_padding
        self.dimen.h = self[1].dimen.h + dims_padding
    end
end

function MyVirtualKey:onTapSelect()
    if self.callback then
        self.callback()
    end
    return true
end

function MyVirtualKey:onHoldSelect()
    if self.hold_callback then
        self.hold_callback()
    end
    return true
end

function MyVirtualKey:setText(text)
    self.label = text
    
    if self.is_pinyin_key and text and text ~= "[]" and text ~= "" then
        local label_font_size = G_reader_settings:readSetting("keyboard_key_font_size", 22)
        local max_width = self.width - 2*self.bordersize - 2*Size.padding.small
        local new_font_size = getAdjustedFontSizeForText(text, max_width, label_font_size)
        self.face = Font:getFace("infont", new_font_size)
        if self[1] and self[1][1] and self[1][1][1] then
            self[1][1][1]:setFace(self.face)
            self[1][1][1]:setText(text)
        end
    elseif self[1] and self[1][1] and self[1][1][1] then
        self[1][1][1]:setText(text)
    end
end

function MyVirtualKey:setColor(color)
    if self[1] and self[1][1] and self[1][1][1] then
        self[1][1][1].fgcolor = color
    end
end

-- 提交拼音文字到输入框
local function commitPinyinText()
    if current_pinyin == "" then
        return
    end
    
    local inputbox = current_inputbox
    if not inputbox and current_ime then
        inputbox = current_ime._inputbox or current_ime.inputbox
        if inputbox then
            current_inputbox = inputbox
        end
    end
    
    if not inputbox or not inputbox.addChars then
        return
    end
    
    inputbox:addChars(current_pinyin)
    
    if current_ime and current_ime.clear_stack then
        current_ime:clear_stack()
    end
    
    current_pinyin = ""
    current_candidates = nil
    current_page = 1
    total_pages = 1
    
    rebuildFirstRow()
end

-- 查找 IME
local function findIME()
    for k, v in pairs(package.loaded) do
        if k and (k:find("keyboardlayouts.zh_CN_keyboard") or k:find("zh_CN_keyboard")) and v and v.ime then
            return v.ime
        end
    end
    return nil
end

-- 直接加载码表数据
local function loadCodeMapDirectly()
    local ok, data = pcall(require, "ui/data/keyboardlayouts/zh_pinyin_data")
    if ok and data and type(data) == "table" then
        code_map = data
        return true
    end
    return false
end

-- 获取所有候选词并分页（根据模式使用不同逻辑）
local function updateCandidates()
    if not code_map or current_pinyin == "" then
        current_candidates = nil
        current_page = 1
        total_pages = 1
        return false
    end
    
    local all_candidates = getRawCandidatesFromCodeMap(current_pinyin)
    if not all_candidates or #all_candidates == 0 then
        current_candidates = nil
        current_page = 1
        total_pages = 1
        return false
    end
    
    local multiplier = getCandidateWidthMultiplier()
    local pages = {}
    
    if key_width_mode == "fixed" then
        -- 固定宽度模式：每页固定 7 个候选词
        local items_per_page = 7
        local total = #all_candidates
        for start_idx = 1, total, items_per_page do
            local end_idx = math.min(start_idx + items_per_page - 1, total)
            local page_cands = {}
            for i = start_idx, end_idx do
                table.insert(page_cands, all_candidates[i])
            end
            table.insert(pages, {
                candidates = page_cands,
                theoretical_width = #page_cands
            })
        end
    else
        -- 动态宽度模式：原有逻辑
        local current_width = 0
        local current_page_cands = {}
        
        for _, cand in ipairs(all_candidates) do
            local word_width = getWordWidth(cand) * multiplier
            local theoretical_width = math.max(word_width, MIN_WIDTH_RATIO)
            
            if current_width + theoretical_width <= CANDIDATE_STD_WIDTH then
                table.insert(current_page_cands, cand)
                current_width = current_width + theoretical_width
            else
                if #current_page_cands > 0 then
                    table.insert(pages, {
                        candidates = current_page_cands,
                        theoretical_width = current_width
                    })
                end
                current_page_cands = { cand }
                current_width = theoretical_width
            end
        end
        
        if #current_page_cands > 0 then
            table.insert(pages, {
                candidates = current_page_cands,
                theoretical_width = current_width
            })
        end
    end
    
    current_candidates = pages
    total_pages = #current_candidates
    current_page = math.min(current_page, total_pages)
    current_page = math.max(current_page, 1)
    
    return true
end

-- 提交候选词
local function commitCandidate(candidate)
    local inputbox = current_inputbox
    if not inputbox and current_ime then
        inputbox = current_ime._inputbox or current_ime.inputbox
        if inputbox then
            current_inputbox = inputbox
        end
    end
    
    if not inputbox or not inputbox.addChars then
        return false
    end
    
    inputbox:addChars(candidate)
    
    if current_ime and current_ime.clear_stack then
        current_ime:clear_stack()
    end
    
    current_pinyin = ""
    current_candidates = nil
    current_page = 1
    total_pages = 1
    
    rebuildFirstRow()
    
    return true
end

-- 清空拼音
local function clearPinyin()
    if #current_pinyin > 0 then
        current_pinyin = ""
        current_candidates = nil
        current_page = 1
        total_pages = 1
        rebuildFirstRow()
        if current_keyboard then
            UIManager:setDirty(current_keyboard, function()
                return "ui", current_keyboard.dimen
            end)
        end
    end
end

-- 修改键盘布局，添加候选栏行
local function addCandidateRowToKeyboardLayout()
    local keyboard = require("ui/data/keyboardlayouts/zh_CN_keyboard")
    if not keyboard or not keyboard.keys then
        return false
    end
    
    if keyboard.keys[1] and keyboard.keys[1][1] and keyboard.keys[1][1].label == "[]" then
        return true
    end
    
    local candidate_row = {}
    candidate_row[1] = { label = "[]" }
    candidate_row[2] = { label = "◀" }
    for i = 1, CANDIDATE_STD_WIDTH do
        candidate_row[2 + i] = { label = "" }
    end
    candidate_row[2 + CANDIDATE_STD_WIDTH + 1] = { label = "▶" }
    
    table.insert(keyboard.keys, 1, candidate_row)
    
    return true
end

-- 动态宽度模式：重建第一行
local function rebuildFirstRowDynamic()
    local key_padding = current_keyboard.key_padding
    local padding = current_keyboard.padding
    
    local old_horizontal_group = current_keyboard.layout[1]
    if not old_horizontal_group then
        return
    end
    
    if not original_key_height then
        local old_first_key = old_horizontal_group[1]
        if old_first_key and old_first_key.dimen then
            original_key_height = old_first_key.dimen.h
        else
            return
        end
    end
    
    local base_key_height = original_key_height
    local base_key_width = math.floor((current_keyboard.width - (10 + 1) * key_padding - 2 * padding) / 10)
    local multiplier = getCandidateWidthMultiplier()
    local min_key_width = base_key_width * MIN_WIDTH_RATIO
    
    local row = {}
    local idx = 1
    
    local pinyin_text = current_pinyin ~= "" and "[" .. current_pinyin .. "]" or "[]"
    row[idx] = { label = pinyin_text, is_pinyin = true, width = base_key_width }
    idx = idx + 1
    
    row[idx] = { label = "◀", width = base_key_width }
    idx = idx + 1
    
    if current_candidates and #current_candidates > 0 and current_candidates[current_page] then
        local page_data = current_candidates[current_page]
        local candidates = page_data.candidates
        
        for _, cand in ipairs(candidates) do
            local word_width = getWordWidth(cand) * multiplier
            local raw_width = base_key_width * word_width + (word_width - 1) * key_padding
            local key_width = math.max(raw_width, min_key_width)
            row[idx] = { label = cand, width = key_width }
            idx = idx + 1
        end
        
        local remaining = CANDIDATE_STD_WIDTH - page_data.theoretical_width
        if remaining > 0 then
            local remaining_width = base_key_width * remaining + (remaining - 1) * key_padding
            if current_page < total_pages then
                local face = Font:getFace("infont", G_reader_settings:readSetting("keyboard_key_font_size", 22))
                local temp_widget = TextWidget:new{ text = "...", face = face }
                local ellipsis_width = temp_widget:getWidth()
                temp_widget:free()
                
                if remaining_width >= ellipsis_width then
                    row[idx] = { label = "...", width = remaining_width }
                else
                    row[idx] = { label = ".", width = remaining_width }
                end
            else
                row[idx] = { label = "", width = remaining_width }
            end
            idx = idx + 1
        end
    else
        for i = 1, CANDIDATE_STD_WIDTH do
            row[idx] = { label = "", width = base_key_width }
            idx = idx + 1
        end
    end
    
    row[idx] = { label = "▶", width = base_key_width }
    
    local horizontal_group = HorizontalGroup:new{ allow_mirroring = false }
    local new_row_widgets = {}
    local x = padding
    local y = padding
    
    for i, key_spec in ipairs(row) do
        local new_key = MyVirtualKey:new{
            label = key_spec.label,
            width = key_spec.width,
            height = base_key_height,
            keyboard = current_keyboard,
            is_pinyin_key = key_spec.is_pinyin or false,
        }
        
        new_key.dimen.x = x
        new_key.dimen.y = y
        new_key.dimen.w = key_spec.width
        new_key.dimen.h = base_key_height
        
        if new_key[1] and new_key[1].dimen then
            new_key[1].dimen.x = x
            new_key[1].dimen.y = y
        end
        
        new_key.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = new_key.dimen,
                },
            },
            HoldSelect = {
                GestureRange:new{
                    ges = "hold",
                    range = new_key.dimen,
                },
            },
        }
        
        table.insert(horizontal_group, new_key)
        table.insert(new_row_widgets, new_key)
        
        if i < #row then
            table.insert(horizontal_group, HorizontalSpan:new{width = key_padding})
        end
        
        x = x + key_spec.width + key_padding
    end
    
    current_keyboard.layout[1] = horizontal_group
    
    local keyboard_frame = current_keyboard[1] and current_keyboard[1][1]
    if keyboard_frame and keyboard_frame[1] and keyboard_frame[1][1] then
        local vertical_group = keyboard_frame[1][1]
        if vertical_group then
            vertical_group[1] = horizontal_group
            vertical_group:resetLayout()
        end
    end
    
    local has_prev = (total_pages > 1 and current_page > 1)
    local has_next = (total_pages > 1 and current_page < total_pages)
    
    if new_row_widgets[1] then
        new_row_widgets[1].callback = function() clearPinyin() end
        new_row_widgets[1].hold_callback = function() commitPinyinText() end
    end
    
    if new_row_widgets[2] then
        if has_prev then
            new_row_widgets[2].callback = function()
                if current_page > 1 then
                    current_page = current_page - 1
                    rebuildFirstRow()
                end
            end
            new_row_widgets[2]:setColor(Blitbuffer.COLOR_BLACK)
        else
            new_row_widgets[2].callback = nil
            new_row_widgets[2]:setColor(Blitbuffer.COLOR_DARK_GRAY)
        end
    end
    
    local last_idx = #new_row_widgets
    if new_row_widgets[last_idx] then
        if has_next then
            new_row_widgets[last_idx].callback = function()
                if current_page < total_pages then
                    current_page = current_page + 1
                    rebuildFirstRow()
                end
            end
            new_row_widgets[last_idx]:setColor(Blitbuffer.COLOR_BLACK)
        else
            new_row_widgets[last_idx].callback = nil
            new_row_widgets[last_idx]:setColor(Blitbuffer.COLOR_DARK_GRAY)
        end
    end
    
    if current_candidates and #current_candidates > 0 and current_candidates[current_page] then
        local candidates = current_candidates[current_page].candidates
        for i = 1, #candidates do
            local key = new_row_widgets[2 + i]
            if key then
                key.callback = (function(c)
                    return function() commitCandidate(c) end
                end)(candidates[i])
                key:setColor(Blitbuffer.COLOR_BLACK)
            end
        end
    end
    
    UIManager:setDirty(current_keyboard, function()
        return "ui", current_keyboard.dimen
    end)
end

-- 固定宽度模式：更新虚拟按键文本、字体和背景色
local function updateVirtualKeyText(key, text, font_size, bg_color)
    if not key then
        return false
    end
    
    key.label = text
    
    if key[1] and key[1][1] and key[1][1][1] then
        local text_widget = key[1][1][1]
        
        if text_widget.setText then
            text_widget:setText(text)
        else
        end
        
        if font_size then
            local new_face = Font:getFace("infont", font_size)
            if text_widget.setFace then
                text_widget:setFace(new_face)
            else
                text_widget.face = new_face
            end
            key.face = new_face
        end
        
        -- 更新背景色
        if bg_color and key[1] then
            key[1].background = bg_color
        end
        
        return true
    else
        if key[1] then
            if key[1][1] then
            end
        end
    end
    
    return false
end

-- 固定宽度模式：保存按键引用
local function saveCandidateKeyReferences(keyboard)
    if not keyboard or not keyboard.layout or not keyboard.layout[1] then
        return false
    end
    
    local candidate_row_widgets = keyboard.layout[1]
    if not candidate_row_widgets or #candidate_row_widgets < 10 then
        return false
    end
    
    pinyin_key = candidate_row_widgets[1]
    prev_page_key = candidate_row_widgets[2]
    for i = 1, 7 do
        candidate_key_refs[i] = candidate_row_widgets[2 + i]
    end
    next_page_key = candidate_row_widgets[10]
    
    return true
end

-- 固定宽度模式：更新候选栏按键显示
local function updateCandidateKeysFixed()
    if not pinyin_key then
        return
    end
    
    local bg_color = getCandidateBarBgColor()
    
    if not pinyin_enabled then
        updateVirtualKeyText(pinyin_key, "[]", nil, bg_color)
        updateVirtualKeyText(prev_page_key, " ", nil, bg_color)
        updateVirtualKeyText(next_page_key, " ", nil, bg_color)
        for i = 1, 7 do
            if candidate_key_refs[i] then
                updateVirtualKeyText(candidate_key_refs[i], "", nil, bg_color)
            end
        end
        return
    end
    
    -- 更新拼音显示
    local pinyin_text = "[]"
    if current_pinyin ~= "" then
        pinyin_text = "[" .. current_pinyin .. "]"
    end
    local max_width = pinyin_key.width - 2*pinyin_key.bordersize - 2*Size.padding.small
    local pinyin_font_size = getAdjustedFontSizeForText(pinyin_text, max_width, 22)
    updateVirtualKeyText(pinyin_key, pinyin_text, pinyin_font_size, bg_color)
    
    pinyin_key.callback = function()
        clearPinyin()
    end
    pinyin_key.hold_callback = function()
        commitPinyinText()
    end
    
    -- 更新上一页
    if total_pages > 1 then
        updateVirtualKeyText(prev_page_key, "◀", nil, bg_color)
        prev_page_key.callback = function()
            if current_page > 1 then
                current_page = current_page - 1
                updateCandidates()
                updateCandidateKeysFixed()
                if current_keyboard then
                    UIManager:setDirty(current_keyboard, function()
                        return "ui", current_keyboard.dimen
                    end)
                end
            end
        end
    else
        updateVirtualKeyText(prev_page_key, " ", nil, bg_color)
        prev_page_key.callback = nil
    end
    
    -- 更新候选词
    local page_candidates = {}
    if current_candidates and #current_candidates > 0 and current_candidates[current_page] then
        page_candidates = current_candidates[current_page].candidates
    end
    
    for i = 1, 7 do
        local key = candidate_key_refs[i]
        if key then
            local cand = page_candidates and page_candidates[i]
            if cand then
                local max_width = key.width - 2*key.bordersize - 2*Size.padding.small
                local font_size = getAdjustedFontSizeForText(cand, max_width, 22)
                updateVirtualKeyText(key, cand, font_size, bg_color)
                key.callback = function()
                    commitCandidate(cand)
                end
            else
                updateVirtualKeyText(key, "", nil, bg_color)
                key.callback = nil
            end
        end
    end
    
    -- 更新下一页
    if total_pages > 1 and current_page < total_pages then
        updateVirtualKeyText(next_page_key, "▶", nil, bg_color)
        next_page_key.callback = function()
            if current_page < total_pages then
                current_page = current_page + 1
                updateCandidates()
                updateCandidateKeysFixed()
                if current_keyboard then
                    UIManager:setDirty(current_keyboard, function()
                        return "ui", current_keyboard.dimen
                    end)
                end
            end
        end
    else
        updateVirtualKeyText(next_page_key, " ", nil, bg_color)
        next_page_key.callback = nil
    end
    
    if current_keyboard then
        UIManager:setDirty(current_keyboard, function()
            return "ui", current_keyboard.dimen
        end)
    end
end

-- 固定宽度模式：重建第一行
local function rebuildFirstRowFixed()
    if not pinyin_key then
        if current_keyboard then
            saveCandidateKeyReferences(current_keyboard)
        end
    end
    updateCandidateKeysFixed()
end

-- 重建第一行（根据模式选择）
function rebuildFirstRow()
    if not current_keyboard then
        return
    end
    
    if not pinyin_enabled then
        return
    end
    
    updateCandidates()
    
    if key_width_mode == "fixed" then
        rebuildFirstRowFixed()
    else
        rebuildFirstRowDynamic()
    end
end

-- 处理字母输入
local function handleAddChar(key)
    
    if not key then
        return false
    end

    -- 空格键处理（添加到最前面，在其他判断之前）
    local key_char_space = key
    if type(key) == "table" then
        if key.key then
            key_char_space = key.key
        elseif key.label then
            key_char_space = key.label
        end
    end
    if key_char_space == " " then
        if getSpaceCommit() then
            -- 优先上屏候选词第一个
            if current_candidates and #current_candidates > 0 and current_candidates[current_page] then
                local candidates = current_candidates[current_page].candidates
                if candidates and #candidates > 0 then
                    commitCandidate(candidates[1])
                    return true
                end
            end
            -- 其次上屏拼音
            if current_pinyin ~= "" then
                commitPinyinText()
                return true
            end
        end
        -- 无内容或功能关闭，返回 false 让原始空格功能执行
        return false
    end
    
    if not pinyin_enabled then
        return false
    end
    
    if not code_map then
        return false
    end
    
    local key_char = key
    if type(key) == "table" then
        if key.key then
            key_char = key.key
        elseif key.label then
            key_char = key.label
        else
            return false
        end
    end
    
    
    if (key_char >= "a" and key_char <= "z") or (key_char >= "A" and key_char <= "Z") then
        if key_char >= "A" and key_char <= "Z" then
            local inputbox = current_inputbox
            if not inputbox and current_ime then
                inputbox = current_ime._inputbox or current_ime.inputbox
                if inputbox then
                    current_inputbox = inputbox
                end
            end
            if inputbox and inputbox.addChars then
                inputbox:addChars(key_char)
            else
            end
            current_pinyin = ""
            current_candidates = nil
            current_page = 1
            total_pages = 1
            rebuildFirstRow()
            return true
        else
            current_pinyin = current_pinyin .. key_char
if key_width_mode == "fixed" then
    saveCandidateKeyReferences(current_keyboard)  -- 重新获取引用
end
            rebuildFirstRow()
            return true
        end
    end
    
    return false
end

-- 启用拼音功能
function enablePinyinFeatures()
    if pinyin_enabled then
        return
    end
    pinyin_enabled = true
    current_pinyin = ""
    current_candidates = nil
    current_page = 1
    total_pages = 1
    rebuildFirstRow()
    if current_keyboard then
        UIManager:setDirty(current_keyboard, function()
            return "ui", current_keyboard.dimen
        end)
    end
end

-- 禁用拼音功能
function disablePinyinFeatures()
    if not pinyin_enabled then
        return
    end
    pinyin_enabled = false
    current_pinyin = ""
    current_candidates = nil
    current_page = 1
    total_pages = 1
    rebuildFirstRow()
    if current_keyboard then
        UIManager:setDirty(current_keyboard, function()
            return "ui", current_keyboard.dimen
        end)
    end
end

-- 保存原始函数引用
local originalAddChar = nil
local originalDelChar = nil
local originalInit = nil
local originalSetKeyboardLayout = nil

-- Hook VirtualKeyboard（只执行一次）
local function hookVirtualKeyboard()
    if class_hooked then
        return true
    end
    
    loadCodeMapDirectly()
    current_ime = findIME()
    addCandidateRowToKeyboardLayout()
    
    local VirtualKeyboard = require("ui/widget/virtualkeyboard")
    if not VirtualKeyboard then
        return false
    end
    
    originalAddChar = VirtualKeyboard.addChar
    originalDelChar = VirtualKeyboard.delChar
    originalInit = VirtualKeyboard.init
    originalSetKeyboardLayout = VirtualKeyboard.setKeyboardLayout
    
    VirtualKeyboard.addChar = function(self, key)
        if not handleAddChar(key) then
            originalAddChar(self, key)
        end
    end
    
    VirtualKeyboard.delChar = function(self)
        if pinyin_enabled and #current_pinyin > 0 then
            current_pinyin = current_pinyin:sub(1, -2)
            rebuildFirstRow()
            return
        else
            originalDelChar(self)
        end
    end
    
    VirtualKeyboard.setKeyboardLayout = function(self, layout)
        originalSetKeyboardLayout(self, layout)
        if layout == "zh_CN"  then
            enablePinyinFeatures()
        else
            disablePinyinFeatures()
        end
    end
    
    VirtualKeyboard.init = function(self, ...)
        originalInit(self, ...)
        current_keyboard = self
        
        updateKeyWidthMode()
        
        current_pinyin = ""
        current_candidates = nil
        current_page = 1
        total_pages = 1
        
        if self.inputbox then
            current_inputbox = self.inputbox
            if current_ime then
                current_ime._inputbox = self.inputbox
            end
        end
        
        if key_width_mode == "fixed" then
            saveCandidateKeyReferences(self)
        end
        
        local current_layout = self:getKeyboardLayout()
        if current_layout == "zh_CN" then
            enablePinyinFeatures()
            
            -- 中文键盘：设置空格键长按上屏拼音（仅当功能开启时）
            if getSpaceCommit() then
                for _, row in ipairs(self.layout) do
                    for _, key in ipairs(row) do
                        if key.label == " " or (key.key and key.key == " ") then
                            key.hold_callback = function()
                                if current_pinyin ~= "" then
                                    commitPinyinText()
                                end
                            end
                            break
                        end
                    end
                end
            end
        else
            disablePinyinFeatures()
        end
    end
    
    class_hooked = true
    logger.info("[CANDIDATE_BAR] 补丁安装完成，宽度模式: " .. key_width_mode)
    return true
end

local function applyPatch()
    if patched then
        return
    end
    
    if hookVirtualKeyboard() then
        patched = true
    end
end

UIManager:scheduleIn(0.5, applyPatch)
return true
