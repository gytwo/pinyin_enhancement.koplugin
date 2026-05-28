-- lexicon_manager.lua
-- 码表管理公共模块

local lfs = require("libs/libkoreader-lfs")
local DataStorage = require("datastorage")
local logger = require("logger")

local M = {}

-- 文件名到中文名称的映射
local lexicon_display_names = {
    ["Classical Poetry.lua"] = "古诗词词库",
    ["Couplet.lua"] = "对联词库",
    ["Finance.lua"] = "财经金融词库",
    ["Ideological.lua"] = "思政专业术语词库",
    ["Idiom"] = "成语俗语词库",
    ["Legal.lua"] = "法律词库",
    ["Neologisms.lua"] = "新词集锦词库",
    ["Three-Character Idiom.lua"] = "三字成语词库",
    ["WittySaying.lua"] = "歇后语词库",
}

-- 获取显示名称
function M.getDisplayName(filename)
    return lexicon_display_names[filename] or filename:gsub("%.lua$", "")
end

-- 获取 lexicon 目录路径
function M.getLexiconDir()
    local plugin_dir = DataStorage:getDataDir() .. "/plugins/pinyin_enhancement.koplugin/"
    return plugin_dir .. "lexicon/"
end

-- 扫描所有码表（文件或目录）
function M.scanLexiconFiles()
    local lexicon_dir = M.getLexiconDir()
    local attr = lfs.attributes(lexicon_dir)
    if not attr or attr.mode ~= "directory" then
        logger.warn("[LEXICON_MANAGER] 目录不存在: " .. lexicon_dir)
        return {}
    end
    
    local items = {}
    
    -- 扫描根目录下的 .lua 文件
    for file in lfs.dir(lexicon_dir) do
        if file:match("%.lua$") then
            table.insert(items, file)
        end
    end
    
    -- 检查 Idiom 子目录是否存在
    local idiom_dir = lexicon_dir .. "Idiom"
    local idiom_attr = lfs.attributes(idiom_dir)
    if idiom_attr and idiom_attr.mode == "directory" then
        -- 检查目录下是否有 .lua 文件
        local has_files = false
        for file in lfs.dir(idiom_dir) do
            if file:match("%.lua$") then
                has_files = true
                break
            end
        end
        if has_files then
            table.insert(items, "Idiom")
        end
    end
    
    table.sort(items)
    logger.info("[LEXICON_MANAGER] 扫描到 " .. #items .. " 个码表: " .. table.concat(items, ", "))
    return items
end

-- 获取已启用的码表列表
function M.getEnabledLexicons()
    local enabled = G_reader_settings:readSetting("pinyin_enabled_lexicons")
    if enabled == nil then
        return {}
    end
    return enabled
end

-- 保存启用的码表列表
function M.setEnabledLexicons(enabled_list)
    G_reader_settings:saveSetting("pinyin_enabled_lexicons", enabled_list)
end

-- 加载单个码表文件
function M.loadLexiconFile(filepath)
    local ok, data = pcall(dofile, filepath)
    if ok and data and type(data) == "table" then
        return data
    end
    return nil
end

-- 加载目录下所有码表文件
function M.loadLexiconDirectory(dirpath)
    local combined_data = {}
    local count = 0
    
    for file in lfs.dir(dirpath) do
        if file:match("%.lua$") then
            local filepath = dirpath .. "/" .. file
            local ok, data = pcall(dofile, filepath)
            if ok and data and type(data) == "table" then
                for k, v in pairs(data) do
                    combined_data[k] = v
                end
                count = count + 1
                logger.info("[LEXICON_MANAGER]   加载: " .. file)
            else
                logger.warn("[LEXICON_MANAGER]   加载失败: " .. file)
            end
        end
    end
    
    if count > 0 then
        local entry_count = 0
        for _ in pairs(combined_data) do entry_count = entry_count + 1 end
        logger.info("[LEXICON_MANAGER] 目录加载完成，共 " .. count .. " 个文件，" .. entry_count .. " 个条目")
    end
    
    return combined_data
end

-- 加载所有启用的码表数据
function M.loadEnabledLexiconsData()
    local enabled_items = M.getEnabledLexicons()
    if #enabled_items == 0 then
        logger.info("[LEXICON_MANAGER] 没有启用的额外码表")
        return {}
    end
    
    logger.info("[LEXICON_MANAGER] 启用的码表: " .. table.concat(enabled_items, ", "))
    
    local lexicon_dir = M.getLexiconDir()
    local loaded_data = {}
    
    for _, item in ipairs(enabled_items) do
        local path = lexicon_dir .. item
        local attr = lfs.attributes(path)
        
        if attr and attr.mode == "directory" then
            -- 是目录，加载目录下所有文件
            logger.info("[LEXICON_MANAGER] 加载码表目录: " .. item)
            local data = M.loadLexiconDirectory(path)
            if data and next(data) then
                loaded_data[item] = data
                logger.info("[LEXICON_MANAGER] ✓ " .. item .. " 加载成功")
            else
                logger.warn("[LEXICON_MANAGER] ✗ " .. item .. " 加载失败（无有效数据）")
            end
        elseif attr and attr.mode == "file" then
            -- 是文件，正常加载
            logger.info("[LEXICON_MANAGER] 加载码表文件: " .. item)
            local data = M.loadLexiconFile(path)
            if data then
                loaded_data[item] = data
                logger.info("[LEXICON_MANAGER] ✓ " .. item .. " 加载成功")
            else
                logger.warn("[LEXICON_MANAGER] ✗ " .. item .. " 加载失败")
            end
        else
            logger.warn("[LEXICON_MANAGER] 不存在: " .. path)
        end
    end
    
    return loaded_data
end

return M