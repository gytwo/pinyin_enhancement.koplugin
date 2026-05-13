-- pinyin_update.lua
-- 拼音增强插件在线更新模块
-- 支持 Gitee + GitHub 双源，优先使用手动上传的附件

local logger = require("logger")
local UIManager = require("ui/uimanager")
local Notification = require("ui/widget/notification")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local gettext = require("gettext")
local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("json")

local M = {}

-- 仓库信息
local REPO_OWNER = "gytwo"
local REPO_NAME = "pinyin_enhancement.koplugin"

-- 手动上传的附件文件名
local MANUAL_ZIP_NAME = "pinyin_enhancement.koplugin.zip"

-- 定义更新源
local UPDATE_SOURCES = {
    gitee = {
        api_url = "https://gitee.com/api/v5/repos/%s/%s/releases",
        download_url_pattern = "https://gitee.com/%s/%s/releases/download/%s/%s.zip",
    },
    github = {
        api_url = "https://api.github.com/repos/%s/%s/releases",
    }
}

local Device = require("device")
local is_android = Device:isAndroid()

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

-- 通用 API 请求函数
local function request_api(url)
    logger.info("PinyinEnhancement: 请求 URL: " .. url)
    local response = {}
    local ok, err = pcall(function()
        return http.request{
            url = url,
            sink = ltn12.sink.table(response),
            headers = {
                ["User-Agent"] = "KOReader-PinyinEnhancement",
                ["Accept"] = "application/json",
            }
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
    local success, data = pcall(json.decode, response_str)
    if not success or not data then
        logger.warn("PinyinEnhancement: JSON 解析失败")
        return nil
    end
    return data
end

-- 从指定源获取版本列表
function M.get_versions_from_source(source, page)
    local api_url = string.format(source.api_url, REPO_OWNER, REPO_NAME)
    local url = api_url .. "?page=" .. tostring(page) .. "&per_page=100"
    return request_api(url)
end

-- 从所有源获取版本（自动切换）
function M.get_all_versions()
    local all_versions = {}
    -- 优先尝试 Gitee
    local page = 1
    while true do
        local data = M.get_versions_from_source(UPDATE_SOURCES.gitee, page)
        if not data or #data == 0 then
            break
        end
        for _, release in ipairs(data) do
            local tag_name = release.tag_name or release.name
            if tag_name then
                local zip_url = nil
                -- 优先查找手动上传的附件
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
                })
            end
        end
        if #data < 100 then
            break
        end
        page = page + 1
    end
    
    -- 如果 Gitee 获取失败（没有数据），则尝试 GitHub
    if #all_versions == 0 then
        logger.info("PinyinEnhancement: Gitee 无数据，切换到 GitHub")
        page = 1
        while true do
            local data = M.get_versions_from_source(UPDATE_SOURCES.github, page)
            if not data or #data == 0 then
                break
            end
            for _, release in ipairs(data) do
                local tag_name = release.tag_name or release.name
                if tag_name then
                    local zip_url = nil
                    -- 优先查找手动上传的附件
                    if release.assets then
                        for _, asset in ipairs(release.assets) do
                            if asset.name == MANUAL_ZIP_NAME then
                                zip_url = asset.browser_download_url
                                break
                            end
                        end
                    end
                    -- 没有手动附件，使用 zipball_url
                    if not zip_url and release.zipball_url then
                        zip_url = release.zipball_url
                    end
                    table.insert(all_versions, {
                        tag = tag_name,
                        url = zip_url,
                        body = release.body,
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

-- 获取最新版本（自动切换源）
function M.get_latest_version()
    -- 优先尝试 Gitee
    local data = request_api(string.format(UPDATE_SOURCES.gitee.api_url .. "/latest", REPO_OWNER, REPO_NAME))
    if not data or not data.tag_name then
        logger.info("PinyinEnhancement: Gitee 获取最新版本失败，切换到 GitHub")
        data = request_api(string.format(UPDATE_SOURCES.github.api_url .. "/latest", REPO_OWNER, REPO_NAME))
    end
    
    if not data then
        return nil, nil, "网络请求异常"
    end
    
    local tag_name = data.tag_name or data.name
    if not tag_name then
        return nil, nil, "未找到版本号"
    end
    
    logger.info("PinyinEnhancement: 最新版本: " .. tag_name)
    
    local zip_url = nil
    -- 优先查找手动上传的附件
    if data.assets then
        for _, asset in ipairs(data.assets) do
            if asset.name == MANUAL_ZIP_NAME then
                zip_url = asset.browser_download_url
                logger.info("PinyinEnhancement: 使用手动上传的 ZIP 包")
                break
            end
        end
    end
    -- 没有手动附件，使用 zipball_url
    if not zip_url and data.zipball_url then
        zip_url = data.zipball_url
        logger.info("PinyinEnhancement: 使用 GitHub 自动生成的源码包")
    end
    
    return tag_name, zip_url, data.body
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

function M.download_update(download_url)
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
    
    local cmd = string.format("curl -L -o '%s' '%s' 2>/dev/null", zip_path, download_url)
    local result = os.execute(cmd)
    
    if result ~= 0 then
        cmd = string.format("wget --max-redirect=5 -O '%s' '%s' 2>/dev/null", zip_path, download_url)
        result = os.execute(cmd)
    end
    
    if result ~= 0 then
        cmd = string.format("busybox wget -O '%s' '%s' 2>/dev/null", zip_path, download_url)
        result = os.execute(cmd)
    end
    
    if result ~= 0 then
        os.remove(zip_path)
        return nil, "下载失败"
    end
    
    local size = lfs.attributes(zip_path, "size") or 0
    if size < 1000 then
        os.remove(zip_path)
        return nil, "下载的文件无效"
    end
    
    logger.info("PinyinEnhancement: 下载完成，大小: " .. size .. " 字节")
    return zip_path
end

-- 安装更新（自动处理嵌套目录）
function M.install_update(zip_path)
    logger.info("PinyinEnhancement: 开始安装更新，ZIP路径: " .. zip_path)
    
    -- 检查 ZIP 文件是否存在
    if lfs.attributes(zip_path, "mode") ~= "file" then
        logger.error("PinyinEnhancement: ZIP 文件不存在: " .. zip_path)
        return false
    end
    
    -- 创建临时目录（放在插件目录外面，避免被删除）
    local temp_dir
    if is_android then
        local data_dir = DataStorage:getDataDir()
        if data_dir:sub(1, 2) == "./" then
            data_dir = data_dir:sub(3)
        elseif data_dir:sub(1, 1) == "." then
            data_dir = data_dir:sub(2)
        end
        temp_dir = data_dir .. "plugins/.temp_pinyin_update"
    else
        temp_dir = "/tmp/.temp_pinyin_update"
    end
    
    os.execute(string.format("rm -rf '%s'", temp_dir))
    os.execute(string.format("mkdir -p '%s'", temp_dir))
    
    -- 解压到临时目录
    local result = os.execute(string.format("unzip -o -q '%s' -d '%s' 2>/dev/null", zip_path, temp_dir))
    if result ~= 0 then
        result = os.execute(string.format("busybox unzip -o -q '%s' -d '%s' 2>/dev/null", zip_path, temp_dir))
    end
    
    if result ~= 0 then
        logger.error("PinyinEnhancement: 解压失败")
        os.execute(string.format("rm -rf '%s'", temp_dir))
        os.remove(zip_path)
        return false
    end
    
    logger.info("PinyinEnhancement: 解压成功，正在处理目录结构...")
    
    -- 处理嵌套目录：如果临时目录下只有一个子目录，就把里面的内容移出来
    local files = {}
    local dirs = {}
    for file in lfs.dir(temp_dir) do
        if file ~= "." and file ~= ".." then
            local path = temp_dir .. "/" .. file
            local attr = lfs.attributes(path)
            if attr.mode == "directory" then
                table.insert(dirs, file)
            else
                table.insert(files, file)
            end
        end
    end
    
    -- 如果只有一层目录且没有文件，说明是嵌套的
    if #files == 0 and #dirs == 1 then
        local nested_dir = temp_dir .. "/" .. dirs[1]
        logger.info("PinyinEnhancement: 检测到嵌套目录，正在处理...")
        for file in lfs.dir(nested_dir) do
            if file ~= "." and file ~= ".." then
                os.execute(string.format("mv '%s/%s' '%s/'", nested_dir, file, temp_dir))
            end
        end
        os.execute(string.format("rm -rf '%s'", nested_dir))
    end
    
    -- 删除原插件目录
    logger.info("PinyinEnhancement: 删除原插件目录: " .. plugin_dir)
    os.execute(string.format("rm -rf '%s'", plugin_dir))
    os.execute(string.format("mkdir -p '%s'", plugin_dir))
    
    -- 移动所有文件到插件目录
    for file in lfs.dir(temp_dir) do
        if file ~= "." and file ~= ".." then
            os.execute(string.format("mv '%s/%s' '%s/'", temp_dir, file, plugin_dir))
        end
    end
    
    -- 清理临时目录
    os.execute(string.format("rm -rf '%s'", temp_dir))
    os.remove(zip_path)
    
    logger.info("PinyinEnhancement: 更新安装成功")
    return true
end

local _version_dialog = nil

local function show_version_choice(versions, current_version)
    local buttons = {}
    
    for _, v in ipairs(versions) do
        local is_current = (v.tag == current_version)
        local button_text = is_current and string.format(gettext("当前版本: %s (重新下载)"), v.tag) or string.format(gettext("回退到 %s"), v.tag)
        
        table.insert(buttons, {
            {
                text = button_text,
                callback = function()
                    if _version_dialog then
                        UIManager:close(_version_dialog)
                        _version_dialog = nil
                    end
                    M.perform_update(v.url, v.tag)
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

function M.check_for_updates(silent)
    if not NetworkMgr:isOnline() then
        if not silent then
            UIManager:show(Notification:new{
                text = gettext("无网络连接，无法检查更新"),
                timeout = 2
            })
        end
        return
    end
    
    if not silent then
        UIManager:show(Notification:new{
            text = gettext("正在检查更新..."),
            timeout = 1
        })
    end
    
    UIManager:scheduleIn(1, function()
        local latest_version, download_url, release_notes = M.get_latest_version()
        
        if not latest_version then
            if not silent then
                UIManager:show(Notification:new{
                    text = gettext("检查更新失败，请稍后重试"),
                    timeout = 2
                })
            end
            return
        end
        
        local current_version = get_current_version()
        
        if M.is_newer_version(current_version, latest_version) then
            local message = string.format(gettext("发现新版本: %s\n当前版本: %s\n\n是否下载并安装更新？"), latest_version, current_version)
            
            if release_notes and release_notes ~= "" then
                local notes = release_notes:sub(1, 200)
                message = message .. "\n\n更新内容:\n" .. notes
                if #release_notes > 200 then
                    message = message .. "..."
                end
            end
            
            UIManager:show(ConfirmBox:new{
                text = message,
                ok_text = gettext("更新"),
                cancel_text = gettext("稍后"),
                ok_callback = function()
                    M.perform_update(download_url, latest_version)
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
                        local all_versions = M.get_all_versions()
                        if not all_versions or #all_versions == 0 then
                            UIManager:show(Notification:new{
                                text = gettext("获取版本列表失败"),
                                timeout = 2
                            })
                            return
                        end
                        show_version_choice(all_versions, current_version)
                    end)
                end
            })
        end
    end)
end

function M.perform_update(download_url, target_version)
    if not download_url then
        UIManager:show(Notification:new{
            text = gettext("未找到更新包下载地址"),
            timeout = 2
        })
        return
    end
    
    local version_text = target_version and (" (" .. target_version .. ")") or ""
    
    UIManager:show(Notification:new{
        text = gettext("正在下载更新") .. version_text .. "...",
        timeout = 1
    })
    
    local zip_path, err = M.download_update(download_url)
    
    if not zip_path then
        UIManager:show(Notification:new{
            text = err or gettext("下载失败，请稍后重试"),
            timeout = 3
        })
        return
    end
    
    UIManager:show(Notification:new{
        text = gettext("正在安装更新") .. version_text .. "...",
        timeout = 1
    })
    
    local success = M.install_update(zip_path)
    
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
end

return M
