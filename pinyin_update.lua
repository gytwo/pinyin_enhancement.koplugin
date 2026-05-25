-- pinyin_update.lua
-- 拼音增强插件在线更新模块
-- 支持 GitHub Latest、GitHub Pre-release、Gitee Latest

local logger = require("logger")
local UIManager = require("ui/uimanager")
local Notification = require("ui/widget/notification")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local gettext = require("gettext")

local M = {}

local REPO_OWNER = "gytwo"
local REPO_NAME = "pinyin_enhancement.koplugin"
local MANUAL_ZIP_NAME = "pinyin_enhancement.koplugin.zip"

local Device = require("device")
local is_android = Device:isAndroid()

-- 定义更新源（三种选项）
local SOURCES = {
    github_latest = {
        name = "GitHub (Latest)",
        api_url = "https://api.github.com/repos/%s/%s/releases/latest",
        list_url = "https://api.github.com/repos/%s/%s/releases",
        type = "github",
        prerelease = false,
    },
    github_prerelease = {
        name = "GitHub (Pre-release)",
        api_url = "https://api.github.com/repos/%s/%s/releases",
        list_url = "https://api.github.com/repos/%s/%s/releases",
        type = "github",
        prerelease = true,
    },
    gitee_latest = {
        name = "Gitee (Latest)",
        api_url = "https://gitee.com/api/v5/repos/%s/%s/releases/latest",
        list_url = "https://gitee.com/api/v5/repos/%s/%s/releases",
        type = "gitee",
        prerelease = false,
    },
}

-- 保存用户选择的更新源到设置
local function save_selected_source(source_key)
    G_reader_settings:saveSetting("pinyin_update_source", source_key)
end

-- 获取用户保存的更新源key
local function get_saved_source_key()
    local saved = G_reader_settings:readSetting("pinyin_update_source")
    if saved == "github_prerelease" then
        return "github_prerelease"
    elseif saved == "gitee_latest" then
        return "gitee_latest"
    else
        return "github_latest"  -- 默认
    end
end

-- 根据key获取source对象
local function get_source_by_key(key)
    if key == "github_prerelease" then
        return SOURCES.github_prerelease
    elseif key == "gitee_latest" then
        return SOURCES.gitee_latest
    else
        return SOURCES.github_latest
    end
end

-- 获取插件目录
local plugin_dir
local current_file_path = (...)

if is_android then
    local data_dir = DataStorage:getDataDir()
    if data_dir:sub(1, 2) == "./" then
        data_dir = data_dir:sub(3)
    elseif data_dir:sub(1, 1) == "." then
        data_dir = data_dir:sub(2)
    end
    if data_dir:sub(-1) ~= "/" then
        data_dir = data_dir .. "/"
    end
    plugin_dir = data_dir .. "plugins/pinyin_enhancement.koplugin/"
else
    plugin_dir = current_file_path:match("(.*/)pinyin_enhancement.koplugin/")
    if not plugin_dir then
        local data_dir = DataStorage:getDataDir()
        if data_dir:sub(1, 2) == "./" then
            data_dir = data_dir:sub(3)
        elseif data_dir:sub(1, 1) == "." then
            data_dir = data_dir:sub(2)
        end
        plugin_dir = data_dir .. "plugins/pinyin_enhancement.koplugin/"
    end
end

if plugin_dir:sub(-1) == "/" then
    plugin_dir = plugin_dir:sub(1, -2)
end

logger.info("PinyinEnhancement: 插件目录: " .. plugin_dir)

local function get_current_version()
    local meta_path = plugin_dir .. "/_meta.lua"
    local f = io.open(meta_path, "r")
    if not f then
        return "v1.0"
    end
    local content = f:read("*all")
    f:close()
    local version = content:match('version%s*=%s*"([^"]+)"')
    if not version then
        version = content:match("version%s*=%s*'([^']+)'")
    end
    return version or "v1.0"
end

-- HTTP 请求（带超时）
local function request_url(url, timeout)
    timeout = timeout or 10
    logger.info("PinyinEnhancement: 请求 URL: " .. url)
    
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    local response = {}
    local ok, err = pcall(function()
        return http.request{
            url = url,
            sink = ltn12.sink.table(response),
            headers = {
                ["User-Agent"] = "KOReader-PinyinEnhancement",
                ["Accept"] = "application/json",
            },
            timeout = timeout,
        }
    end)
    
    if not ok then
        logger.warn("PinyinEnhancement: HTTP 请求异常: " .. tostring(err))
        return nil
    end
    if not response or #response == 0 then
        logger.warn("PinyinEnhancement: 响应为空")
        return nil
    end
    
    local response_str = table.concat(response)
    local json = require("json")
    local success, data = pcall(json.decode, response_str)
    if not success or not data then
        logger.warn("PinyinEnhancement: JSON 解析失败")
        return nil
    end
    return data
end

-- 获取最新版本信息（从 GitHub）
local function get_latest_from_github(source)
    local url = string.format(source.api_url, REPO_OWNER, REPO_NAME)
    
    if source.prerelease then
        -- Pre-release 模式：获取所有 releases，筛选 prerelease
        local data = request_url(url, 15)
        if not data or #data == 0 then
            return nil, nil, nil, gettext("获取版本信息失败")
        end
        
        local latest_prerelease = nil
        for _, release in ipairs(data) do
            if release.prerelease == true then
                if not latest_prerelease then
                    latest_prerelease = release
                else
                    -- 比较创建时间，取最新的
                    local current_time = os.time()
                    local release_time = os.time({
                        year = tonumber(release.created_at:sub(1,4)),
                        month = tonumber(release.created_at:sub(6,7)),
                        day = tonumber(release.created_at:sub(9,10)),
                        hour = tonumber(release.created_at:sub(12,13)) or 0,
                        min = tonumber(release.created_at:sub(15,16)) or 0,
                        sec = tonumber(release.created_at:sub(18,19)) or 0,
                    })
                    local latest_time = os.time({
                        year = tonumber(latest_prerelease.created_at:sub(1,4)),
                        month = tonumber(latest_prerelease.created_at:sub(6,7)),
                        day = tonumber(latest_prerelease.created_at:sub(9,10)),
                        hour = tonumber(latest_prerelease.created_at:sub(12,13)) or 0,
                        min = tonumber(latest_prerelease.created_at:sub(15,16)) or 0,
                        sec = tonumber(latest_prerelease.created_at:sub(18,19)) or 0,
                    })
                    if release_time > latest_time then
                        latest_prerelease = release
                    end
                end
            end
        end
        
        if not latest_prerelease then
            return nil, nil, nil, gettext("未找到预发布版本")
        end
        
        return M._parse_release_data(latest_prerelease, source)
    else
        -- Latest 模式：直接获取 latest release
        local data = request_url(url, 15)
        if not data or not data.tag_name then
            return nil, nil, nil, gettext("获取版本信息失败")
        end
        return M._parse_release_data(data, source)
    end
end

-- 获取最新版本信息（从 Gitee）
local function get_latest_from_gitee(source)
    local url = string.format(source.api_url, REPO_OWNER, REPO_NAME)
    local data = request_url(url, 15)
    
    if not data or not data.tag_name then
        return nil, nil, nil, gettext("获取版本信息失败")
    end
    
    return M._parse_release_data(data, source)
end

-- 解析 release 数据，提取下载地址
function M._parse_release_data(data, source)
    local tag_name = data.tag_name or data.name
    logger.info("PinyinEnhancement: 最新版本: " .. tag_name .. " (来源: " .. source.name .. ")")
    
    -- 获取下载地址
    local zip_url = nil
    if data.assets then
        for _, asset in ipairs(data.assets) do
            if asset.name == MANUAL_ZIP_NAME then
                zip_url = asset.browser_download_url
                logger.info("PinyinEnhancement: 使用手动上传的 ZIP 包")
                break
            end
        end
    end
    if not zip_url and data.zipball_url then
        zip_url = data.zipball_url
        logger.info("PinyinEnhancement: 使用自动生成的源码包")
    end
    
    return tag_name, zip_url, source.name, data.body
end

-- 获取最新版本信息（根据源类型）
local function get_latest_version_from_source(source)
    if source.type == "github" then
        return get_latest_from_github(source)
    else
        return get_latest_from_gitee(source)
    end
end

-- 获取版本列表（用于回退）
local function get_all_versions_from_source(source)
    local all_versions = {}
    local page = 1
    
    local url = string.format(source.list_url, REPO_OWNER, REPO_NAME)
    
    if source.type == "github" and source.prerelease then
        -- GitHub Pre-release 模式：只获取 prerelease
        local data = request_url(url .. "?per_page=100", 15)
        if not data or #data == 0 then
            return {}
        end
        
        for _, release in ipairs(data) do
            if release.prerelease == true then
                local tag_name = release.tag_name or release.name
                if tag_name then
                    local zip_url = nil
                    if release.assets then
                        for _, asset in ipairs(release.assets) do
                            if asset.name == MANUAL_ZIP_NAME then
                                zip_url = asset.browser_download_url
                                break
                            end
                        end
                    end
                    table.insert(all_versions, {
                        tag = tag_name,
                        url = zip_url,
                        body = release.body,
                        source = source.name,
                    })
                end
            end
        end
    elseif source.type == "github" then
        -- GitHub Latest 模式：获取所有正式版
        local data = request_url(url .. "?per_page=100", 15)
        if not data or #data == 0 then
            return {}
        end
        
        for _, release in ipairs(data) do
            if release.prerelease ~= true then
                local tag_name = release.tag_name or release.name
                if tag_name then
                    local zip_url = nil
                    if release.assets then
                        for _, asset in ipairs(release.assets) do
                            if asset.name == MANUAL_ZIP_NAME then
                                zip_url = asset.browser_download_url
                                break
                            end
                        end
                    end
                    table.insert(all_versions, {
                        tag = tag_name,
                        url = zip_url,
                        body = release.body,
                        source = source.name,
                    })
                end
            end
        end
    else
        -- Gitee：分页获取
        while true do
            local paged_url = url .. "?page=" .. tostring(page) .. "&per_page=100"
            local data = request_url(paged_url, 15)
            
            if not data or #data == 0 then
                break
            end
            
            for _, release in ipairs(data) do
                local tag_name = release.tag_name or release.name
                if tag_name then
                    local zip_url = nil
                    if release.assets then
                        for _, asset in ipairs(release.assets) do
                            if asset.name == MANUAL_ZIP_NAME then
                                zip_url = asset.browser_download_url
                                break
                            end
                        end
                    end
                    table.insert(all_versions, {
                        tag = tag_name,
                        url = zip_url,
                        body = release.body,
                        source = source.name,
                    })
                end
            end
            
            if #data < 100 then
                break
            end
            page = page + 1
        end
    end
    
    return all_versions
end

function M.is_newer_version(current, latest)
    if current == latest then return false end
    
    local cur = current:gsub("^v", "")
    local lat = latest:gsub("^v", "")
    
    local cur_parts = {}
    for part in cur:gmatch("[^.]+") do
        table.insert(cur_parts, tonumber(part) or 0)
    end
    local lat_parts = {}
    for part in lat:gmatch("[^.]+") do
        table.insert(lat_parts, tonumber(part) or 0)
    end
    
    for i = 1, math.max(#cur_parts, #lat_parts) do
        local cur_part = cur_parts[i] or 0
        local lat_part = lat_parts[i] or 0
        if lat_part > cur_part then
            return true
        elseif lat_part < cur_part then
            return false
        end
    end
    return false
end

-- 显示临时提示
local function show_msg(text, timeout)
    UIManager:show(Notification:new{
        text = text,
        timeout = timeout or 2,
    })
end

-- 下载更新
local function download_update(download_url)
    local zip_path
    if is_android then
        local data_dir = DataStorage:getDataDir()
        if data_dir:sub(1, 2) == "./" then
            data_dir = data_dir:sub(3)
        elseif data_dir:sub(1, 1) == "." then
            data_dir = data_dir:sub(2)
        end
        local plugins_dir = data_dir .. "plugins"
        zip_path = plugins_dir .. "/pinyin_enhancement.koplugin.zip"
        if lfs.attributes(plugins_dir, "mode") ~= "directory" then
            os.execute("mkdir -p " .. plugins_dir)
        end
    else
        zip_path = "/tmp/pinyin_enhancement.koplugin.zip"
    end
    
    -- 方式1: curl
    local cmd = string.format("curl -L --max-time 15 -o '%s' '%s' 2>/dev/null", zip_path, download_url)
    local result = os.execute(cmd)
    
    -- 方式2: wget
    if result ~= 0 then
        cmd = string.format("wget --timeout=15 -O '%s' '%s' 2>/dev/null", zip_path, download_url)
        result = os.execute(cmd)
    end
    
    -- 方式3: busybox wget
    if result ~= 0 then
        cmd = string.format("busybox wget --timeout=15 -O '%s' '%s' 2>/dev/null", zip_path, download_url)
        result = os.execute(cmd)
    end
    
    if result ~= 0 then
        os.remove(zip_path)
        return nil, gettext("下载失败")
    end
    
    local size = lfs.attributes(zip_path, "size") or 0
    if size < 1000 then
        show_msg(gettext("下载的文件无效"), 3)
        os.remove(zip_path)
        return nil, gettext("下载的文件无效")
    end
    
    return zip_path
end

-- 安装更新
local function install_update(zip_path)
    if is_android then
        if lfs.attributes(plugin_dir, "mode") ~= "directory" then
            os.execute("mkdir -p " .. plugin_dir)
        end
        
        local result = os.execute(string.format("unzip -o -q '%s' -d '%s' 2>/dev/null", zip_path, plugin_dir))
        
        if result ~= 0 then
            result = os.execute(string.format("busybox unzip -o -q '%s' -d '%s' 2>/dev/null", zip_path, plugin_dir))
        end
        
        os.remove(zip_path)
        
        if result == 0 then
            logger.info("PinyinEnhancement: 自动安装成功")
            return true
        else
            logger.warn("PinyinEnhancement: 自动安装失败")
            return false
        end
    else
        local result = os.execute(string.format("unzip -o %s -d %s", zip_path, plugin_dir))
        
        if result ~= 0 then
            result = os.execute(string.format("/usr/bin/unzip -o %s -d %s", zip_path, plugin_dir))
        end
        
        os.remove(zip_path)
        
        if result == 0 then
            logger.info("PinyinEnhancement: 更新安装成功")
        else
            logger.warn("PinyinEnhancement: 更新安装失败")
        end
        
        return result == 0
    end
end

-- 版本选择对话框
local _version_dialog = nil

local function show_version_choice(versions, current_version, source)
    local buttons = {}
    
    for _, v in ipairs(versions) do
        local is_current = (v.tag == current_version)
        local display_text = v.tag
        if v.source then
            display_text = display_text .. " [" .. v.source .. "]"
        end
        local button_text = is_current and string.format(gettext("当前版本: %s (重新下载)"), display_text) or string.format(gettext("回退到 %s"), display_text)
        
        table.insert(buttons, {
            {
                text = button_text,
                callback = function()
                    if _version_dialog then
                        UIManager:close(_version_dialog)
                        _version_dialog = nil
                    end
                    M.perform_update(v.url, v.tag, source)
                end
            }
        })
    end
    
    table.insert(buttons, {})
    table.insert(buttons, {
        {
            text = gettext("取消"),
            callback = function()
                if _version_dialog then
                    UIManager:close(_version_dialog)
                    _version_dialog = nil
                end
            end
        }
    })
    
    local ButtonDialog = require("ui/widget/buttondialog")
    local Screen = Device.screen
    _version_dialog = ButtonDialog:new{
        title = gettext("选择要下载的版本"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
    }
    UIManager:show(_version_dialog)
end

-- 选择更新源的对话框
local function show_source_selection_dialog(on_selected)
    local ButtonDialog = require("ui/widget/buttondialog")
    local Screen = Device.screen
    
    local saved_key = get_saved_source_key()
    
    local dialog
    local buttons = {
        {
            {
                text = (saved_key == "github_latest" and "✓ " or "  ") .. gettext("GitHub (正式版)"),
                callback = function()
                    UIManager:close(dialog)
                    save_selected_source("github_latest")
                    if on_selected then on_selected(get_source_by_key("github_latest")) end
                end
            }
        },
        {
            {
                text = (saved_key == "github_prerelease" and "✓ " or "  ") .. gettext("GitHub (预发布版)"),
                callback = function()
                    UIManager:close(dialog)
                    save_selected_source("github_prerelease")
                    if on_selected then on_selected(get_source_by_key("github_prerelease")) end
                end
            }
        },
        {
            {
                text = (saved_key == "gitee_latest" and "✓ " or "  ") .. gettext("Gitee (正式版)"),
                callback = function()
                    UIManager:close(dialog)
                    save_selected_source("gitee_latest")
                    if on_selected then on_selected(get_source_by_key("gitee_latest")) end
                end
            }
        },
        {},
        {
            {
                text = gettext("取消"),
                callback = function()
                    UIManager:close(dialog)
                end
            }
        },
    }
    
    dialog = ButtonDialog:new{
        title = gettext("选择更新源"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
    }
    UIManager:show(dialog)
end

-- 执行更新检查
local function do_check_updates(source)
    if not NetworkMgr:isOnline() then
        show_msg(gettext("无网络连接，无法检查更新"), 2)
        return
    end
    
    show_msg(gettext("正在检查更新..."), 1)
    
    UIManager:scheduleIn(0.5, function()
        local latest_version, download_url, source_used, err = get_latest_version_from_source(source)
        
        if not latest_version then
            show_msg(err or gettext("检查更新失败"), 3)
            return
        end
        
        local current_version = get_current_version()
        
        if M.is_newer_version(current_version, latest_version) then
            local source_text = " (" .. source_used .. ")"
            local message = string.format(gettext("发现新版本: %s%s\n当前版本: %s\n\n是否下载并安装更新？"), latest_version, source_text, current_version)
            
            UIManager:show(ConfirmBox:new{
                text = message,
                ok_text = gettext("更新"),
                cancel_text = gettext("稍后"),
                ok_callback = function()
                    M.perform_update(download_url, latest_version, source)
                end
            })
        else
            UIManager:show(ConfirmBox:new{
                text = string.format(gettext("当前已是最新版本 (%s)\n\n是否需要回退到之前的版本？"), current_version),
                ok_text = gettext("回退"),
                cancel_text = gettext("取消"),
                ok_callback = function()
                    UIManager:show(InfoMessage:new{
                        text = gettext("正在获取版本列表..."),
                        timeout = 1
                    })
                    
                    UIManager:scheduleIn(0.5, function()
                        local all_versions = get_all_versions_from_source(source)
                        if not all_versions or #all_versions == 0 then
                            show_msg(gettext("获取版本列表失败"), 2)
                            return
                        end
                        show_version_choice(all_versions, current_version, source)
                    end)
                end
            })
        end
    end)
end

-- 检查更新（主入口）
function M.check_for_updates(silent, plugin)
    show_source_selection_dialog(function(selected_source)
        do_check_updates(selected_source)
    end)
end

function M.perform_update(download_url, target_version, source)
    if not download_url then
        UIManager:show(Notification:new{
            text = gettext("未找到更新包下载地址"),
            timeout = 2
        })
        return
    end
    
    local version_text = target_version and (" (" .. target_version .. ")") or ""
    local source_text = source and (" [" .. source.name .. "]") or ""
    
    UIManager:show(Notification:new{
        text = gettext("正在下载更新") .. version_text .. source_text .. "...",
        timeout = 1
    })
    
    UIManager:scheduleIn(0.1, function()
        local zip_path, err = download_update(download_url)
        
        if not zip_path then
            UIManager:show(Notification:new{
                text = err or gettext("下载失败，请检查网络连接后重试"),
                timeout = 4
            })
            return
        end
        
        UIManager:show(Notification:new{
            text = gettext("正在安装更新") .. version_text .. "...",
            timeout = 1
        })
        
        UIManager:scheduleIn(0.1, function()
            local success = install_update(zip_path)
            
            if success then
                UIManager:show(ConfirmBox:new{
                    text = gettext("更新安装完成，需要重启 KOReader 才能生效。是否立即重启？"),
                    ok_text = gettext("重启"),
                    cancel_text = gettext("稍后"),
                    ok_callback = function()
                        UIManager:restartKOReader()
                    end
                })
            else
                if is_android then
                    local data_dir = DataStorage:getDataDir()
                    if data_dir:sub(1, 2) == "./" then
                        data_dir = data_dir:sub(3)
                    elseif data_dir:sub(1, 1) == "." then
                        data_dir = data_dir:sub(2)
                    end
                    UIManager:show(Notification:new{
                        text = string.format(gettext("自动安装失败，请手动解压 %splugins/pinyin_enhancement.koplugin.zip 到 plugins 目录后重启"), data_dir),
                        timeout = 5
                    })
                else
                    UIManager:show(Notification:new{
                        text = gettext("安装失败，请手动更新"),
                        timeout = 3
                    })
                end
            end
        end)
    end)
end

return M
