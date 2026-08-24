-- 2-quickcenter.lua - 快捷中心（Quick Center）for KOReader
-- 快捷操作 + 控制中心集成补丁：菜单录制、5 种动作类型、自定义图标、替换系统图标与 UI 字体
-- 安装：放入 koreader/patches/ 目录（文件名 2- 前缀为 late 加载优先级，勿改）
-- 卸载：删除本文件，同时删除 koreader/settings/quickcenter.lua（可选配置文件）

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local BD = require("ui/bidi")
local _ = require("gettext")
local datetime = require("datetime")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Dispatcher = require("dispatcher")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputText = require("ui/widget/inputtext")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local Menu = require("ui/widget/menu")
local PathChooser = require("ui/widget/pathchooser")
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Notification = require("ui/widget/notification")
local util = require("util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local Event = require("ui/event")
local IconWidget = require("ui/widget/iconwidget")
local FontList = require("fontlist")

logger.info("[QuickActions] 加载中...")

-- ============================================================
-- 全局状态
-- ============================================================
local openDispatcherPicker = nil
local _settings_dialog = nil
local sub_dialog = nil
local CONFIG_PATH = nil
local CONFIG_DATA = nil
local DEFAULT_CONFIG = nil
local MAX_SLOTS = 66

-- ============================================================
-- ButtonDialog 全局补丁：默认 10 行/页
-- ============================================================
local _orig_ButtonDialog_new = ButtonDialog.new
function ButtonDialog.new(_, ...)
    local args = {...}
    if type(args[1]) ~= "table" then args = {} else args = args[1] end
    if args.rows_per_page == nil then args.rows_per_page = 10 end
    return _orig_ButtonDialog_new(_, args)
end

-- ============================================================
-- 默认配置
-- ============================================================
DEFAULT_CONFIG = {
    qa_tab_icon = "star.empty",
    qa_enabled = true,
    qa_slots = { "wifi", "night", "rotate", "screenshot", "continue", "fontlist", "restart", "search", "qa_settings", "qa_add_button", "qa_new" },
    qa_frontlight = true,
    qa_warmth = true,
    qa_shape = "round",
    qa_bg = "flat",
    qa_labels = false,
    qa_label_scale_pct = 90,
    qa_settings_on_hold = true,
    qa_button_size_pct = 100,
    custom_list = {},
    custom = {},
    builtin_overrides = {},
    qa_context_filter = true,
    qa_auto_add_to_panel = true,
    qa_button_hold_edit = true,
    qa_slider_show_value = false,
    qa_slider_style = "line",
    qa_filter_initialized = false,
    qa_icon_overrides = {},
    ui_font_overrides = {},
    qa_shortcuts = {},
    qa_layout_enabled = false,
    qa_layout_rows = 2,
    qa_layout_cols = 4,
    saved_configs = {},
    version = 1,
}

-- ============================================================
-- 配置读写
-- ============================================================
local function getConfigPath()
    if CONFIG_PATH then return CONFIG_PATH end
    local ok, DataStorage = pcall(require, "datastorage")
    CONFIG_PATH = ok and DataStorage and DataStorage:getSettingsDir() .. "/quickcenter.lua" or "quickcenter.lua"
    return CONFIG_PATH
end

-- 序列化为 Lua 表字面量（转义反斜杠/引号/换行，避免写出非法配置）
local function serializeTable(t, indent)
    indent = indent or ""
    local lines, keys = { "{\n" }, {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    for i, k in ipairs(keys) do
        local v = t[k]
        local ks = type(k) == "string" and string.format('["%s"]', k) or string.format("[%s]", tostring(k))
        local vv
        if type(v) == "table" then
            vv = serializeTable(v, indent .. "  ")
        elseif type(v) == "string" then
            vv = '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r") .. '"'
        elseif type(v) == "number" or type(v) == "boolean" then
            vv = tostring(v)
        else
            vv = nil -- 跳过无法序列化的值
        end
        if vv then lines[#lines + 1] = string.format("%s  %s = %s,", indent, ks, vv) end
    end
    lines[#lines + 1] = indent .. "}"
    return table.concat(lines, "\n")
end

-- 原子写入：先写临时文件再改名，避免写入中断导致配置损坏
local function saveConfig()
    if not CONFIG_DATA then return end
    local tmp = CONFIG_PATH .. ".tmp"
    local f = io.open(tmp, "w")
    if f then
        f:write("return " .. serializeTable(CONFIG_DATA))
        f:close()
        os.rename(tmp, CONFIG_PATH)
    end
end

local function loadConfig()
    if CONFIG_DATA then return CONFIG_DATA end
    local path = getConfigPath()
    local f = io.open(path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            content = content:gsub("^\239\187\191", "") -- 去 BOM
            local chunk, err = load(content)
            if chunk then
                local ok, data = pcall(chunk)
                if ok and type(data) == "table" then
                    CONFIG_DATA = data
                    return CONFIG_DATA
                else
                    logger.warn("[QuickActions] pcall 失败:", err)
                end
            else
                logger.warn("[QuickActions] load 失败:", err)
            end
        end
        -- 配置损坏：备份后使用默认
        logger.warn("[QuickActions] 配置文件损坏，备份原文件后使用默认配置")
        pcall(function() os.rename(path, path .. ".bak") end)
        CONFIG_DATA = DEFAULT_CONFIG
        saveConfig()
        return CONFIG_DATA
    end
    logger.info("[QuickActions] 配置文件不存在，创建默认配置")
    CONFIG_DATA = DEFAULT_CONFIG
    saveConfig()
    return CONFIG_DATA
end

-- ============================================================
-- 配置访问
-- ============================================================
local function getSetting(key)
    local cfg = loadConfig()
    local val = cfg[key]
    if val ~= nil then return val end
    return DEFAULT_CONFIG[key]
end

local function setSetting(key, value)
    loadConfig()[key] = value
    saveConfig()
end

local function getBool(key)
    local val = getSetting(key)
    if type(val) == "boolean" then return val end
    return DEFAULT_CONFIG[key] == true
end
local function setBool(key, value) setSetting(key, value == true) end

local function getString(key)
    local val = getSetting(key)
    if type(val) == "string" then return val end
    return DEFAULT_CONFIG[key] or ""
end
local function setString(key, value) setSetting(key, value) end

local function getNumber(key)
    local val = getSetting(key)
    if type(val) == "number" then return val end
    return DEFAULT_CONFIG[key] or 0
end
local function setNumber(key, value) setSetting(key, value) end

local function getTable(key)
    local val = loadConfig()[key]
    if type(val) == "table" then return val end
    return DEFAULT_CONFIG[key] or {}
end

-- 深拷贝后落盘，避免外部修改直接污染配置
local function setTable(key, value)
    local json = require("json")
    loadConfig()[key] = json.decode(json.encode(value))
    saveConfig()
end

-- ============================================================
-- 对话框 / 面板管理
-- ============================================================
local function closeSettingsDialog()
    if _settings_dialog then
        UIManager:close(_settings_dialog)
        _settings_dialog = nil
    end
end

local function refreshQuickPanel(touch_menu)
    if touch_menu and touch_menu.updateItems then touch_menu:updateItems() end
end

-- ============================================================
-- 便捷配置访问
-- ============================================================
local function isQAEnabled() return getBool("qa_enabled") end
local function getQASlots()
    local slots = getSetting("qa_slots")
    return type(slots) == "table" and slots or DEFAULT_CONFIG.qa_slots
end
local function saveQASlots(slots) setSetting("qa_slots", slots) end
local function showFrontlight() return getBool("qa_frontlight") end
local function showWarmth() return getBool("qa_warmth") end
local function showSliderValue() return getBool("qa_slider_show_value") end
local function getSliderStyle() return getString("qa_slider_style") end
local function getShape() return getString("qa_shape") end
local function getBg() return getString("qa_bg") end
local function showLabels() return getBool("qa_labels") end
local function getLabelScalePct()
    return math.max(50, math.min(200, math.floor(getNumber("qa_label_scale_pct"))))
end
local function getLabelScale() return getLabelScalePct() / 100 end
local function buttonHoldEdit() return getBool("qa_button_hold_edit") end
local function settingsOnHold() return getBool("qa_settings_on_hold") end
local function getButtonSizePct()
    return math.max(60, math.min(150, math.floor(getNumber("qa_button_size_pct"))))
end

-- ============================================================
-- 插件 / 补丁扫描（独立实现，扫描结果缓存：插件列表运行期不变）
-- ============================================================
-- 菜单回调的桩对象：插件 addToMainMenu 会向其写入菜单项
local TOUCHMENU_STUB = {
    closeMenu = function() end,
    onClose = function() end,
    updateItems = function() end,
    handleEvent = function() return false end,
}

local PluginScan = {}
PluginScan.SENTINEL = "__menu_callback"
PluginScan.SUBMENU = "__menu_submenu"

local EXCLUDED_PLUGINS = { zen_ui = true }
local LAUNCH_METHODS = { "onShow", "show", "open", "launch", "onOpen" }

local function plugin_loader()
    local ok, loader = pcall(require, "pluginloader")
    return ok and loader or nil
end

local function live_uis()
    local out = {}
    local fm_mod = package.loaded["apps/filemanager/filemanager"]
    if fm_mod and fm_mod.instance then out[#out + 1] = fm_mod.instance end
    local reader_mod = package.loaded["apps/reader/readerui"]
    if reader_mod and reader_mod.instance then out[#out + 1] = reader_mod.instance end
    return out
end

local function enabled_plugin_names()
    local names = {}
    local loader = plugin_loader()
    if not (loader and type(loader.loadPlugins) == "function") then return names end
    local ok, enabled = pcall(loader.loadPlugins, loader)
    if not ok or type(enabled) ~= "table" then return names end
    for _i, plugin in ipairs(enabled) do
        if type(plugin) == "table" and type(plugin.name) == "string" then names[plugin.name] = true end
    end
    names.zen_ui = nil
    return names
end

local function is_callable(value)
    if type(value) == "function" then return true end
    local mt = type(value) == "table" and getmetatable(value) or nil
    return type(mt) == "table" and type(mt.__call) == "function"
end

-- 用空表探测插件的 addToMainMenu，取到该插件的主菜单项
local function probe_menu_entry(mod, key)
    if type(mod.addToMainMenu) ~= "function" then return nil end
    local probe = {}
    local ok = pcall(mod.addToMainMenu, mod, probe)
    if not ok then return nil end
    local entry = probe[key]
    if entry == nil and type(mod.name) == "string" then entry = probe[mod.name] end
    if entry == nil then
        local only, count = nil, 0
        for _k, value in pairs(probe) do
            if type(value) == "table" then count = count + 1; only = value end
        end
        if count == 1 then entry = only end
    end
    return type(entry) == "table" and entry or nil
end

local function text_without_glyph(text)
    if type(text) ~= "string" then return nil end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function entry_text(entry)
    if type(entry) ~= "table" then return nil end
    if type(entry.text_func) == "function" then
        local ok, text = pcall(entry.text_func)
        if ok then return text_without_glyph(text) end
    end
    return text_without_glyph(entry.text)
end

local function find_method(mod, key)
    for _i, method in ipairs(LAUNCH_METHODS) do
        if is_callable(mod[method]) then return method end
    end
    local camel = "on" .. key:sub(1, 1):upper() .. key:sub(2)
    if is_callable(mod[camel]) then return camel end
    local entry = probe_menu_entry(mod, key)
    if entry then
        if type(entry.callback) == "function" then return PluginScan.SENTINEL end
        if entry.sub_item_table ~= nil or entry.sub_item_table_func ~= nil then return PluginScan.SUBMENU end
    end
end

local function add_candidate(out, seen, key, mod)
    if type(key) ~= "string" or key == "" or EXCLUDED_PLUGINS[key] or seen[key] or type(mod) ~= "table" then return end
    local method = find_method(mod, key)
    if not method then return end
    seen[key] = true
    local entry = probe_menu_entry(mod, key)
    local title = entry_text(entry)
    if not title or title == "" then title = key:sub(1, 1):upper() .. key:sub(2) end
    out[#out + 1] = { key = key, method = method, title = title }
end

-- 解析菜单项的子菜单表（兼容 sub_item_table / sub_item_table_func）
local function menuSubTable(item)
    if type(item) ~= "table" then return nil end
    local sub = item.sub_item_table
    if sub == nil and type(item.sub_item_table_func) == "function" then
        local ok, res = pcall(item.sub_item_table_func, TOUCHMENU_STUB)
        if ok then sub = res end
    end
    return type(sub) == "table" and sub or nil
end

-- 按标题在菜单项树中查找可执行项（补丁动作复用）
local function findMenuItem(items, title)
    if type(items) ~= "table" then return nil end
    for _i, item in ipairs(items) do
        if type(item) == "table" then
            if entry_text(item) == title and type(item.callback) == "function" then return item.callback end
            local sub = menuSubTable(item)
            if sub then
                local cb = findMenuItem(sub, title)
                if cb then return cb end
            end
        end
    end
    return nil
end

function PluginScan.scan()
    if PluginScan._scan_cache then return PluginScan._scan_cache end
    local ok, results = pcall(function()
        local out, seen = {}, {}
        local loader = plugin_loader()
        if loader and type(loader.loaded_plugins) == "table" then
            for key, mod in pairs(loader.loaded_plugins) do add_candidate(out, seen, key, mod) end
        end
        local names = enabled_plugin_names()
        if loader and type(loader.getPluginInstance) == "function" then
            for key in pairs(names) do
                local ok_plugin, plugin = pcall(loader.getPluginInstance, loader, key)
                if ok_plugin then add_candidate(out, seen, key, plugin) end
            end
        end
        for _i, ui in ipairs(live_uis()) do
            for key in pairs(names) do add_candidate(out, seen, key, ui[key]) end
        end
        -- 扫描补丁：直接遍历菜单项的 callback 项
        local function scanPatchItems(items, parent_title)
            if type(items) ~= "table" then return end
            for _i, item in ipairs(items) do
                if type(item) == "table" then
                    local text = entry_text(item)
                    local sub = menuSubTable(item)
                    if sub and #sub > 0 then
                        scanPatchItems(sub, text) -- 递归：传递当前 text 为父级
                    elseif text and type(item.callback) == "function" then
                        local display_title = parent_title and (parent_title .. " · " .. text) or text
                        local patch_key = "patch_" .. display_title
                        if not seen[patch_key] then
                            seen[patch_key] = true
                            out[#out + 1] = { key = patch_key, method = PluginScan.SENTINEL, title = text, display_title = display_title, is_patch = true }
                        end
                    end
                end
            end
        end
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        if fm and fm.menu and fm.menu.menu_items then scanPatchItems(fm.menu.menu_items) end
        local RUI = require("apps/reader/readerui")
        local reader = RUI and RUI.instance
        if reader and reader.menu and reader.menu.menu_items then scanPatchItems(reader.menu.menu_items) end
        table.sort(out, function(a, b) return a.title < b.title end)
        return out
    end)
    PluginScan._scan_cache = ok and results or {}
    return PluginScan._scan_cache
end

local function live_plugin(key)
    local loader = plugin_loader()
    local loaded = loader and loader.loaded_plugins
    if type(loaded) == "table" and type(loaded[key]) == "table" then return loaded[key] end
    if loader and type(loader.getPluginInstance) == "function" then
        local ok, plugin = pcall(loader.getPluginInstance, loader, key)
        if ok and type(plugin) == "table" then return plugin end
    end
    for _i, ui in ipairs(live_uis()) do
        if type(ui[key]) == "table" then return ui[key] end
    end
end

function PluginScan.resolve(key, method)
    -- 补丁动作：按标题查找菜单项回调
    if type(key) == "string" and string.sub(key, 1, 6) == "patch_" then
        local menu_title = string.sub(key, 7):gsub("^.* · ", "")
        local callback = nil
        local FM = require("apps/filemanager/filemanager")
        local fm = FM and FM.instance
        if fm and fm.menu and fm.menu.menu_items then callback = findMenuItem(fm.menu.menu_items, menu_title) end
        if not callback then
            local RUI = require("apps/reader/readerui")
            local reader = RUI and RUI.instance
            if reader and reader.menu and reader.menu.menu_items then callback = findMenuItem(reader.menu.menu_items, menu_title) end
        end
        if callback then
            return function() return callback(TOUCHMENU_STUB) end
        end
        return nil
    end
    if type(key) ~= "string" or type(method) ~= "string" then return nil end
    local mod = live_plugin(key)
    if type(mod) ~= "table" then return nil end
    if method == PluginScan.SENTINEL then
        local entry = probe_menu_entry(mod, key)
        local callback = entry and entry.callback
        if type(callback) ~= "function" then return nil end
        return function() return callback(TOUCHMENU_STUB) end
    end
    if method == PluginScan.SUBMENU then
        local entry = probe_menu_entry(mod, key)
        if not entry then return nil end
        local sub_items = menuSubTable(entry)
        if not sub_items then return nil end
        local title = type(entry.text) == "string" and entry.text or key
        return function()
            local ok_host, menu_host = pcall(require, "modules/menu/app_launcher/menu_host")
            if ok_host and menu_host and type(menu_host.show) == "function" then
                return menu_host.show{ title = title, item_table = sub_items }
            end
            local buttons = {}
            for _i, item in ipairs(sub_items) do
                local cb = item.callback
                local text = item.text
                if type(item.text_func) == "function" then text = item.text_func() end
                if type(text) == "string" then
                    buttons[#buttons + 1] = {{
                        text = text,
                        callback = function() if cb then cb() end end,
                    }}
                end
            end
            UIManager:show(ButtonDialog:new{
                title = title,
                title_align = "center",
                buttons = buttons,
                width = math.floor(Screen:getWidth() * 0.7),
            })
        end
    end
    if not is_callable(mod[method]) then return nil end
    return function() return mod[method](mod) end
end

-- 文件管理器 / 阅读器实例（带 pcall 保护）
local function getInstances()
    local ok, FM = pcall(require, "apps/filemanager/filemanager")
    local fm = ok and FM and FM.instance or nil
    local ok2, RUI = pcall(require, "apps/reader/readerui")
    local rui = ok2 and RUI and RUI.instance or nil
    return fm, rui
end

local function closeTouchMenu(ctx)
    if ctx and ctx.touch_menu then ctx.touch_menu:onClose() end
end

-- ============================================================
-- 自定义动作分发执行（folder/collection/plugin/补丁/menu/dispatcher）
-- ============================================================
-- 前向声明：replayPath 定义在本函数之后（Lua 词法作用域要求先声明，
-- 否则闭包会绑定到全局 nil）
local replayPath
local function executeCustomAction(cfg, ctx)
    local atype = cfg.action_type
    local fm, rui = getInstances()
    if atype == "folder" and cfg.action_value then
        closeTouchMenu(ctx)
        if fm and fm.file_chooser then
            fm.file_chooser:changeToPath(cfg.action_value)
        elseif rui then
            rui:onClose()
            local FM = require("apps/filemanager/filemanager")
            FM:showFiles()
            local fm2 = FM.instance
            if fm2 and fm2.file_chooser then fm2.file_chooser:changeToPath(cfg.action_value) end
        end
    elseif atype == "collection" and cfg.action_value then
        if fm and fm.collections then
            pcall(fm.collections.onShowColl, fm.collections, cfg.action_value)
        elseif rui then
            rui.tearing_down = true
            rui:onClose()
            local FM = require("apps/filemanager/filemanager")
            FM:showFiles()
            local fm2 = FM.instance
            if fm2 and fm2.collections then pcall(fm2.collections.onShowColl, fm2.collections, cfg.action_value) end
        end
    elseif atype == "dispatcher" and cfg.dispatcher_action then
        closeTouchMenu(ctx)
        local ok, DispatcherMod = pcall(require, "dispatcher")
        if ok and DispatcherMod then DispatcherMod:execute({ [cfg.dispatcher_action] = cfg.dispatcher_value or true }) end
    elseif atype == "menu" and cfg.menu_path then
        -- 按录制路径回放菜单（含分页处理）
        local recorded_view = cfg.menu_path.view or "common"
        local current_view = nil
        if rui and not rui.tearing_down then current_view = "reader"
        elseif fm then current_view = "filemanager" end
        if recorded_view == "common" or recorded_view == current_view then
            local target_menu = nil
            if recorded_view == "reader" or current_view == "reader" then
                if rui and rui.menu then
                    if not rui.menu.menu_container or not rui.menu.menu_container[1] then rui.menu:onShowMenu() end
                    local mc = rui.menu.menu_container
                    target_menu = mc and mc[1] or rui.menu
                end
            elseif fm and fm.menu then
                if not fm.menu.menu_container or not fm.menu.menu_container[1] then fm.menu:onShowMenu(cfg.menu_path.tab_index or 1) end
                local mc = fm.menu.menu_container
                target_menu = mc and mc[1] or fm.menu
            end
            if target_menu then
                replayPath(target_menu, cfg.menu_path)
            else
                UIManager:show(InfoMessage:new{ text = _("无法打开菜单"), timeout = 2 })
            end
        else
            local msg = (recorded_view == "reader")
                and _("此快捷操作只能在阅读器中执行，请先打开一本书。")
                or _("此快捷操作只能在文件浏览器中执行。")
            UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
        end
    elseif atype == "plugin" and cfg.plugin_key then
        -- 子菜单：按路径索引执行
        if cfg.plugin_method == "submenu" and cfg.plugin_path_indices then
            local mod = live_plugin(cfg.plugin_key)
            if mod and type(mod.addToMainMenu) == "function" then
                local entry = probe_menu_entry(mod, cfg.plugin_key)
                local current_items = entry and menuSubTable(entry) or nil
                local found_item = nil
                if current_items then
                    for i, idx in ipairs(cfg.plugin_path_indices) do
                        if current_items and current_items[idx] then
                            found_item = current_items[idx]
                            if i < #cfg.plugin_path_indices then current_items = menuSubTable(found_item) end
                        else
                            found_item = nil
                            break
                        end
                    end
                end
                if found_item and type(found_item.callback) == "function" then
                    pcall(found_item.callback)
                    closeTouchMenu(ctx)
                else
                    UIManager:show(InfoMessage:new{
                        text = string.format(_("找不到插件菜单项 (索引: %s)"), table.concat(cfg.plugin_path_indices or {}, ", ")),
                        timeout = 2,
                    })
                end
            end
        elseif string.sub(cfg.plugin_key, 1, 6) == "patch_" then
            -- 补丁动作：遍历当前界面菜单项执行
            local menu_title = string.sub(cfg.plugin_key, 7):gsub("^.* · ", "")
            local callback = nil
            if fm and fm.menu and fm.menu.menu_items then callback = findMenuItem(fm.menu.menu_items, menu_title) end
            if not callback and rui and rui.menu and rui.menu.menu_items then callback = findMenuItem(rui.menu.menu_items, menu_title) end
            if callback then
                pcall(callback)
                closeTouchMenu(ctx)
            else
                UIManager:show(InfoMessage:new{
                    text = string.format(_("找不到补丁菜单项: %s"), menu_title),
                    timeout = 2,
                })
            end
        else
            -- 普通插件方法
            local method = cfg.plugin_method
            if type(method) ~= "string" or method == "submenu" then method = PluginScan.SENTINEL end
            local resolve_func = PluginScan.resolve(cfg.plugin_key, method)
            if not resolve_func then
                UIManager:show(InfoMessage:new{
                    text = string.format(_("无法解析插件方法: %s.%s"), cfg.plugin_key, method),
                    timeout = 2,
                })
                return
            end
            pcall(resolve_func)
        end
    end
end

-- ============================================================
-- UI 字体切换（三种字体类型，自动替换所有对应 key）
-- ============================================================
local _font_picker_dialog = nil
local _font_main_dialog = nil

local function getAvailableFonts()
    local result = {}
    for idx, path in ipairs(FontList:getFontList()) do
        local fname, name = util.splitFilePathName(path)
        if name and (name:match("%.ttf$") or name:match("%.otf$")) then
            result[#result + 1] = {
                name = name,
                display = name:gsub("%.ttf$", ""):gsub("%.otf$", ""):gsub("_", " "),
            }
        end
    end
    table.sort(result, function(a, b) return a.display:lower() < b.display:lower() end)
    return result
end

local UI_FONT_ITEMS = {
    { key = "regular", label = _("常规字体"), default = "NotoSans-Regular.ttf" },
    { key = "bold", label = _("粗体字体"), default = "NotoSans-Bold.ttf" },
    { key = "mono", label = _("等宽字体"), default = "DroidSansMono.ttf" },
}
local FONT_TYPE_MAP = {
    regular = { "cfont", "ffont", "smallffont", "largeffont", "rifont", "pgfont", "hfont", "infofont", "smallinfofont", "x_smallinfofont", "xx_smallinfofont" },
    bold = { "tfont", "smalltfont", "x_smalltfont", "smallinfofontbold" },
    mono = { "scfont", "hpkfont", "infont", "smallinfont" },
}

local function applyUIFontChanges()
    local overrides = getTable("ui_font_overrides") or {}
    local font_exists = {}
    for idx, path in ipairs(FontList:getFontList()) do
        local fname, name = util.splitFilePathName(path)
        if name then font_exists[name] = true end
    end
    local defaults = { regular = "NotoSans-Regular.ttf", bold = "NotoSans-Bold.ttf", mono = "DroidSansMono.ttf" }
    for kind, keys in pairs(FONT_TYPE_MAP) do
        local font_name = overrides[kind] or defaults[kind]
        if font_exists[font_name] then
            for _i, k in ipairs(keys) do Font.fontmap[k] = font_name end
        end
    end
    Font.faces = {}
    -- 统一覆盖各组件默认字体（face/fface 字段）
    local function overrideFace(modname, field, font_key, default_size)
        local ok, mod = pcall(require, modname)
        if ok and mod and mod[field] then
            mod[field] = Font:getFace(font_key, mod[field].orig_size or default_size)
        end
    end
    overrideFace("ui/widget/touchmenu", "fface", "cfont", 24)
    overrideFace("ui/widget/confirmbox", "face", "cfont", 22)
    overrideFace("ui/widget/infomessage", "face", "infofont", 22)
    overrideFace("ui/widget/notification", "face", "x_smallinfofont", 18)
    overrideFace("ui/widget/buttondialog", "title_face", "tfont", 20)
    overrideFace("ui/widget/buttondialog", "info_face", "infofont", 22)
    overrideFace("ui/widget/inputdialog", "input_face", "infont", 16)
    overrideFace("ui/widget/multiinputdialog", "title_face", "tfont", 20)
    overrideFace("ui/widget/multiinputdialog", "info_face", "infofont", 22)
    Button.text_font_face = overrides.regular or defaults.regular
    -- 菜单/触摸菜单项字体补丁（两处逻辑相同，合并）
    local function patchMenuUpdateItems(modname)
        local ok_mod, mod = pcall(require, modname)
        if not (ok_mod and mod and mod.updateItems) then return end
        local orig_update = mod.updateItems
        mod.updateItems = function(self, ...)
            if not self._font_patched then
                for i = 1, #self.item_group do
                    local widget = self.item_group[i]
                    if widget and widget.face then
                        local cls = getmetatable(widget)
                        if cls then cls.font = overrides.regular or defaults.regular; cls.infont = overrides.regular or defaults.regular end
                    end
                end
                self._font_patched = true
            end
            return orig_update(self, ...)
        end
    end
    patchMenuUpdateItems("ui/widget/menu")
    patchMenuUpdateItems("ui/widget/touchmenu")
end

local function setUIFontOverride(key, font_name)
    local overrides = getTable("ui_font_overrides") or {}
    if font_name then overrides[key] = font_name else overrides[key] = nil end
    setTable("ui_font_overrides", overrides)
    applyUIFontChanges()
    UIManager:setDirty("all", "full")
end

local function resetAllUIFonts()
    setTable("ui_font_overrides", {})
    UIManager:show(Notification:new{ text = _("已重置所有UI字体，重启后生效"), timeout = 2 })
    UIManager:show(ConfirmBox:new{
        text = _("重启后生效。立即重启？"),
        ok_text = _("重启"),
        cancel_text = _("稍后"),
        ok_callback = function() UIManager:restartKOReader() end,
    })
end

-- 重启确认框（多处共用）
local function askRestart(text)
    UIManager:show(ConfirmBox:new{
        text = text or _("重启后生效。立即重启？"),
        ok_text = _("重启"),
        cancel_text = _("稍后"),
        ok_callback = function() UIManager:restartKOReader() end,
    })
end

function showFontPickerForUIKey(ui_key, ui_label, on_select, on_cancel)
    if _font_picker_dialog then UIManager:close(_font_picker_dialog); _font_picker_dialog = nil end
    local all_fonts = getAvailableFonts()
    local current = getTable("ui_font_overrides")[ui_key] or ""
    local buttons = {}
    local function closePicker()
        if _font_picker_dialog then UIManager:close(_font_picker_dialog); _font_picker_dialog = nil end
    end
    buttons[#buttons + 1] = {{ text = _("应用默认"), callback = function() closePicker(); if on_select then on_select(nil) end end }}
    buttons[#buttons + 1] = {{ text = _("返回"), callback = function() closePicker(); if on_cancel then on_cancel() end end }}
    buttons[#buttons + 1] = {}
    if #all_fonts == 0 then
        buttons[#buttons + 1] = {{ text = _("没有可用的字体文件"), enabled = false }}
    else
        for i, font in ipairs(all_fonts) do
            local is_current = (font.name == current)
            buttons[#buttons + 1] = {{
                text = (is_current and "✓ " or "  ") .. font.display,
                callback = function()
                    closePicker()
                    if on_select then on_select(font.name) end
                end,
            }}
        end
    end
    _font_picker_dialog = ButtonDialog:new{
        title = string.format(_("选择 %s 字体"), ui_label),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    UIManager:show(_font_picker_dialog)
end

function showUIFontSwitcher()
    if _font_main_dialog then UIManager:close(_font_main_dialog); _font_main_dialog = nil end
    if _font_picker_dialog then UIManager:close(_font_picker_dialog); _font_picker_dialog = nil end
    local overrides = getTable("ui_font_overrides") or {}
    local replaced_count = 0
    for i, item in ipairs(UI_FONT_ITEMS) do
        if overrides[item.key] then replaced_count = replaced_count + 1 end
    end
    local buttons = {}
    local function closeMain()
        if _font_main_dialog then UIManager:close(_font_main_dialog); _font_main_dialog = nil end
    end
    buttons[#buttons + 1] = {{
        text = string.format(_("重置全部 (%d/%d)"), replaced_count, #UI_FONT_ITEMS),
        callback = function() closeMain(); resetAllUIFonts() end,
    }}
    buttons[#buttons + 1] = {}
    for i, item in ipairs(UI_FONT_ITEMS) do
        local override = overrides[item.key]
        local display = (override or item.default):gsub("%.ttf$", ""):gsub("%.otf$", ""):gsub("_", " ")
        local text = item.label .. ": " .. display
        if override then
            local default_display = item.default:gsub("%.ttf$", ""):gsub("%.otf$", ""):gsub("_", " ")
            text = item.label .. ": " .. default_display .. " → " .. display
        end
        buttons[#buttons + 1] = {{
            text = text,
            callback = function()
                closeMain()
                showFontPickerForUIKey(
                    item.key,
                    item.label,
                    function(new_font)
                        if new_font then
                            setUIFontOverride(item.key, new_font)
                            UIManager:show(Notification:new{
                                text = string.format(_("%s 已设置为 %s"), item.label, new_font),
                                timeout = 2,
                            })
                        else
                            setUIFontOverride(item.key, nil)
                            UIManager:show(Notification:new{
                                text = string.format(_("%s 已重置为默认"), item.label),
                                timeout = 2,
                            })
                        end
                        showUIFontSwitcher()
                    end,
                    function() showUIFontSwitcher() end
                )
            end,
        }}
    end
    _font_main_dialog = ButtonDialog:new{
        title = _("UI字体切换"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    UIManager:show(_font_main_dialog)
end

applyUIFontChanges()

-- ============================================================
-- Nerd Font 支持（全局函数：图标码位 ↔ UTF-8 字符）
-- ============================================================
function nerdIconChar(icon_value)
    if type(icon_value) ~= "string" then return nil end
    local hex = icon_value:match("^nerd:([0-9A-Fa-f]+)$")
    if not hex then return nil end
    local cp = tonumber(hex, 16)
    if not cp or cp < 0 or cp > 0x10FFFF then return nil end
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor((cp % 0x1000) / 0x40), 0x80 + (cp % 0x40))
    end
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor((cp % 0x40000) / 0x1000),
        0x80 + math.floor((cp % 0x1000) / 0x40), 0x80 + (cp % 0x40))
end

local function isNerdIcon(icon_value) return nerdIconChar(icon_value) ~= nil end

-- ============================================================
-- Nerd Font 图标列表（从 symbols 字体读取字形，码位区间单遍扫描）
-- ============================================================
local ffi = require("ffi")
ffi.cdef[[
    FT_Error FT_Get_Glyph_Name(FT_Face face, FT_UInt glyph_index, FT_String *buffer, FT_UInt buffer_max);
]]
local ft2 = ffi.loadlib("freetype", "6")

local NERD_RANGES = {
    {0x23FB, 0x23FE}, {0xE700, 0xE7FF}, {0xF000, 0xF3FF}, {0xF500, 0xF8FF},
    {0xE800, 0xE8FF}, {0xE000, 0xE09F}, {0xE100, 0xE2FF}, {0xE400, 0xE6FF},
    {0xF400, 0xF4FF}, {0xE300, 0xE3FF}, {0xE0A0, 0xE0FF},
}

local function getNerdGlyphName(cp, face)
    if not cp or type(cp) ~= "number" then return nil end
    face = face or Font:getFace("symbols", 12)
    local ft_face = face and face.ftsize and face.ftsize.face
    if not ft_face then return nil end
    local glyph_index = ft2.FT_Get_Char_Index(ft_face, cp)
    if glyph_index == 0 then return nil end
    local buffer = ffi.new("FT_String[128]")
    if ft2.FT_Get_Glyph_Name(ft_face, glyph_index, buffer, 128) ~= 0 then return nil end
    return ffi.string(buffer)
end

-- face 只取一次（原来每码点都 Font:getFace，约 900 次查找 → 1 次）
local function getNerdIcons()
    local icons = {}
    local face = Font:getFace("symbols", 12)
    if not (face and face.ftsize) then return icons end
    for _i, range in ipairs(NERD_RANGES) do
        for cp = range[1], range[2] do
            if face.ftsize:hasGlyph(cp) then
                local hex = string.format("%04X", cp)
                icons[#icons + 1] = { type = "nerd", hex = hex, value = "nerd:" .. hex, name = getNerdGlyphName(cp, face) }
            end
        end
    end
    return icons
end

-- ============================================================
-- 图标解析（带缓存：图标文件运行期不变；miss 用哨兵缓存防反复探测）
-- ============================================================
local _icons_dir = nil
local function getIconsDir()
    if _icons_dir then return _icons_dir end
    local ok, DataStorage = pcall(require, "datastorage")
    _icons_dir = ok and DataStorage and DataStorage:getDataDir() .. "/icons" or "./icons"
    return _icons_dir
end

local _icon_cache = { map = {}, miss = {} }

local function getIconFile(icon_name)
    if not icon_name then return nil end
    if isNerdIcon(icon_name) then return icon_name end
    local cached = _icon_cache.map[icon_name]
    if cached ~= nil then return cached == _icon_cache.miss and nil or cached end
    local result
    if icon_name:sub(1, 1) == "/" and lfs.attributes(icon_name, "mode") == "file" then
        result = icon_name
    end
    if not result then
        local ok, DataStorage = pcall(require, "datastorage")
        if ok and DataStorage then
            local full_path = (DataStorage:getDataDir() .. "/" .. icon_name):gsub("/%.", ""):gsub("/+", "/")
            if lfs.attributes(full_path, "mode") == "file" then result = full_path end
        end
    end
    if not result then
        local filename = icon_name:match("([^/]+)$") or icon_name
        local dirs_to_check = { getIconsDir(), "resources/icons/mdlight", "resources/icons", "resources" }
        for _i, dir in ipairs(dirs_to_check) do
            local path = dir .. "/" .. filename
            if lfs.attributes(path, "mode") == "file" then result = path; break end
        end
    end
    _icon_cache.map[icon_name] = result or _icon_cache.miss
    return result
end

local function getIconWidget(icon_path, size)
    size = size or Screen:scaleBySize(24)
    if isNerdIcon(icon_path) then
        local nerd_char = nerdIconChar(icon_path)
        if nerd_char then
            return TextWidget:new{
                text = nerd_char,
                face = Font:getFace("symbols", math.floor(size * 0.6)),
                fgcolor = Blitbuffer.COLOR_BLACK,
                padding = 0,
            }
        end
    end
    local file_path = getIconFile(icon_path)
    if file_path and lfs.attributes(file_path, "mode") == "file" then
        local iw = ImageWidget:new{ file = file_path, width = size, height = size, alpha = true, is_icon = true }
        local ok_render = pcall(function() iw:_render() end)
        if ok_render then return iw end
        iw:free()
    end
    return nil
end

-- ============================================================
-- 图标文件浏览器
-- ============================================================
local THUMB_SIZE = Screen:scaleBySize(32)
local THUMB_GAP = Screen:scaleBySize(6)

local _InnerIconChooser = PathChooser:extend{
    select_directory = false,
    select_file = true,
    state_w = THUMB_SIZE + THUMB_GAP,
    path = getIconsDir(),
    onConfirm = nil,
    _filter_text = "",
    _all_items = nil,
    stop_events_propagation = true,
}

function _InnerIconChooser:init()
    self.title = _('选择图标')
    self.file_filter = function(filename)
        local ext = filename:lower()
        return ext:match('%.svg$') ~= nil or ext:match('%.png$') ~= nil
    end
    self.state_w = THUMB_SIZE + THUMB_GAP
    PathChooser.init(self)
    if not self._all_items then self:refreshPath() end
end

function _InnerIconChooser:getCollate()
    return self.collates.strcoll, "strcoll"
end

function _InnerIconChooser:refreshPath()
    local _, folder_name = util.splitFilePathName(self.path)
    Screen:setWindowTitle(folder_name)
    self._all_items = self:genItemTableFromPath(self.path)
    self:_applyCurrentFilter()
end

function _InnerIconChooser:_applyCurrentFilter()
    local filter_text = self._filter_text or ""
    local items
    if filter_text == "" then
        items = self._all_items
    else
        items = {}
        local pattern = filter_text:lower()
        for _i, item in ipairs(self._all_items) do
            if item.is_go_up or (item.text and item.text:lower():find(pattern, 1, true)) then
                items[#items + 1] = item
            end
        end
    end
    local itemmatch
    if self.focused_path then itemmatch = { path = self.focused_path }; self.focused_path = nil end
    local subtitle = BD.directory(filemanagerutil.abbreviate(self.path))
    self:switchItemTable(nil, items, filter_text == "" and self.path_items[self.path] or 1, itemmatch, subtitle)
end

function _InnerIconChooser:applyFilter(text)
    self._filter_text = text or ""
    if self._all_items then self:_applyCurrentFilter() end
end

function _InnerIconChooser:_recalculateDimen(no_recalculate_dimen)
    Menu._recalculateDimen(self, no_recalculate_dimen)
    if not self.item_dimen then return end
    if self._filter_bar_height and self._filter_bar_height > 0 and not no_recalculate_dimen then
        self.available_height = self.available_height - self._filter_bar_height
        self.item_dimen.h = math.floor(self.available_height / self.perpage)
    end
    local content_w = math.max(0, self.item_dimen.w - 2 * Size.padding.fullscreen)
    local max_state_w = math.max(1, math.floor(content_w / 4))
    local ts, tg = THUMB_SIZE, THUMB_GAP
    self.state_w = math.min(ts + tg, max_state_w)
    self._thumb_size = math.max(0, math.min(ts, self.state_w - tg))
end

function _InnerIconChooser:updateItems(select_number, no_recalculate_dimen)
    Menu.updateItems(self, select_number, no_recalculate_dimen)
    self.path_items[self.path] = (self.page - 1) * self.perpage + (select_number or 1)
    local eff_thumb = self._thumb_size or 0
    if eff_thumb <= 0 then return end
    local item_h = self.item_dimen and self.item_dimen.h or eff_thumb
    local center_y = math.max(0, math.floor((item_h - eff_thumb) / 2))
    for _i, item_widget in ipairs(self.item_group) do
        local entry = item_widget.entry
        if not entry then goto continue end
        local filepath = entry.path or ""
        if not filepath:lower():match("%.svg$") and not filepath:lower():match("%.png$") then goto continue end
        local uc = item_widget._underline_container
        local hg = uc and uc[1]
        local og = hg and hg[1]
        if og then
            -- 缩略图插到行首（与 PathChooser 原布局一致）
            table.insert(og, 1, ImageWidget:new{
                file = filepath,
                width = eff_thumb,
                height = eff_thumb,
                alpha = true,
                overlap_offset = { 0, center_y },
            })
            og._size = nil
        end
        ::continue::
    end
end

function _InnerIconChooser:onMenuSelect(item)
    local path = item.path or ""
    if path:lower():match("%.svg$") or path:lower():match("%.png$") then
        if self.show_parent then self.show_parent:onClose() end
        if self.onConfirm then self.onConfirm(path) end
        return true
    end
    return PathChooser.onMenuSelect(self, item)
end

function _InnerIconChooser:onMenuHold(item)
    local path = item.path or ""
    if path:lower():match("%.svg$") or path:lower():match("%.png$") then return true end
    return PathChooser.onMenuHold(self, item)
end

local IconBrowser = WidgetContainer:extend{
    path = getIconsDir(),
    onConfirm = nil,
    is_always_active = true,
}

function IconBrowser:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local final_path = nil
    for _i, path in ipairs({ self.path, "./resources/icons/mdlight", "./" }) do
        if lfs.attributes(path, "mode") == "directory" then
            final_path = path
            break
        end
    end
    if not final_path then
        UIManager:show(InfoMessage:new{ text = _("找不到图标目录，无法打开图标浏览器"), timeout = 3 })
        return
    end
    self.path = final_path
    self._filter_input = InputText:new{
        text = "",
        hint = _("按名称筛选…"),
        width = self.dimen.w - 4 * Size.padding.default,
        height = nil,
        face = Font:getFace("smallinfofont"),
        padding = Size.padding.small,
        margin = 0,
        bordersize = Size.border.inputtext,
        parent = self,
        scroll = false,
        focused = false,
        edit_callback = function() self:_applyFilter() end,
    }
    self._filter_input.addChars = function(inp, chars)
        if chars == "\n" then
            inp:onCloseKeyboard()
            return
        end
        InputText.addChars(inp, chars)
    end
    self._filter_bar = FrameContainer:new{
        padding = Size.padding.default,
        padding_top = Size.padding.small,
        padding_bottom = Size.padding.small,
        bordersize = 0,
        self._filter_input,
    }
    local filter_h = self._filter_bar:getSize().h
    self._chooser = _InnerIconChooser:new{
        show_parent = self,
        path = self.path,
        onConfirm = self.onConfirm,
        height = self.dimen.h,
        close_callback = function() self:onClose() end,
    }
    table.insert(self._chooser.content_group, 2, self._filter_bar)
    self._chooser._filter_bar_height = filter_h
    self._chooser:refreshPath()
    self[1] = self._chooser
end

function IconBrowser:_applyFilter()
    if not self._chooser then return end
    local text = self._filter_input and self._filter_input:getText() or ""
    self._chooser:applyFilter(text)
end

-- 保持不可聚焦（防止实体按键焦点跳到浏览器内部）
function IconBrowser:getFocusableWidgetXY() return nil, nil end

function IconBrowser:onClose()
    if self._filter_input then self._filter_input:onCloseKeyboard() end
    UIManager:close(self)
end

-- ============================================================
-- 扫描图标目录中的 SVG/PNG 文件
-- ============================================================
local function scanAllIconDirs(mode)
    local all_files, seen = {}, {}
    local dirs_to_scan = (mode == "system")
        and { "resources/icons/mdlight" }
        or { getIconsDir(), "resources/icons/mdlight", "resources/icons", "resources" }
    for _i, dir in ipairs(dirs_to_scan) do
        if lfs.attributes(dir, "mode") == "directory" then
            for file in lfs.dir(dir) do
                if file ~= "." and file ~= ".." then
                    local ext = file:lower()
                    if ext:match("%.svg$") or ext:match("%.png$") then
                        local name = file:gsub("%.[^%.]+$", "")
                        if not seen[name] then
                            seen[name] = true
                            all_files[#all_files + 1] = {
                                path = dir .. "/" .. file,
                                name = name,
                                display_name = name:gsub("_", " "),
                                ext = ext,
                                type = "file",
                            }
                        end
                    end
                end
            end
        end
    end
    return all_files
end

local cached_file_icons = nil
local function getFileIcons()
    if cached_file_icons == nil then cached_file_icons = scanAllIconDirs() end
    return cached_file_icons
end

local picker_cache = {}
local function clearFileIconsCache()
    picker_cache = {}
    cached_file_icons = nil
end

local system_temp_overrides = nil
local function getSystemTempOverrides()
    if system_temp_overrides == nil then
        system_temp_overrides = {}
        for k, v in pairs(getTable("qa_icon_overrides")) do system_temp_overrides[k] = v end
    end
    return system_temp_overrides
end
local function resetSystemTempOverrides() system_temp_overrides = nil end

-- ============================================================
-- 图标选择器（网格 + 筛选 + 分页；屏幕尺寸变化自动重算布局）
-- ============================================================
local function showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad = Screen:scaleBySize(24)
    local brd = Screen:scaleBySize(1)
    local cache_key = (filter or "all") .. "_" .. (mode or "normal")
    local use_cache = picker_cache[cache_key] ~= nil

    local icons_list, page_widgets, total_pages
    local frame_x, frame_y, frame_w, frame_h
    local content_w, title_bar_h, button_bar_h, footer_h
    local cols, rows, per_page, h_gap, v_gap
    local cell_w, cell_h, icon_sz, font_size, cell_pad, grid_w, grid_h
    local dialog = nil
    local cur_page = 1
    local filter_keyword = ""
    local filtered_icons_list = nil
    local search_dialog = nil

    local function getDisplayList()
        -- 防御：icons_list 意外为 nil 时返回空表，避免 #nil 崩溃（历史回归点）
        if filter_keyword == "" then return icons_list or {} end
        if filtered_icons_list == nil then
            filtered_icons_list = {}
            local pattern = filter_keyword:lower()
            for _i, icon in ipairs(icons_list or {}) do
                local hay = icon.type == "nerd" and icon.name or icon.display_name
                local match = false
                if icon.type == "nerd" then
                    if icon.hex:lower():find(pattern, 1, true) then match = true end
                end
                if not match and hay and hay:lower():find(pattern, 1, true) then match = true end
                if not match and icon.type ~= "nerd" and icon.name and icon.name:lower():find(pattern, 1, true) then match = true end
                if match then filtered_icons_list[#filtered_icons_list + 1] = icon end
            end
        end
        return filtered_icons_list
    end

    local function rebuildPicker()
        filtered_icons_list = nil
        local display_list = getDisplayList()
        local new_total_pages = math.max(1, math.ceil(#display_list / per_page))
        local new_page_widgets = {}
        for p = 1, new_total_pages do
            local page_vg = VerticalGroup:new{ align = "left" }
            local start_idx = (p - 1) * per_page + 1
            for row = 0, rows - 1 do
                local row_hg = HorizontalGroup:new{ align = "top" }
                for col = 0, cols - 1 do
                    local idx = start_idx + row * cols + col
                    if idx <= #display_list then
                        local icon = display_list[idx]
                        local icon_widget
                        if icon.type == "nerd" then
                            icon_widget = TextWidget:new{
                                text = nerdIconChar(icon.value) or "?",
                                face = Font:getFace("symbols", font_size),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            }
                        else
                            local icon_path = icon.path
                            if mode == "system" and icon.is_overridden and icon.override_path then icon_path = icon.override_path end
                            icon_widget = IconWidget:new{ file = icon_path, width = icon_sz, height = icon_sz, alpha = true }
                            pcall(function() icon_widget:_render() end)
                        end
                        local cell_content = CenterContainer:new{
                            dimen = Geom:new{ w = cell_w - cell_pad * 2 - 2, h = cell_h - cell_pad * 2 - 2 },
                            icon_widget,
                        }
                        local border_color, border_size = Blitbuffer.COLOR_LIGHT_GRAY, 1
                        if mode == "system" and icon.is_overridden then border_color, border_size = Blitbuffer.COLOR_BLACK, 2 end
                        local cell = FrameContainer:new{
                            width = cell_w,
                            height = cell_h,
                            bordersize = border_size,
                            color = border_color,
                            background = Blitbuffer.COLOR_WHITE,
                            radius = Screen:scaleBySize(4),
                            padding = cell_pad,
                            cell_content,
                        }
                        row_hg[#row_hg + 1] = cell
                        if col < cols - 1 then row_hg[#row_hg + 1] = HorizontalSpan:new{ width = h_gap } end
                    end
                end
                page_vg[#page_vg + 1] = row_hg
                if row < rows - 1 then page_vg[#page_vg + 1] = VerticalSpan:new{ width = v_gap } end
            end
            new_page_widgets[p] = page_vg
        end
        page_widgets = new_page_widgets
        total_pages = new_total_pages
        if cur_page > total_pages then cur_page = 1 end
        if dialog then UIManager:setDirty(dialog, function() return "ui", dialog.dimen end) end
    end

    local function showSearchDialog()
        if search_dialog then UIManager:close(search_dialog); search_dialog = nil end
        local function onStrike()
            if search_dialog then
                filter_keyword = search_dialog:getInputText() or ""
                filtered_icons_list = nil
                rebuildPicker()
                UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
            end
        end
        search_dialog = InputDialog:new{
            title = _("筛选图标"),
            input = filter_keyword,
            input_hint = _("输入名称或码位..."),
            strike_callback = onStrike,
            buttons = {
                {
                    {
                        text = _("清除"),
                        callback = function()
                            UIManager:close(search_dialog)
                            search_dialog = nil
                            filter_keyword = ""
                            filtered_icons_list = nil
                            rebuildPicker()
                            UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
                        end,
                    },
                    {
                        text = _("关闭"),
                        callback = function()
                            UIManager:close(search_dialog)
                            search_dialog = nil
                        end,
                    },
                }
            },
        }
        UIManager:show(search_dialog)
        pcall(function() search_dialog:onShowKeyboard() end)
    end

    local temp_overrides = {}
    if mode == "system" then temp_overrides = getSystemTempOverrides() end

    local cache_valid = false
    if use_cache and mode ~= "system" then
        local cached = picker_cache[cache_key]
        -- 校验缓存完整性：尺寸一致且 icons_list 存在（防缓存结构变化导致 nil）
        if cached.sw == sw and cached.sh == sh and cached.icons_list then
            cache_valid = true
            icons_list, page_widgets, total_pages = cached.icons_list, cached.page_widgets, cached.total_pages
            frame_x, frame_y, frame_w, frame_h = cached.frame_x, cached.frame_y, cached.frame_w, cached.frame_h
            content_w, title_bar_h, button_bar_h, footer_h = cached.content_w, cached.title_bar_h, cached.button_bar_h, cached.footer_h
            cols, rows, per_page, h_gap, v_gap = cached.cols, cached.rows, cached.per_page, cached.h_gap, cached.v_gap
            cell_w, cell_h, icon_sz, font_size, cell_pad, grid_w, grid_h = cached.cell_w, cached.cell_h, cached.icon_sz, cached.font_size, cached.cell_pad, cached.grid_w, cached.grid_h
        end
    end

    if not cache_valid then
        if use_cache and mode ~= "system" and picker_cache[cache_key].icons_list then
            icons_list = picker_cache[cache_key].icons_list
        else
            icons_list = {}
            if (not filter or filter == "nerd") and mode ~= "system" then
                for _i, icon in ipairs(getNerdIcons()) do
                    icons_list[#icons_list + 1] = { type = "nerd", hex = icon.hex, value = "nerd:" .. icon.hex, name = icon.name }
                end
            end
            if not filter or filter == "file" then
                local file_icons = (mode == "system") and scanAllIconDirs("system") or getFileIcons()
                for _i, file in ipairs(file_icons) do
                    local item = { type = "file", path = file.path, name = file.name, display_name = file.display_name, value = file.path }
                    if mode == "system" then
                        local override_icon = temp_overrides[file.name]
                        item.is_overridden = override_icon ~= nil
                        if override_icon then
                            local override_path = getIconsDir() .. "/" .. override_icon
                            if lfs.attributes(override_path, "mode") == "file" then item.override_path = override_path end
                        end
                    end
                    icons_list[#icons_list + 1] = item
                end
            end
        end
        if sw > sh then cols, rows, frame_h = 9, 4, math.floor(sh * 0.85)
        else cols, rows, frame_h = 7, 5, math.floor(sh * 0.70) end
        per_page = cols * rows
        h_gap, v_gap = Screen:scaleBySize(15), Screen:scaleBySize(15)
        frame_w = math.floor(sw * 0.90)
        content_w = frame_w - 2 * pad - 2 * brd
        title_bar_h = Screen:scaleBySize(50)
        button_bar_h = Screen:scaleBySize(50)
        footer_h = Screen:scaleBySize(40)
        cell_w = math.floor((content_w - (cols - 1) * h_gap) / cols)
        local available_h = frame_h - pad - title_bar_h - button_bar_h - footer_h - pad
        cell_h = math.max(44, math.floor((available_h - (rows - 1) * v_gap) / rows))
        icon_sz = math.floor(cell_h * 0.55)
        font_size = math.floor(icon_sz * 0.85)
        cell_pad = math.max(4, math.floor(cell_h * 0.2))
        grid_w = cols * cell_w + (cols - 1) * h_gap
        grid_h = cell_h * rows + (rows - 1) * v_gap
        frame_x = math.floor((sw - frame_w) / 2)
        frame_y = math.max(0, math.floor((sh - frame_h) / 2))
        rebuildPicker()
        if mode ~= "system" then
            picker_cache[cache_key] = {
                icons_list = icons_list,
                page_widgets = page_widgets,
                total_pages = total_pages,
                sw = sw,
                sh = sh,
                frame_x = frame_x,
                frame_y = frame_y,
                frame_w = frame_w,
                frame_h = frame_h,
                content_w = content_w,
                title_bar_h = title_bar_h,
                button_bar_h = button_bar_h,
                footer_h = footer_h,
                cols = cols,
                rows = rows,
                per_page = per_page,
                h_gap = h_gap,
                v_gap = v_gap,
                cell_w = cell_w,
                cell_h = cell_h,
                icon_sz = icon_sz,
                font_size = font_size,
                cell_pad = cell_pad,
                grid_w = grid_w,
                grid_h = grid_h,
            }
        end
    end

    -- 系统图标模式：重置全部 / 应用替换
    local function countReplaced()
        local n = 0
        for _i, item in ipairs(icons_list) do
            if temp_overrides[item.name] then n = n + 1 end
        end
        return n
    end

    local btn_row
    if mode == "system" then
        local function resetIcons()
            if countReplaced() == 0 then
                UIManager:show(InfoMessage:new{ text = _("没有已替换的图标需要重置"), timeout = 2 })
                return
            end
            resetSystemTempOverrides()
            setTable("qa_icon_overrides", {})
            picker_cache = {}
            UIManager:show(Notification:new{ text = _("已重置所有图标，重启后生效"), timeout = 2 })
            askRestart()
        end
        local function applyIcons()
            local n = countReplaced()
            if n == 0 then
                UIManager:show(InfoMessage:new{ text = _("没有已替换的图标需要应用"), timeout = 2 })
                return
            end
            local overrides = getTable("qa_icon_overrides")
            for k, _ in pairs(overrides) do overrides[k] = nil end
            for k, v in pairs(temp_overrides) do if v then overrides[k] = v end end
            setTable("qa_icon_overrides", overrides)
            resetSystemTempOverrides()
            picker_cache = {}
            UIManager:show(Notification:new{ text = string.format(_("已应用 %d 个图标替换"), n), timeout = 2 })
            askRestart()
        end
        btn_row = HorizontalGroup:new{
            align = "center",
            Button:new{ text = string.format(_("重置全部 (%d)"), countReplaced()), width = math.floor(content_w / 2) - 4, show_parent = nil, callback = resetIcons },
            HorizontalSpan:new{ width = 8 },
            Button:new{ text = string.format(_("应用替换 (%d)"), countReplaced()), width = math.floor(content_w / 2) - 4, show_parent = nil, callback = applyIcons },
        }
    else
        local btn_width = math.floor(content_w / 4) - 5
        local show_browse_btn = not filter or filter == "file"
        btn_row = HorizontalGroup:new{
            align = "center",
            Button:new{
                text = _("应用默认"),
                width = btn_width,
                show_parent = nil,
                callback = function()
                    UIManager:close(dialog)
                    UIManager:setDirty("all", "full")
                    if on_select then on_select(nil) end
                end,
            },
            HorizontalSpan:new{ width = 8 },
            Button:new{
                text = "刷新↻",
                width = btn_width,
                show_parent = nil,
                callback = function()
                    clearFileIconsCache()
                    UIManager:close(dialog)
                    UIManager:setDirty("all", "full")
                    showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
                end,
            },
            HorizontalSpan:new{ width = 8 },
            Button:new{
                text = (filter == "file") and _("显示完整图标") or _("仅显示file图标"),
                width = btn_width,
                show_parent = nil,
                callback = function()
                    UIManager:close(dialog)
                    UIManager:setDirty("all", "full")
                    showIconPicker(on_select, saved_icon, (filter == "file") and nil or "file")
                end,
            },
            (show_browse_btn and HorizontalSpan:new{ width = 8 } or nil),
            (show_browse_btn and Button:new{
                text = _("浏览文件"),
                width = btn_width,
                show_parent = nil,
                callback = function()
                    UIManager:close(dialog)
                    UIManager:setDirty("all", "full")
                    clearFileIconsCache()
                    UIManager:show(IconBrowser:new{
                        path = getIconsDir(),
                        onConfirm = function(file_path)
                            if on_select then on_select(file_path) end
                        end,
                    })
                end,
            } or nil),
        }
    end

    local inner_frame = FrameContainer:new{
        width = frame_w,
        height = frame_h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = brd,
        radius = Screen:scaleBySize(8),
        padding = pad,
        VerticalGroup:new{ align = "center" },
    }

    local PickerDlg = InputContainer:extend{}
    function PickerDlg:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        self:registerTouchZones({
            {
                id = "picker_tap",
                ges = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges)
                    local fd = inner_frame.dimen
                    if not fd or not ges.pos:intersectWith(fd) then
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        return true
                    end
                    local gx, gy = ges.pos.x, ges.pos.y
                    local btn_hit = 80
                    -- 左上角：返回（系统模式回到系统图标预览；其他模式重新选择当前图标）
                    if gx >= frame_x + pad and gx < frame_x + pad + btn_hit
                            and gy >= frame_y + pad and gy < frame_y + pad + btn_hit then
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        if parent_mode == "system" then
                            showIconPicker(nil, nil, nil, "system")
                        elseif on_select then
                            on_select(saved_icon)
                        end
                        return true
                    end
                    -- 右上角：筛选
                    if gx >= frame_x + frame_w - pad - btn_hit and gx < frame_x + frame_w - pad
                            and gy >= frame_y + pad and gy < frame_y + pad + btn_hit then
                        showSearchDialog()
                        return true
                    end
                    -- 底部按钮行
                    local btn_y = frame_y + pad + title_bar_h
                    if gy >= btn_y and gy < btn_y + button_bar_h then
                        if mode == "system" then
                            local bw = math.floor(content_w / 2) - 4
                            local bx = frame_x + pad
                            if gx >= bx and gx < bx + bw then
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                resetIcons()
                                return true
                            elseif gx >= bx + bw + 8 and gx < bx + (bw + 8) * 2 then
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                applyIcons()
                                return true
                            end
                        else
                            local bw = math.floor(content_w / 4) - 5
                            local bx = frame_x + pad
                            local idx = 0
                            -- 四个按钮逐个命中检测
                            for i = 0, 3 do
                                if i == 3 and not (not filter or filter == "file") then break end
                                local x0 = bx + (bw + 8) * i
                                if gx >= x0 and gx < x0 + bw then
                                    UIManager:close(self)
                                    UIManager:setDirty("all", "full")
                                    if i == 0 then
                                        if on_select then on_select(nil) end
                                    elseif i == 1 then
                                        clearFileIconsCache()
                                        showIconPicker(on_select, saved_icon, filter, mode, parent_mode)
                                    elseif i == 2 then
                                        showIconPicker(on_select, saved_icon, (filter == "file") and nil or "file")
                                    else
                                        clearFileIconsCache()
                                        UIManager:show(IconBrowser:new{
                                            path = getIconsDir(),
                                            onConfirm = function(file_path)
                                                if on_select then on_select(file_path) end
                                            end,
                                        })
                                    end
                                    return true
                                end
                            end
                        end
                        return true
                    end
                    -- 页脚：上一页 / 下一页 / 跳页
                    local bar_y = frame_y + pad + title_bar_h + button_bar_h + grid_h
                    if gy >= bar_y and gy < bar_y + footer_h then
                        local chev_w = 120
                        if gx < frame_x + pad + chev_w then
                            if cur_page > 1 then
                                cur_page = cur_page - 1
                                UIManager:setDirty(self, function() return "ui", self.dimen end)
                            end
                            return true
                        elseif gx > frame_x + frame_w - pad - chev_w then
                            if cur_page < total_pages then
                                cur_page = cur_page + 1
                                UIManager:setDirty(self, function() return "ui", self.dimen end)
                            end
                            return true
                        else
                            local dlg
                            dlg = InputDialog:new{
                                title = _("跳转到第几页"),
                                input = tostring(cur_page),
                                input_hint = string.format("1 - %d", total_pages),
                                input_type = "number",
                                buttons = {
                                    {
                                        {
                                            text = _("取消"),
                                            callback = function() UIManager:close(dlg) end,
                                        },
                                        {
                                            text = _("跳转"),
                                            is_enter_default = true,
                                            callback = function()
                                                local page = tonumber(dlg:getInputText())
                                                if page and page >= 1 and page <= total_pages then
                                                    cur_page = page
                                                    UIManager:close(dlg)
                                                    UIManager:setDirty(self, function() return "ui", self.dimen end)
                                                else
                                                    UIManager:show(InfoMessage:new{
                                                        text = string.format(_("请输入 1 到 %d 之间的数字"), total_pages),
                                                        timeout = 2,
                                                    })
                                                end
                                            end,
                                        },
                                    }
                                },
                            }
                            UIManager:show(dlg)
                            pcall(function() dlg:onShowKeyboard() end)
                            return true
                        end
                    end
                    -- 网格：选中图标
                    local grid_start_x = frame_x + pad + (content_w - grid_w) / 2
                    local grid_y = frame_y + pad + title_bar_h + button_bar_h
                    if gx >= grid_start_x and gx < grid_start_x + grid_w
                            and gy >= grid_y and gy < grid_y + grid_h then
                        local col = math.floor((gx - grid_start_x) / (cell_w + h_gap))
                        local row = math.floor((gy - grid_y) / (cell_h + v_gap))
                        local display_list = getDisplayList()
                        local idx = (cur_page - 1) * per_page + row * cols + col + 1
                        if idx >= 1 and idx <= #display_list then
                            local selected_icon = display_list[idx]
                            if mode == "system" then
                                local system_icon_name = selected_icon.name
                                local current = temp_overrides[system_icon_name]
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                showIconPicker(
                                    function(selected)
                                        if selected == current then return end
                                        if selected then
                                            temp_overrides[system_icon_name] = selected:match("([^/]+)$") or selected
                                        else
                                            temp_overrides[system_icon_name] = nil
                                        end
                                        picker_cache = {}
                                        showIconPicker(nil, nil, nil, "system")
                                    end,
                                    current,
                                    "file",
                                    nil,
                                    "system"
                                )
                            else
                                UIManager:close(self)
                                UIManager:setDirty("all", "full")
                                if on_select then on_select(selected_icon.value) end
                            end
                            return true
                        end
                    end
                    return true
                end,
            },
            {
                id = "picker_swipe",
                ges = "swipe",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges)
                    local dir = ges.direction
                    if dir == "west" then
                        if cur_page < total_pages then
                            cur_page = cur_page + 1
                            UIManager:setDirty(self, function() return "ui", self.dimen end)
                        end
                    elseif dir == "east" then
                        if cur_page > 1 then
                            cur_page = cur_page - 1
                            UIManager:setDirty(self, function() return "ui", self.dimen end)
                        end
                    else
                        UIManager:close(self)
                        UIManager:setDirty("all", "full")
                        return true
                    end
                    return true
                end,
            },
        })
    end

    function PickerDlg:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        inner_frame.dimen = Geom:new{ x = frame_x, y = frame_y, w = frame_w, h = frame_h }
        inner_frame:paintTo(bb, frame_x, frame_y)
        local content_x, content_y = frame_x + pad, frame_y + pad
        local title_text
        if mode == "system" then title_text = _("系统图标预览")
        elseif filter == "file" then title_text = _("选择图标文件")
        else title_text = _("选择图标") end
        if filter_keyword ~= "" then title_text = title_text .. " [" .. _("筛选") .. ": \"" .. filter_keyword .. "\"]" end
        local title_tw = TextWidget:new{ text = title_text, face = Font:getFace("smallinfofont"), bold = true }
        title_tw:paintTo(bb, content_x + (content_w - title_tw:getSize().w) / 2, content_y + 12)
        local back_tw = TextWidget:new{ text = "↶", face = Font:getFace("cfont", 24), fgcolor = Blitbuffer.COLOR_BLACK }
        back_tw:paintTo(bb, content_x, content_y + 5)
        local search_tw = TextWidget:new{ text = nerdIconChar("nerd:F002") or "?", face = Font:getFace("symbols", 22), fgcolor = Blitbuffer.COLOR_BLACK }
        search_tw:paintTo(bb, content_x + content_w - 35, content_y + 5)
        btn_row:paintTo(bb, content_x, content_y + title_bar_h)
        local grid_start_x = content_x + (content_w - grid_w) / 2
        local grid_start_y = content_y + title_bar_h + button_bar_h
        local display_list = getDisplayList()
        if #display_list == 0 then
            local empty_tw = TextWidget:new{ text = _("没有匹配的图标"), face = Font:getFace("cfont"), fgcolor = Blitbuffer.COLOR_DARK_GRAY }
            empty_tw:paintTo(bb, grid_start_x + (grid_w - empty_tw:getSize().w) / 2, grid_start_y + grid_h / 2 - 20)
        else
            page_widgets[cur_page]:paintTo(bb, grid_start_x, grid_start_y)
        end
        if total_pages > 1 then
            local bar_y = grid_start_y + grid_h + (footer_h - 20) / 2
            local left = TextWidget:new{ text = "◀", face = Font:getFace("cfont", 20), fgcolor = Blitbuffer.COLOR_BLACK }
            left:paintTo(bb, content_x + 10, bar_y)
            local right = TextWidget:new{ text = "▶", face = Font:getFace("cfont", 20), fgcolor = Blitbuffer.COLOR_BLACK }
            right:paintTo(bb, frame_x + frame_w - pad - 50, bar_y)
            local page_text = TextWidget:new{ text = string.format("%d / %d", cur_page, total_pages), face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.gray(0.5) }
            page_text:paintTo(bb, frame_x + (frame_w - page_text:getSize().w) / 2, bar_y)
        end
    end

    dialog = PickerDlg:new{}
    UIManager:show(dialog, "full")
end

-- ============================================================
-- 菜单路径录制器
-- ============================================================
local _pick_state = {
    active = false, menu = nil, nav_path = {}, tab_index = 1, on_done = nil, on_cancel = nil,
}
local _orig_onMenuSelect = nil
local _orig_backToUpperMenu = nil
local _orig_switchMenuTab = nil
local _orig_closeMenu = nil
local _orig_updateItems = nil

local function _itemText(item)
    local t = item.text
    if type(t) == "function" then t = t() end
    if not t and item.text_func then t = item.text_func() end
    return type(t) == "string" and t or ""
end

-- 前向声明：_stopPicking 定义在本函数之后
local _stopPicking
local function _makeActionBar(menu)
    local buttons = {}
    buttons[#buttons + 1] = Button:new{
        text = _("完成录制并保存为快捷操作"),
        width = menu.item_width,
        text_font_bold = true,
        bordersize = Size.border.thin,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        show_parent = menu.show_parent,
        callback = function()
            if _pick_state.active then
                local index_path = {}
                for _i, step in ipairs(_pick_state.nav_path) do index_path[#index_path + 1] = step.index end
                local path_record = {
                    tab_index = _pick_state.tab_index,
                    display_label = _pick_state.nav_path[#_pick_state.nav_path] and _pick_state.nav_path[#_pick_state.nav_path].text or _("菜单动作"),
                    index_path = index_path,
                    view = _pick_state.view,
                    is_leaf = false,
                }
                local cb = _pick_state.on_done
                _stopPicking()
                if cb then cb(path_record) end
            end
        end,
    }
    buttons[#buttons + 1] = Button:new{
        text = _("取消"),
        width = menu.item_width,
        text_font_bold = true,
        bordersize = Size.border.thin,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        show_parent = menu.show_parent,
        callback = function()
            if _pick_state.active then
                local cb = _pick_state.on_cancel
                _stopPicking()
                if cb then cb() end
            end
        end,
    }
    local vg = VerticalGroup:new{ align = "center" }
    for _i, btn in ipairs(buttons) do
        vg[#vg + 1] = btn
        vg[#vg + 1] = VerticalSpan:new{ width = Size.padding.small }
    end
    return vg
end

_stopPicking = function()
    local menu = _pick_state.menu
    local action_bar = _pick_state.action_bar
    local bars_span = _pick_state.bars_span
    _pick_state.action_bar = nil
    _pick_state.bars_span = nil
    _pick_state.active = false
    _pick_state.menu = nil
    _pick_state.on_done = nil
    _pick_state.on_cancel = nil
    _pick_state.tab_index = nil
    _pick_state.nav_path = nil
    _pick_state.view = nil
    if menu and action_bar then
        local ig = menu.item_group
        for i = #ig, 1, -1 do
            if ig[i] == action_bar or ig[i] == bars_span then table.remove(ig, i) end
        end
        ig:resetLayout()
        menu.dimen.h = ig:getSize().h + menu.bordersize * 2 + menu.padding
        UIManager:setDirty(menu.show_parent, function() return "ui", menu.dimen end)
    end
    UIManager:setDirty("all", "flashui")
    local TouchMenu = require("ui/widget/touchmenu")
    if _orig_onMenuSelect then
        TouchMenu.onMenuSelect = _orig_onMenuSelect
        TouchMenu.backToUpperMenu = _orig_backToUpperMenu
        TouchMenu.switchMenuTab = _orig_switchMenuTab
        TouchMenu.closeMenu = _orig_closeMenu
        TouchMenu.updateItems = _orig_updateItems
        _orig_onMenuSelect = nil
        _orig_backToUpperMenu = nil
        _orig_switchMenuTab = nil
        _orig_closeMenu = nil
        _orig_updateItems = nil
    end
end

local function startPicking(menu, on_done, on_cancel, view)
    local TouchMenu = require("ui/widget/touchmenu")
    if _pick_state.active then _stopPicking() end
    if not _orig_onMenuSelect then
        _orig_onMenuSelect = TouchMenu.onMenuSelect
        _orig_backToUpperMenu = TouchMenu.backToUpperMenu
        _orig_switchMenuTab = TouchMenu.switchMenuTab
        _orig_closeMenu = TouchMenu.closeMenu
        _orig_updateItems = TouchMenu.updateItems
    end
    _pick_state.active = true
    _pick_state.menu = menu
    _pick_state.tab_index = 1
    _pick_state.nav_path = {}
    _pick_state.view = view or "common"
    _pick_state.on_done = on_done
    _pick_state.on_cancel = on_cancel
    TouchMenu.updateItems = function(self, ...)
        local result = _orig_updateItems(self, ...)
        if _pick_state.active and self == menu then
            if not _pick_state.action_bar then _pick_state.action_bar = _makeActionBar(self) end
            if not _pick_state.bars_span then _pick_state.bars_span = VerticalSpan:new{ width = Size.padding.default } end
            self.item_group[#self.item_group + 1] = _pick_state.bars_span
            self.item_group[#self.item_group + 1] = _pick_state.action_bar
            self.item_group:resetLayout()
            self.dimen.h = self.item_group:getSize().h + self.bordersize * 2 + self.padding
            UIManager:setDirty(self.show_parent, function() return "ui", self.dimen end)
        end
        return result
    end
    TouchMenu.closeMenu = function(self, ...)
        if _pick_state.active and self == menu then
            local cb = _pick_state.on_cancel
            _stopPicking()
            if cb then cb() end
        end
        return _orig_closeMenu(self, ...)
    end
    TouchMenu.onMenuSelect = function(self, item, tap_on_checkmark)
        if not _pick_state.active then
            return _orig_onMenuSelect(self, item, tap_on_checkmark)
        end
        local sub = (item.sub_item_table_func and item.sub_item_table_func()) or item.sub_item_table
        local item_index
        for i, it in ipairs(self.item_table or {}) do
            if it == item then item_index = i; break end
        end
        if sub then
            _pick_state.nav_path[#_pick_state.nav_path + 1] = { index = item_index, text = _itemText(item) }
            return _orig_onMenuSelect(self, item, tap_on_checkmark)
        end
        local label = _itemText(item)
        local index_path = {}
        for _i, step in ipairs(_pick_state.nav_path) do index_path[#index_path + 1] = step.index end
        index_path[#index_path + 1] = item_index
        local path_record = {
            tab_index = _pick_state.tab_index,
            display_label = label,
            index_path = index_path,
            view = _pick_state.view,
            is_leaf = true,
        }
        local cb = _pick_state.on_done
        _stopPicking()
        if cb then cb(path_record) end
        return true
    end
    TouchMenu.backToUpperMenu = function(self, no_close)
        if _pick_state.active and self == menu then
            if #self.item_table_stack ~= 0 then
                if #_pick_state.nav_path > 0 then table.remove(_pick_state.nav_path) end
            else
                local cb = _pick_state.on_cancel
                _stopPicking()
                if cb then cb() end
            end
        end
        return _orig_backToUpperMenu(self, no_close)
    end
    TouchMenu.switchMenuTab = function(self, tab_num)
        if _pick_state.active and self == menu then
            _pick_state.tab_index = tab_num
            _pick_state.nav_path = {}
        end
        return _orig_switchMenuTab(self, tab_num)
    end
    menu.cur_tab = nil
    if menu.bar and menu.bar.switchToTab then menu.bar:switchToTab(1) end
    UIManager:show(Notification:new{ text = _("点击任意菜单项录制为快捷操作"), timeout = 2 })
end

-- 按索引路径回放菜单（含分页与子菜单栈恢复）
replayPath = function(menu, path_record)
    if not path_record or not path_record.index_path then return false end
    local TouchMenu = require("ui/widget/touchmenu")
    local _orig_switchMenuTab = TouchMenu.switchMenuTab
    if path_record.tab_index then
        local switch = _orig_switchMenuTab or TouchMenu.switchMenuTab
        switch(menu, path_record.tab_index)
    end
    local function snapshotMenuState()
        local item_table_stack = {}
        for i, item_table in ipairs(menu.item_table_stack or {}) do item_table_stack[i] = item_table end
        return {
            cur_tab = menu.cur_tab,
            item_table = menu.item_table,
            item_table_stack = item_table_stack,
            page = menu.page,
        }
    end
    local function restoreMenuState(state)
        if not menu or not state then return end
        menu.cur_tab = state.cur_tab
        menu.item_table = state.item_table
        menu.item_table_stack = {}
        for i, tbl in ipairs(state.item_table_stack or {}) do menu.item_table_stack[i] = tbl end
        menu.parent_id = nil
        menu.page = state.page or 1
        menu:updateItems(menu.page)
    end
    local saved_state = snapshotMenuState()
    local current_menu = menu
    local current_item = nil
    for i, idx in ipairs(path_record.index_path) do
        if current_menu.perpage then
            local target_page = math.ceil(idx / current_menu.perpage)
            if target_page > 1 and target_page ~= current_menu.page and current_menu.onGotoPage then
                current_menu:onGotoPage(target_page)
            end
        end
        if not current_menu.item_table or not current_menu.item_table[idx] then
            restoreMenuState(saved_state)
            return false
        end
        current_item = current_menu.item_table[idx]
        local should_enter_submenu = (i < #path_record.index_path) or (i == #path_record.index_path and not path_record.is_leaf)
        if should_enter_submenu then
            local sub = (current_item.sub_item_table_func and current_item.sub_item_table_func()) or current_item.sub_item_table
            if not sub or #sub == 0 then
                restoreMenuState(saved_state)
                return false
            end
            current_menu.item_table_stack[#current_menu.item_table_stack + 1] = current_menu.item_table
            current_menu.item_table = sub
            current_menu.page = 1
            if current_menu.updateItems then current_menu:updateItems() end
        end
    end
    if path_record.is_leaf then
        local callback = (current_item.callback_func and current_item.callback_func()) or current_item.callback
        if callback then pcall(callback, current_menu) end
        restoreMenuState(saved_state)
        menu:closeMenu()
    end
    return true
end

-- ============================================================
-- 动作执行与注册
-- ============================================================
local ACTION_REGISTRY = {}
local ACTION_ORDER = {}
local _wifi_optimistic = nil

local function getNetworkMgr()
    local ok, nm = pcall(require, "ui/network/manager")
    return ok and nm or nil
end

local function getAction(id)
    local builtin_overrides = getTable("builtin_overrides")
    if builtin_overrides[id] then
        local base = ACTION_REGISTRY[id]
        return {
            label = builtin_overrides[id].label or (base and base.label) or id,
            icon = builtin_overrides[id].icon or (base and base.icon),
            is_in_place = base and base.is_in_place or false,
            view = builtin_overrides[id].view or (base and base.view) or "common",
            execute = base and base.execute,
        }
    end
    if ACTION_REGISTRY[id] then
        local action = ACTION_REGISTRY[id]
        return {
            label = action.label,
            icon = action.icon,
            is_in_place = action.is_in_place,
            view = action.view or "common",
            execute = action.execute,
        }
    end
    local custom = getTable("custom")
    local cfg = custom[id]
    if type(cfg) == "table" and cfg.label then
        -- 菜单动作：优先用户自定义视图，否则取录制路径的视图
        local view = cfg.view or "common"
        if cfg.action_type == "menu" and cfg.menu_path and cfg.menu_path.view then view = cfg.menu_path.view end
        return {
            label = cfg.label,
            icon = cfg.icon,
            is_in_place = cfg.is_in_place or false,
            view = view,
            execute = function(ctx) executeCustomAction(cfg, ctx) end,
        }
    end
    return nil
end

local function executeAction(id, ctx)
    local action = getAction(id)
    if action and action.execute then
        -- pcall 保护：动作回调异常不得导致 KOReader 崩溃
        local ok, err = pcall(action.execute, ctx or {})
        if not ok then logger.warn("[QuickActions] 动作执行失败:", id, err) end
    end
end

local function isInPlace(id)
    local action = getAction(id)
    return action and action.is_in_place or false
end

local function getLabelForAction(id)
    local overrides = getTable("builtin_overrides")
    if overrides[id] and overrides[id].label then return overrides[id].label end
    local action = getAction(id)
    return action and action.label or id
end

local function getIconForAction(id)
    local overrides = getTable("builtin_overrides")
    if overrides[id] and overrides[id].icon then return overrides[id].icon end
    if id == "wifi" then
        if _wifi_optimistic ~= nil then return _wifi_optimistic and "nerd:ECA8" or "nerd:ECA9" end
        local NetworkMgr = getNetworkMgr()
        if NetworkMgr then
            local ok, is_on = pcall(function() return NetworkMgr:isWifiOn() end)
            if ok and is_on then return "nerd:ECA8" else return "nerd:ECA9" end
        end
        return "nerd:ECA8"
    end
    if id == "toggle_cloze_mode" then
        local reader = require("apps/reader/readerui").instance
        if reader and reader.highlight then
            local annotations = reader.highlight.ui.annotation.annotations
            if annotations then
                for idx, item in ipairs(annotations) do
                    if item.drawer and reader.highlight._temp_covered and reader.highlight._temp_covered[idx] then
                        return "nerd:F070"
                    end
                end
            end
        end
        return "nerd:F06E"
    end
    local action = getAction(id)
    return action and action.icon or nil
end

local function registerAction(id, label, icon, is_in_place, view, execute_fn)
    ACTION_REGISTRY[id] = {
        label = label,
        icon = icon,
        is_in_place = is_in_place,
        view = view or "common",
        execute = execute_fn,
    }
    ACTION_ORDER[#ACTION_ORDER + 1] = id
end

-- ============================================================
-- 注册内置动作（如需删除可直接删除相应注册代码）
-- ============================================================
registerAction("wifi", _("Wi-Fi"), "net-wifi.svg", true, "common", function(ctx)
    local NetworkMgr = getNetworkMgr()
    if not NetworkMgr then
        UIManager:show(InfoMessage:new{ text = _("WiFi not available"), timeout = 2 })
        return
    end
    local is_on = NetworkMgr:isWifiOn()
    _wifi_optimistic = not is_on
    if ctx.touch_menu then ctx.touch_menu:updateItems() end
    if is_on then NetworkMgr:turnOffWifi() else NetworkMgr:turnOnWifi() end
    UIManager:scheduleIn(2, function()
        _wifi_optimistic = nil
        if ctx.touch_menu then ctx.touch_menu:updateItems() end
    end)
end)

registerAction("night", _("夜间模式"), "nerd:F186", true, "common", function(ctx)
    local G = rawget(_G, "G_reader_settings")
    local night_mode = G and G:isTrue("night_mode") or false
    Screen:toggleNightMode()
    UIManager:ToggleNightMode(not night_mode)
    if G then G:saveSetting("night_mode", not night_mode) end
    UIManager:setDirty("all", "full")
end)

registerAction("rotate", _("旋转"), "nerd:E8BC", true, "common", function(ctx)
    UIManager:broadcastEvent(Event:new("SwapRotation"))
end)

registerAction("screenshot", _("截屏（4秒后）"), "nerd:E7FF", false, "common", function(ctx)
    local function showCountdown(num)
        UIManager:show(Notification:new{ text = tostring(num), timeout = 1 })
    end
    showCountdown(3)
    UIManager:scheduleIn(1, function()
        showCountdown(2)
        UIManager:scheduleIn(1, function()
            UIManager:scheduleIn(1, function()
                local ui = require("apps/reader/readerui").instance
                if not ui then ui = require("apps/filemanager/filemanager").instance end
                if ui and ui.screenshoter then
                    ui.screenshoter:onScreenshot()
                else
                    local Screenshoter = require("ui/widget/screenshoter")
                    Screenshoter:new{ ui = ui }:onScreenshot()
                end
            end)
        end)
    end)
end)

registerAction("continue", _("继续阅读"), "nerd:F405", false, "common", function(ctx)
    local reader = require("apps/reader/readerui").instance
    local RH = require("readhistory")
    local target_file = nil
    if reader and reader.document then
        target_file = RH:getPreviousFile(reader.document.file)
    else
        target_file = RH and RH.hist and RH.hist[1] and RH.hist[1].file
    end
    if target_file then
        require("apps/reader/readerui"):showReader(target_file)
    else
        UIManager:show(InfoMessage:new{ text = _("没有找到最近阅读的书籍"), timeout = 2 })
    end
end)

registerAction("search", _("搜索"), "nerd:F002", false, "common", function(ctx)
    local reader = require("apps/reader/readerui").instance
    if reader and reader.search then
        reader.search:onShowFulltextSearchInput()
    else
        local fm = require("apps/filemanager/filemanager").instance
        if fm and fm.filesearcher then fm.filesearcher:onShowFileSearch() end
    end
end)

registerAction("quit", _("退出"), "nerd:F08B", false, "common", function(ctx)
    UIManager:quit()
end)

registerAction("restart", _("重启"), "nerd:F01E", false, "common", function(ctx)
    UIManager:restartKOReader()
end)

registerAction("power", _("电源"), "nerd:F011", true, "common", function(ctx)
    local buttons = {}
    if Device:canRestart() then
        buttons[#buttons + 1] = {{ text = _("重启"), callback = function() UIManager:restartKOReader() end }}
    end
    if Device:canSuspend() then
        buttons[#buttons + 1] = {{ text = _("睡眠"), callback = function() UIManager:suspend() end }}
    end
    buttons[#buttons + 1] = {{ text = _("退出"), callback = function() UIManager:quit() end }}
    UIManager:show(ButtonDialog:new{ width = math.floor(Screen:getWidth() * 0.42), buttons = buttons })
end)

registerAction("httpinspector", _("HTTP服务器"), "nerd:E701", true, "common", function(ctx)
    local ui = require("apps/reader/readerui").instance
    if not ui then ui = require("apps/filemanager/filemanager").instance end
    if not ui then
        UIManager:show(Notification:new{ text = _("无法获取UI实例"), timeout = 2 })
        return
    end
    local menu_items = ui.menu and ui.menu.menu_items
    local handled = false
    if menu_items and menu_items.httpremote then
        local sub_items = menu_items.httpremote.sub_item_table
        if sub_items and #sub_items > 0 and type(sub_items[1].callback) == "function" then
            local touchmenu_instance = ui.menu.menu_container and ui.menu.menu_container[1] or nil
            sub_items[1].callback(touchmenu_instance)
            closeTouchMenu(ctx)
            local is_running = ui.httpinspector and ui.httpinspector:isRunning() or false
            UIManager:show(Notification:new{
                text = is_running and _("HTTP服务器已启动") or _("HTTP服务器已关闭"),
                timeout = 2,
            })
            handled = true
        end
    end
    if not handled then
        if ui and ui.httpinspector then
            if ui.httpinspector:isRunning() then
                ui.httpinspector:stop()
                UIManager:show(Notification:new{ text = _("HTTP服务器已关闭"), timeout = 2 })
            else
                ui.httpinspector:start()
                UIManager:show(Notification:new{ text = _("HTTP服务器已启动"), timeout = 2 })
            end
        else
            UIManager:show(InfoMessage:new{ text = _("未找到httpinspector插件实例"), timeout = 2 })
        end
    end
end)

registerAction("fontlist", "字体列表", "nerd:F031", false, "reader", function(ctx)
    local reader = require("apps/reader/readerui").instance
    local cre = require("document/credocument"):engineInit()
    if not reader then
        UIManager:show(InfoMessage:new{ text = "请先打开一本书", timeout = 2 })
        return
    end
    closeTouchMenu(ctx)
    local face_list = cre.getFontFaces()
    table.sort(face_list, function(a, b) return a:lower() < b:lower() end)
    local current_font = reader.view.font_face or G_reader_settings:readSetting("cre_font")
    local buttons = {}
    local font_dialog = nil
    for idx, face in ipairs(face_list) do
        local font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(face)
        if not font_filename then font_filename, font_faceindex = cre.getFontFaceFilenameAndFaceIndex(face, nil, true) end
        local display_name = face
        if font_filename and font_faceindex then display_name = FontList:getLocalizedFontName(font_filename, font_faceindex) or face end
        local is_checked = (face == current_font)
        buttons[#buttons + 1] = {{
            text = display_name .. (is_checked and "  ✓" or ""),
            callback = function()
                if font_dialog then UIManager:close(font_dialog); font_dialog = nil end
                if reader and reader.view then
                    reader.view.font_face = face
                    reader.view.ui.document:setFontFace(face)
                    reader.view.ui:handleEvent(Event:new("UpdatePos"))
                    if reader.view.ui.doc_settings then reader.view.ui.doc_settings:saveSetting("font_face", face) end
                    UIManager:show(Notification:new{ text = string.format("字体已设置为: %s", display_name), timeout = 2 })
                end
            end,
        }}
    end
    font_dialog = ButtonDialog:new{
        title = "选择字体",
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
        rows_per_page = 10,
    }
    UIManager:show(font_dialog)
end)

registerAction("qa_settings", _("快捷操作设置"), "nerd:E73A", false, "common", function(ctx)
    showSettingsMenu()
end)

local function refreshPanelMenus()
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1] then
        fm.menu.menu_container[1]:updateItems()
    end
    local reader = require("apps/reader/readerui").instance
    if reader and reader.menu and reader.menu.menu_container and reader.menu.menu_container[1] then
        reader.menu.menu_container[1]:updateItems()
    end
end

registerAction("qa_new", _("新建快捷操作"), "nerd:F067", false, "common", function()
    showCustomQADialog(nil, function() refreshPanelMenus() end)
end)

registerAction("ui_font_switch", _("切换UI字体"), "nerd:F30B", true, "common", function(ctx)
    showUIFontSwitcher()
end)

registerAction("qa_add_button", _("添加按钮"), "nerd:F055", false, "common", function()
    local touch_menu = nil
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1] then
        touch_menu = fm.menu.menu_container[1]
    else
        local reader = require("apps/reader/readerui").instance
        if reader and reader.menu and reader.menu.menu_container and reader.menu.menu_container[1] then
            touch_menu = reader.menu.menu_container[1]
        end
    end
    showAddButtonMenu(touch_menu)
end)

registerAction("fmcoversettings", _("封面视觉设置"), "nerd:E8C8", false, "filemanager", function()
    local reader = require("apps/reader/readerui").instance
    if reader then
        UIManager:show(InfoMessage:new{ text = _("此功能仅在文件管理器中可用"), timeout = 2 })
    else
        UIManager:broadcastEvent(Event:new("FMCoverSettings"))
    end
end)

registerAction("toggle_cloze_mode", _("遮盖模式"), "nerd:F040", false, "reader", function(ctx)
    local reader = require("apps/reader/readerui").instance
    if reader then
        UIManager:broadcastEvent(Event:new("Toggleclozemode"))
        if ctx and ctx.touch_menu then ctx.touch_menu:updateItems() end
    else
        UIManager:show(InfoMessage:new{ text = _("请先打开一本书"), timeout = 2 })
    end
end)

registerAction("reading_insights", _("阅读统计"), "nerd:F073", false, "common", function(ctx)
    UIManager:broadcastEvent(Event:new("ShowReadingInsightsPopup"))
end)

registerAction("filebrowserplus", _("FilebrowserPlus"), "nerd:F029", true, "common", function()
    local fm, reader = getInstances()
    local plugin = (fm and fm.filebrowserplus) or (reader and reader.filebrowserplus)
    if plugin then
        if plugin:isRunning() then plugin:stop() else plugin:start() end
    else
        UIManager:show(InfoMessage:new{
            text = _("未找到filebrowserplus插件实例或方法，请检查插件是否已安装或者修改动作注册方法以适应更新后的插件"),
            timeout = 2,
        })
    end
end)

registerAction("zlibrary_search", _("ZLibrary搜索"), "nerd:E76F", false, "common", function()
    local fm, reader = getInstances()
    local plugin = (fm and fm.zlibrary) or (reader and reader.zlibrary)
    if plugin and plugin.onZlibrarySearch then
        plugin:onZlibrarySearch()
    else
        UIManager:show(InfoMessage:new{
            text = _("未找到zlibrary 插件实例或方法，请检查插件是否已安装或者修改动作注册方法以适应更新后的插件"),
            timeout = 2,
        })
    end
end)

registerAction("cloudlibrary_autosync", _("CloudLibrary-省心同步"), "nerd:E33B", false, "common", function()
    local fm, reader = getInstances()
    local plugin = (fm and fm.CloudLibrary) or (reader and reader.CloudLibrary)
    if plugin then
        plugin:toggleAutoSyncQuick()
    else
        UIManager:show(InfoMessage:new{
            text = _("未找到cloudLibrary 插件实例或方法，请检查插件是否已安装或者修改动作注册方法以适应更新后的插件"),
            timeout = 2,
        })
    end
end)

registerAction("cloudlibrary_batch_download_books", _("CloudLibrary-批量下载/删除"), "nerd:F409", false, "common", function()
    local fm, reader = getInstances()
    local plugin = (fm and fm.CloudLibrary) or (reader and reader.CloudLibrary)
    if plugin then
        plugin:batchDownloadBooks()
    else
        UIManager:show(InfoMessage:new{
            text = _("未找到cloudLibrary 插件实例或方法，请检查插件是否已安装或者修改动作注册方法以适应更新后的插件"),
            timeout = 2,
        })
    end
end)

registerAction("cloudlibrary_settings", _("CloudLibrary-云库设置"), "nerd:E33D", false, "common", function()
    local fm, reader = getInstances()
    local plugin = (fm and fm.CloudLibrary) or (reader and reader.CloudLibrary)
    if plugin then
        if reader then plugin:onCloudLibrarySettingsReader() else plugin:onCloudLibrarySettingsFileManager() end
    else
        UIManager:show(InfoMessage:new{
            text = _("未找到cloudLibrary 插件实例或方法，请检查插件是否已安装或者修改动作注册方法以适应更新后的插件"),
            timeout = 2,
        })
    end
end)

registerAction("annotations_viewer", _("annotationsviewer"), "nerd:F040", false, "common", function()
    local fm, reader = getInstances()
    local has_plugin = (reader and reader.annotationsviewer) or (fm and fm.annotationsviewer)
    if not has_plugin then
        UIManager:show(InfoMessage:new{ text = _("annotationsviewer 插件未安装"), timeout = 2 })
        return
    end
    if reader then
        UIManager:broadcastEvent(Event:new("ShowCurrentBookAnnotations"))
    else
        UIManager:broadcastEvent(Event:new("ShowAllAnnotations"))
    end
end)

-- ============================================================
-- 界面专用配置（view 管理）
-- ============================================================
local function isMenuAction(action_id)
    local cfg = getTable("custom")[action_id]
    return cfg and cfg.action_type == "menu"
end

local function getActionViewFinal(action_id)
    if not action_id then return "common" end
    local overrides = getTable("builtin_overrides")
    if overrides and overrides[action_id] and overrides[action_id].view then return overrides[action_id].view end
    local cfg = getTable("custom")[action_id]
    if cfg then
        if cfg.action_type == "menu" and cfg.menu_path and cfg.menu_path.view then return cfg.menu_path.view end
        if cfg.view then return cfg.view end
    end
    if ACTION_REGISTRY[action_id] then return ACTION_REGISTRY[action_id].view or "common" end
    return "common"
end

local function setCustomActionView(action_id, view)
    local custom = getTable("custom")
    local cfg = custom[action_id]
    if not cfg then return end
    cfg.view = view
    setTable("custom", custom)
end

local function toggleDedicated(action_id, target_view)
    if isMenuAction(action_id) then return end
    local current_view = getActionViewFinal(action_id)
    local is_builtin = ACTION_REGISTRY[action_id] ~= nil
    if is_builtin then
        local overrides = getTable("builtin_overrides")
        if not overrides[action_id] then overrides[action_id] = {} end
        overrides[action_id].view = current_view == target_view and "common" or target_view
        setTable("builtin_overrides", overrides)
    else
        setCustomActionView(action_id, current_view == target_view and "common" or target_view)
    end
end

local function getActionSymbol(id)
    if ACTION_ORDER then
        for _i, builtin_id in ipairs(ACTION_ORDER) do
            if builtin_id == id then return (nerdIconChar("nerd:E002") or "○") .. " " end
        end
    end
    local cfg = getTable("custom")[id]
    local symbols = { menu = "⊚ ", dispatcher = "⊕ ", plugin = "⬡ ", collection = "⊞ ", folder = "◇ " }
    if cfg and symbols[cfg.action_type] then return symbols[cfg.action_type] end
    return "● "
end

local function getTypePriority(id)
    local cfg = getTable("custom")[id]
    local priority = { menu = 1, dispatcher = 2, plugin = 3, folder = 4, collection = 5 }
    if cfg and priority[cfg.action_type] then return priority[cfg.action_type] end
    if ACTION_ORDER then
        for _i, builtin_id in ipairs(ACTION_ORDER) do
            if builtin_id == id then return 7 end
        end
    end
    return 8
end

-- 全部可用动作（内置 + 自定义），按 custom_list 顺序
local function getAllActions()
    local all = {}
    for i = 1, #ACTION_ORDER do
        local id = ACTION_ORDER[i]
        if id then
            all[#all + 1] = { id = id, label = getLabelForAction(id), view = getActionViewFinal(id), is_builtin = true }
        end
    end
    local custom_list = getSetting("custom_list")
    if type(custom_list) == "table" then
        for i = 1, #custom_list do
            local id = custom_list[i]
            local cfg = getTable("custom")[id]
            if cfg then
                local view = cfg.view or "common"
                if cfg.action_type == "menu" and cfg.menu_path and cfg.menu_path.view then view = cfg.menu_path.view end
                all[#all + 1] = { id = id, label = cfg.label, view = view, is_builtin = false }
            end
        end
    end
    return all
end

local function isActionVisible(action_id, current_view)
    if not getBool("qa_context_filter") then return true end
    local view = getActionViewFinal(action_id)
    if current_view == "filemanager" then return view == "filemanager" or view == "common" end
    if current_view == "reader" then return view == "reader" or view == "common" end
    return true
end

-- ============================================================
-- Dispatcher 工具（settingsList 只读一次并缓存；注册表运行期不变）
-- ============================================================
local DISPATCHER_SECTIONS = {
    { key = "general", title = _("通用") },
    { key = "device", title = _("设备") },
    { key = "screen", title = _("屏幕和灯光") },
    { key = "filemanager", title = _("文件浏览器") },
    { key = "reader", title = _("阅读器") },
    { key = "rolling", title = _("流式文档 (epub, fb2, txt…)") },
    { key = "paging", title = _("固定布局文档 (pdf, djvu, 图片…)") },
}

-- settingsList 缓存：运行期不变（KOReader 启动时完成 Dispatcher 注册）。
-- 注意：不能用函数名存字段（LuaJIT 不支持对函数值索引，会崩溃）
local dispatcher_settings_cache = nil
local function getDispatcherSettingsList()
    if dispatcher_settings_cache ~= nil then return dispatcher_settings_cache end
    local ok, DispatcherMod = pcall(require, "dispatcher")
    local settingsList = nil
    if ok and DispatcherMod and type(DispatcherMod.registerAction) == "function" then
        pcall(DispatcherMod.init, DispatcherMod)
        local i = 1
        while true do
            local name, val = debug.getupvalue(DispatcherMod.registerAction, i)
            if not name then break end
            if name == "settingsList" then settingsList = val; break end
            i = i + 1
        end
    end
    dispatcher_settings_cache = settingsList
    return settingsList
end

-- 依据 Dispatcher 定义确定默认视图
local function dispatcherView(def)
    if not def then return "common" end
    if def.filemanager then return "filemanager" end
    if def.reader or def.rolling or def.paging then return "reader" end
    return "common"
end

-- 获取系统动作列表（含 def，供动作选择器直接使用）
local function getDispatcherActions()
    local settingsList = getDispatcherSettingsList()
    if type(settingsList) ~= "table" then return {} end
    local order
    local ok, DispatcherMod = pcall(require, "dispatcher")
    if ok and DispatcherMod then
        local i = 1
        while true do
            local name, val = debug.getupvalue(DispatcherMod.registerAction, i)
            if not name then break end
            if name == "dispatcher_menu_order" then order = val; break end
            i = i + 1
        end
    end
    if type(order) ~= "table" then
        order = {}
        for key in pairs(settingsList) do order[#order + 1] = key end
        table.sort(order)
    end
    local result = {}
    for _i, action_id in ipairs(order) do
        local def = settingsList[action_id]
        if type(def) == "table" and def.title and def.category and (def.condition == nil or def.condition == true) then
            local section_key = "general"
            for _i, sec in ipairs(DISPATCHER_SECTIONS) do
                if def[sec.key] == true then section_key = sec.key; break end
            end
            result[#result + 1] = {
                id = action_id,
                title = tostring(def.title),
                category = def.category,
                def = def,
                section_key = section_key,
            }
        end
    end
    return result
end

local function getDefaultViewForActionType(action_type, action_value)
    if action_type == "folder" or action_type == "collection" then return "filemanager" end
    if action_type == "plugin" then return "common" end
    if action_type == "dispatcher" then
        if not action_value then return "common" end
        local settingsList = getDispatcherSettingsList()
        return dispatcherView(settingsList and settingsList[action_value])
    end
    if action_type == "menu" then
        if not action_value or type(action_value) ~= "table" then return "common" end
        return action_value.view or "common"
    end
    return "common"
end

-- ============================================================
-- 工具函数
-- ============================================================
local function getCollectionsList()
    local ok, RC = pcall(require, "readcollection")
    if not ok or not RC then return {} end
    pcall(RC._read, RC)
    local collections = {}
    if RC.coll then
        for name in pairs(RC.coll) do
            if name ~= RC.default_collection_name then collections[#collections + 1] = name end
        end
    end
    table.sort(collections, function(a, b) return a:lower() < b:lower() end)
    return collections
end

-- ============================================================
-- 删除和移除
-- ============================================================
local function deleteCustomQA(qa_id)
    CONFIG_DATA = nil
    loadConfig()
    local custom = getTable("custom")
    custom[qa_id] = nil
    setTable("custom", custom)
    local list = getSetting("custom_list")
    if type(list) ~= "table" then list = {} end
    local new_list = {}
    for _i, id in ipairs(list) do
        if id ~= qa_id then new_list[#new_list + 1] = id end
    end
    setSetting("custom_list", new_list)
end

function removeFromPanel(action_id, touch_menu)
    local slots = getQASlots()
    local found = false
    local new_slots = {}
    for _i, sid in ipairs(slots) do
        if sid == action_id then found = true else new_slots[#new_slots + 1] = sid end
    end
    if not found then
        UIManager:show(Notification:new{ text = _("快捷操作标签页中没有该按钮"), timeout = 2 })
        return false
    end
    saveQASlots(new_slots)
    if touch_menu then touch_menu:updateItems() end
    return true
end

-- ============================================================
-- 通用菜单显示框架（灰底标题栏 + 返回导航）
-- ============================================================
local function showMenu(items, title, parent_stack, touch_menu, root_items, no_title)
    local dialog_title = (not no_title) and (title or _("快捷中心")) or nil
    local buttons = {}
    if dialog_title then
        buttons[#buttons + 1] = {{ text = dialog_title, background = Blitbuffer.COLOR_LIGHT_GRAY, callback = function() end }}
    end
    if parent_stack and #parent_stack > 0 then
        if #parent_stack > 1 then
            buttons[#buttons + 1] = {{
                text = "◂◂ " .. _("返回根菜单"),
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                callback = function()
                    closeSettingsDialog()
                    showMenu(root_items, _("快捷中心"), nil, touch_menu, root_items)
                end
            }}
        end
        buttons[#buttons + 1] = {{
            text = "◂ " .. _("返回"),
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            callback = function()
                local parent = parent_stack[#parent_stack]
                closeSettingsDialog()
                showMenu(parent.items, parent.title, parent.parent_stack, touch_menu, root_items)
            end
        }}
        buttons[#buttons + 1] = {}
    end
    for i = 1, #items do
        local item = items[i]
        local sub_table = item.sub_item_table
        if type(sub_table) == "function" then sub_table = sub_table() end
        if sub_table and type(sub_table) == "table" and #sub_table > 0 then
            local display_text = item.text
            if type(display_text) == "function" then display_text = display_text() end
            buttons[#buttons + 1] = {{
                text = "  " .. display_text .. " ▸",
                hold_callback = item.hold_callback,
                callback = function()
                    if _settings_dialog then UIManager:close(_settings_dialog); _settings_dialog = nil end
                    local new_stack = {}
                    if parent_stack then
                        for _i, v in ipairs(parent_stack) do new_stack[#new_stack + 1] = v end
                    end
                    new_stack[#new_stack + 1] = { items = items, title = title, parent_stack = parent_stack }
                    showMenu(sub_table, display_text, new_stack, touch_menu, root_items)
                end
            }}
        else
            local checked = item.checked_func and item.checked_func() or false
            local display_text = item.text
            if type(display_text) == "function" then display_text = display_text() end
            local enabled = (item.enabled == nil) or (type(item.enabled) == "function" and item.enabled()) or item.enabled
            buttons[#buttons + 1] = {{
                text = (checked and "✓ " or "  ") .. display_text,
                enabled = enabled,
                callback = function()
                    if item.callback then item.callback() end
                    closeSettingsDialog()
                    if not item.close_on_click then
                        refreshQuickPanel(touch_menu)
                        showMenu(items, title, parent_stack, touch_menu, root_items)
                    end
                end
            }}
        end
    end
    _settings_dialog = ButtonDialog:new{
        title = nil, -- 标题已由灰色标题栏承担
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    UIManager:show(_settings_dialog)
end

-- ============================================================
-- 编辑快捷操作（内置动作）
-- ============================================================
local VIEW_OPTIONS = { "common", "filemanager", "reader" }
local VIEW_LABELS = {
    common = _("通用"),
    filemanager = _("文件管理器"),
    reader = _("阅读器"),
}

-- 图标按钮文本（Nerd 字符或文件名）
local function iconButtonText(icon)
    if not icon then return _("图标: 默认（点击更改图标）") end
    local nerd_char = nerdIconChar(icon)
    if nerd_char then
        return _("图标") .. ": " .. nerd_char .. " (" .. icon:match("nerd:(.+)") .. ")"
    end
    local fname = icon:match("([^/]+)$") or icon
    return _("图标") .. ": " .. (fname:match("^(.+)%.[^%.]+$") or fname):gsub("_", " ")
end

-- 界面选择子对话框
local function showViewPickerDialog(current_view, on_pick, on_cancel)
    -- 前向声明：必须在按钮回调闭包定义之前，否则闭包内的 view_dialog 引用
    -- 会解析为全局 nil，UIManager:close(nil) 无效，对话框永不关闭（窗口栈残留）
    local view_dialog = nil
    local view_buttons = {}
    for _i, v in ipairs(VIEW_OPTIONS) do
        local _v = v
        view_buttons[#view_buttons + 1] = {{
            text = (current_view == _v and "✓ " or "  ") .. VIEW_LABELS[_v],
            callback = function()
                UIManager:close(view_dialog)
                if on_pick then on_pick(_v) end
            end,
        }}
    end
    view_buttons[#view_buttons + 1] = {{
        text = _("返回"),
        callback = function()
            UIManager:close(view_dialog)
            if on_cancel then on_cancel() end
        end,
    }}
    view_dialog = ButtonDialog:new{
        title = _("选择界面"),
        title_align = "center",
        buttons = view_buttons,
        -- 点击外部 / 实体返回键关闭时同样走 on_cancel，
        -- 确保编辑框被正确重建，避免对话框状态丢失（返回后错乱）
        tap_close_callback = function()
            if on_cancel then on_cancel() end
        end,
    }
    UIManager:show(view_dialog)
end

-- 在按钮槽位列表中把 id 移动一格（dir=1 下移, -1 上移）
local function moveSlot(id, dir)
    local slots = getQASlots()
    for i = 1, #slots do
        if slots[i] == id then
            local j = i + dir
            if j >= 1 and j <= #slots then
                slots[i], slots[j] = slots[j], slots[i]
                saveQASlots(slots)
            end
            return
        end
    end
end

local function showEditActionDialog(action_id, on_done)
    local action = getAction(action_id)
    if not action then return end
    local current_label = action.label
    local current_icon = action.icon
    local current_view = getActionViewFinal(action_id)
    local current_action_type = isMenuAction(action_id) and "menu" or nil
    local active_dialog = nil

    local function getCurrentPosition()
        local slots = getQASlots()
        for i, id in ipairs(slots) do
            if id == action_id then return i, #slots end
        end
        return nil, #slots
    end

    -- no_keyboard：视图选择器关闭后重建时不弹键盘，避免键盘 Enter 误触“保存”，
    -- 且无键盘的表单与视图选择器视觉可区分，防止误触
    local function rebuildDialog(no_keyboard)
        if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
        local function viewButtonText()
            if current_action_type == "menu" then
                return _("界面") .. ": " .. VIEW_LABELS[current_view] .. " (" .. _("已锁定") .. ")"
            end
            return _("界面") .. ": " .. VIEW_LABELS[current_view]
        end
        local fields = { { description = _("名称"), text = current_label, hint = _("动作名称…") } }
        local pos, total = getCurrentPosition()
        local last_row = { { text = _("取消"), callback = function()
            if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
        end } }
        local function grabLabel()
            if active_dialog then
                local inputs = active_dialog:getFields()
                if inputs and inputs[1] then current_label = inputs[1] end
            end
        end
        last_row[#last_row + 1] = { text = _("移除"), callback = function()
            grabLabel()
            if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
            removeFromPanel(action_id, nil)
            if on_done then on_done() end
        end }
        if pos then
            last_row[#last_row + 1] = { text = "◀", enabled = (pos > 1), callback = function()
                grabLabel()
                if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                moveSlot(action_id, -1)
                rebuildDialog()
            end }
            last_row[#last_row + 1] = { text = pos .. "/" .. total, callback = function()
                if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                showArrangeDialog(touch_menu, nil, function()
                    if on_done then on_done() end
                end)
            end }
            last_row[#last_row + 1] = { text = "▶", enabled = (pos < total), callback = function()
                grabLabel()
                if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                moveSlot(action_id, 1)
                rebuildDialog()
            end }
        end
        last_row[#last_row + 1] = { text = _("保存"), is_enter_default = true, callback = function()
            if not active_dialog then return end
            local inputs = active_dialog:getFields()
            local new_label = inputs[1] or ""
            if new_label == "" then
                UIManager:show(InfoMessage:new{ text = _("请输入名称"), timeout = 2 })
                return
            end
            UIManager:close(active_dialog)
            active_dialog = nil
            local builtin_overrides = getTable("builtin_overrides")
            if not builtin_overrides[action_id] then builtin_overrides[action_id] = {} end
            builtin_overrides[action_id].label = new_label
            builtin_overrides[action_id].icon = current_icon
            builtin_overrides[action_id].view = current_view
            setTable("builtin_overrides", builtin_overrides)
            if on_done then on_done() end
        end }
        local buttons = {
            { { text = iconButtonText(current_icon), callback = function()
                grabLabel()
                if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                showIconPicker(function(new_icon)
                    current_icon = new_icon
                    rebuildDialog(true) -- 不弹键盘：防误触（与视图选择器同模式）
                end, current_icon)
            end } },
            { { text = viewButtonText(), enabled = (current_action_type ~= "menu"), callback = function()
                if current_action_type == "menu" then return end
                grabLabel()
                if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                showViewPickerDialog(current_view, function(v)
                    current_view = v
                    rebuildDialog(true)
                end, function() rebuildDialog(true) end)
            end } },
            last_row,
        }
        active_dialog = MultiInputDialog:new{
            title = _("编辑快捷操作"),
            fields = fields,
            tap_close_callback = function()
                UIManager:close(active_dialog)
                active_dialog = nil
            end,
            buttons = buttons,
        }
        UIManager:show(active_dialog)
        if not no_keyboard then
            pcall(function() active_dialog:onShowKeyboard() end)
        end
    end

    rebuildDialog()
end

local function getCustomItems(touch_menu)
    local items = {}
    for i = 1, #ACTION_ORDER do
        local id = ACTION_ORDER[i]
        if id then
            items[#items + 1] = {
                id = id,
                text = getActionSymbol(id) .. getLabelForAction(id) .. " [" .. getActionViewFinal(id) .. "]",
                is_builtin = true,
                on_edit = function()
                    showEditActionDialog(id, function() refreshQuickPanel(touch_menu) end)
                end,
                on_delete = nil,
            }
        end
    end
    local custom_list = getSetting("custom_list")
    if type(custom_list) ~= "table" then custom_list = {} end
    for i = 1, #custom_list do
        local id = custom_list[i]
        local cfg = getTable("custom")[id]
        if cfg then
            items[#items + 1] = {
                id = id,
                text = getActionSymbol(id) .. cfg.label .. " [" .. getActionViewFinal(id) .. "]",
                is_builtin = false,
                on_edit = function()
                    showCustomQADialog(id, function() refreshQuickPanel(touch_menu) end)
                end,
                on_delete = function()
                    deleteCustomQA(id)
                    refreshQuickPanel(touch_menu)
                end,
            }
        end
    end
    -- 排序：内置在前（倒序，与原版行为一致），自定义按名称
    local custom_items, builtin_items = {}, {}
    for _i, item in ipairs(items) do
        if item.is_builtin then builtin_items[#builtin_items + 1] = item else custom_items[#custom_items + 1] = item end
    end
    table.sort(custom_items, function(a, b) return a.text:lower() < b.text:lower() end)
    for _i, item in ipairs(builtin_items) do table.insert(custom_items, 1, item) end
    return custom_items
end

-- ============================================================
-- 添加按钮菜单
-- ============================================================
function showAddButtonMenu(touch_menu, on_back)
    local current_dialog = nil
    local slots = getQASlots()
    local slot_set = {}
    for _i, id in ipairs(slots) do slot_set[id] = true end
    local available = getAllActions()
    table.sort(available, function(a, b)
        local a_checked, b_checked = slot_set[a.id] or false, slot_set[b.id] or false
        if a_checked ~= b_checked then return a_checked end
        local a_prio, b_prio = getTypePriority(a.id), getTypePriority(b.id)
        if a_prio ~= b_prio then return a_prio < b_prio end
        return a.label:lower() < b.label:lower()
    end)
    local buttons = {}
    buttons[#buttons + 1] = {{ text = _("添加按钮"), background = Blitbuffer.COLOR_LIGHT_GRAY, callback = function() end }}
    if on_back then
        buttons[#buttons + 1] = {{
            text = "◂◂ " .. _("返回根菜单"),
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            callback = function()
                UIManager:close(current_dialog)
                showSettingsMenu(touch_menu)
            end
        }}
        buttons[#buttons + 1] = {{
            text = "◂ " .. _("返回"),
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            callback = function()
                UIManager:close(current_dialog)
                on_back()
            end
        }}
        buttons[#buttons + 1] = {}
    else
        buttons[#buttons + 1] = {{
            text = "⚙ " .. _("打开主菜单"),
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            callback = function()
                UIManager:close(current_dialog)
                showSettingsMenu(touch_menu)
            end
        }}
        buttons[#buttons + 1] = {}
    end
    local function toggleOpt(key, label, rebuild)
        buttons[#buttons + 1] = {{
            text = (getBool(key) and "✓ " or "  ") .. label,
            callback = function()
                setBool(key, not getBool(key))
                if touch_menu then touch_menu:updateItems() end
                UIManager:close(current_dialog)
                showAddButtonMenu(touch_menu, on_back)
            end,
        }}
    end
    toggleOpt("qa_frontlight", _("前光滑块"))
    if Device:hasNaturalLight() then toggleOpt("qa_warmth", _("色温滑块")) end
    toggleOpt("qa_slider_show_value", _("显示滑块数值"))
    local function getAllChecked()
        for _i, action in ipairs(available) do
            if not slot_set[action.id] then return false end
        end
        return true
    end
    buttons[#buttons + 1] = {{
        text = getAllChecked() and "☑ " .. _("全部取消") or "☐ " .. _("全部添加"),
        callback = function()
            local current_slots = getQASlots()
            local new_slots = {}
            if getAllChecked() then
                -- 只保留不在可用列表中的（不可移除的）按钮
                for _i, id in ipairs(current_slots) do
                    local is_available = false
                    for _i, action in ipairs(available) do
                        if action.id == id then is_available = true; break end
                    end
                    if not is_available then new_slots[#new_slots + 1] = id end
                end
            else
                for _i, id in ipairs(current_slots) do new_slots[#new_slots + 1] = id end
                for _i, action in ipairs(available) do
                    if not slot_set[action.id] then
                        if #new_slots >= MAX_SLOTS then
                            UIManager:show(Notification:new{ text = string.format(_("最多 %d 个按钮"), MAX_SLOTS), timeout = 2 })
                            return
                        end
                        new_slots[#new_slots + 1] = action.id
                    end
                end
            end
            saveQASlots(new_slots)
            if touch_menu then touch_menu:updateItems() end
            UIManager:close(current_dialog)
            showAddButtonMenu(touch_menu, on_back)
        end,
    }}
    buttons[#buttons + 1] = {}
    for i = 1, #available do
        local action = available[i]
        local display_text = (slot_set[action.id] and "✓ " or "  ") .. getActionSymbol(action.id) .. action.label .. " [" .. (action.view or "common") .. "]"
        buttons[#buttons + 1] = {{
            text = display_text,
            callback = function()
                local current_slots = getQASlots()
                local found = false
                for j = 1, #current_slots do
                    if current_slots[j] == action.id then found = true; break end
                end
                if found then
                    local new_slots = {}
                    for j = 1, #current_slots do
                        if current_slots[j] ~= action.id then new_slots[#new_slots + 1] = current_slots[j] end
                    end
                    saveQASlots(new_slots)
                else
                    if #current_slots >= MAX_SLOTS then
                        UIManager:show(Notification:new{ text = string.format(_("最多 %d 个按钮"), MAX_SLOTS), timeout = 2 })
                        return
                    end
                    current_slots[#current_slots + 1] = action.id
                    saveQASlots(current_slots)
                end
                if touch_menu then touch_menu:updateItems() end
                UIManager:close(current_dialog)
                showAddButtonMenu(touch_menu, on_back)
            end,
        }}
    end
    buttons[#buttons + 1] = {}
    buttons[#buttons + 1] = {{ text = _("关闭"), callback = function() UIManager:close(current_dialog) end }}
    current_dialog = ButtonDialog:new{
        title = nil, -- 标题由灰底栏承担
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
        max_height = math.floor(Screen:getHeight() * 0.7),
    }
    UIManager:show(current_dialog)
end

-- ============================================================
-- 界面过滤设置菜单
-- ============================================================
function showInterfaceFilterMenu(touch_menu)
    local function buildDedicatedListItems(mode)
        local target_view = (mode == "fm") and "filemanager" or "reader"
        local items = {}
        local all_actions = getAllActions()
        table.sort(all_actions, function(a, b)
            local a_checked, b_checked = (a.view == target_view), (b.view == target_view)
            if a_checked ~= b_checked then return a_checked end
            local a_common, b_common = (a.view == "common"), (b.view == "common")
            if a_common ~= b_common then return a_common end
            local a_prio, b_prio = getTypePriority(a.id), getTypePriority(b.id)
            if a_prio ~= b_prio then return a_prio < b_prio end
            return a.label:lower() < b.label:lower()
        end)
        local function allDedicated()
            local all_checked, has_unlocked = true, false
            for _i, action in ipairs(all_actions) do
                if not isMenuAction(action.id) then
                    has_unlocked = true
                    if getActionViewFinal(action.id) ~= target_view then all_checked = false; break end
                end
            end
            return has_unlocked and all_checked or true
        end
        items[#items + 1] = {
            text = function() return allDedicated() and "☑ " .. _("全部取消") or "☐ " .. _("全部专用") end,
            enabled = function()
                for _i, action in ipairs(all_actions) do
                    if not isMenuAction(action.id) then return true end
                end
                return false
            end,
            close_on_click = false,
            callback = function()
                local is_all = allDedicated()
                for _i, action in ipairs(all_actions) do
                    if not isMenuAction(action.id) then
                        local current = getActionViewFinal(action.id)
                        if (is_all and current == target_view) or (not is_all and current ~= target_view) then
                            toggleDedicated(action.id, target_view)
                        end
                    end
                end
                if touch_menu then refreshQuickPanel(touch_menu) end
            end,
        }
        items[#items + 1] = { text = "----------------------------", enabled = false }
        for _i, action in ipairs(all_actions) do
            local action_id = action.id
            local is_locked = isMenuAction(action_id)
            items[#items + 1] = {
                text = function()
                    local prefix = (getActionViewFinal(action_id) == target_view) and "✓ " or "  "
                    local display = prefix .. getActionSymbol(action_id) .. getLabelForAction(action_id) .. " [" .. getActionViewFinal(action_id) .. "]"
                    return is_locked and (display .. " (" .. _("锁定") .. ")") or display
                end,
                enabled = not is_locked,
                close_on_click = false,
                callback = function()
                    if is_locked then return end
                    toggleDedicated(action_id, target_view)
                    if touch_menu then refreshQuickPanel(touch_menu) end
                end,
            }
        end
        return items
    end
    return {
        {
            text = function()
                local enabled = getBool("qa_context_filter")
                return (enabled and "✓ " or "  ") .. _("启用界面过滤")
            end,
            close_on_click = false,
            callback = function()
                setBool("qa_context_filter", not getBool("qa_context_filter"))
                refreshQuickPanel(touch_menu)
            end,
        },
        {
            text = function()
                local fm = 0
                for _i, act in ipairs(getAllActions()) do
                    if act.view == "filemanager" then fm = fm + 1 end
                end
                return string.format(_("文件管理器专用 (%d)"), fm)
            end,
            close_on_click = true,
            sub_item_table = function() return buildDedicatedListItems("fm") end,
        },
        {
            text = function()
                local rd = 0
                for _i, act in ipairs(getAllActions()) do
                    if act.view == "reader" then rd = rd + 1 end
                end
                return string.format(_("阅读器专用 (%d)"), rd)
            end,
            close_on_click = true,
            sub_item_table = function() return buildDedicatedListItems("reader") end,
        },
        {
            text = _("重置为默认专用"),
            close_on_click = true,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("重置所有专用设置到默认值？"),
                    ok_text = _("重置"),
                    cancel_text = _("取消"),
                    ok_callback = function()
                        setTable("builtin_overrides", {})
                        local custom = getTable("custom")
                        for id, cfg in pairs(custom) do
                            if cfg.action_type == "menu" then
                                cfg.view = cfg.menu_path.view or cfg.view
                            else
                                local action_val = cfg.dispatcher_action or cfg.action_value
                                cfg.view = getDefaultViewForActionType(cfg.action_type, action_val)
                            end
                        end
                        setTable("custom", custom)
                        refreshQuickPanel(touch_menu)
                        UIManager:show(Notification:new{ text = _("已重置为默认专用"), timeout = 2 })
                    end,
                })
            end,
        },
    }
end

-- ============================================================
-- 自定义动作编辑对话框
-- ============================================================
function showCustomQADialog(qa_id, on_done)
    local collections = getCollectionsList()
    table.sort(collections, function(a, b) return a:lower() < b:lower() end)

    local custom = getTable("custom")
    local cfg = qa_id and custom[qa_id] or {}
    local start_path = cfg.action_value or (G_reader_settings:readSetting("home_dir") or "/")
    local chosen_icon = cfg.icon
    local dlg_title = qa_id and _("编辑快捷操作") or _("新建快捷操作")
    local existing_label = cfg.label or ""

    local current_action_type = nil
    local current_action_val1 = nil
    local current_action_val2 = nil
    local current_action_title = nil
    if cfg.action_type == "dispatcher" and cfg.dispatcher_action then
        current_action_type = "dispatcher"
        current_action_val1 = cfg.dispatcher_action
        current_action_val2 = cfg.dispatcher_value or true
        current_action_title = cfg.dispatcher_action
    elseif cfg.action_type == "plugin" and cfg.plugin_key then
        current_action_type = "plugin"
        current_action_val1 = cfg.plugin_key
        current_action_val2 = cfg.plugin_method
        current_action_title = cfg.plugin_key
    elseif cfg.action_type == "collection" and cfg.action_value then
        current_action_type = "collection"
        current_action_val1 = cfg.action_value
        current_action_title = cfg.action_value
    elseif cfg.action_type == "folder" and cfg.action_value then
        current_action_type = "folder"
        current_action_val1 = cfg.action_value
        current_action_title = cfg.action_value:match("([^/]+)$") or cfg.action_value
    elseif cfg.action_type == "menu" and cfg.menu_path then
        current_action_type = "menu"
        current_action_val1 = cfg.menu_path
        current_action_title = cfg.menu_path.display_label or _("菜单动作")
    end

    local active_dialog = nil
    local choice_dialog = nil
    local coll_picker = nil
    local plugin_picker = nil
    local disp_picker = nil
    -- 菜单动作：默认取录制路径视图；若用户自定义过则取 cfg.view
    local current_view = cfg.view or "common"

    local buildSaveDialog
    local openActionPicker

    local function closeDispatcherDialogs()
        if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
        if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
        if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
    end

    -- 系统动作（Dispatcher）可配置参数子菜单
    local function buildConfigurableSubItems(item, def, ctx)
        return function()
            if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
            if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
            local sub_items = {}
            local args, toggle = def.args, def.toggle
            if def.args_func then
                local ok, a, t = pcall(def.args_func)
                if ok then args, toggle = a, t end
            end
            sub_items[#sub_items + 1] = {{ text = "⚙️ " .. _("打开主菜单"), callback = function()
                if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
                if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
                ctx.closeSettingsDialog()
                ctx.showSettingsMenu(ctx.touch_menu)
            end }}
            sub_items[#sub_items + 1] = {{ text = "◂◂ " .. _("返回编辑框"), callback = function()
                if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
                if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
                ctx.buildSaveDialog(false)
            end }}
            sub_items[#sub_items + 1] = {{ text = "◂ " .. _("返回"), callback = function()
                if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
                ctx.openDispatcherPicker(ctx.touch_menu)
            end }}
            sub_items[#sub_items + 1] = {}
            if args and #args > 0 then
                for index, value in ipairs(args) do
                    local display = toggle and toggle[index] or tostring(value)
                    sub_items[#sub_items + 1] = {{
                        text = display,
                        callback = function()
                            if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
                            ctx.set.action_type("dispatcher")
                            ctx.set.action_val1(item.id)
                            ctx.set.action_val2(value)
                            ctx.set.action_title(display)
                            ctx.set.view(dispatcherView(def))
                            ctx.buildSaveDialog(true)
                        end,
                    }}
                end
            end
            sub_dialog = ButtonDialog:new{
                title = item.title,
                title_align = "center",
                buttons = sub_items,
                width = math.floor(Screen:getWidth() * 0.7),
            }
            UIManager:show(sub_dialog)
        end
    end

    -- 插件/补丁列表（带 pcall 保护）
    local function getPluginsList()
        local ok_loader, PluginLoader = pcall(require, "pluginloader")
        if ok_loader and PluginLoader and type(PluginLoader.loadPlugins) == "function" then
            pcall(PluginLoader.loadPlugins, PluginLoader)
        end
        local plugins = PluginScan.scan()
        return plugins
    end

    local function commitQA(final_label, path, collection, icon, plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path, user_view)
        local list = getSetting("custom_list")
        if type(list) ~= "table" then list = {} end
        local max_n = 0
        for _i, id in ipairs(list) do
            local n = tonumber(id:match("^custom_qa_(%d+)$"))
            if n and n > max_n then max_n = n end
        end
        local final_id = qa_id or ("custom_qa_" .. (max_n + 1))
        local custom_tbl = getTable("custom")
        local custom_list = getSetting("custom_list")
        if type(custom_list) ~= "table" then custom_list = {} end
        local action_type, default_view = nil, "common"
        if path and path ~= "" then
            action_type, default_view = "folder", "filemanager"
        elseif collection and collection ~= "" then
            action_type, default_view = "collection", "filemanager"
        elseif plugin_key and plugin_key ~= "" then
            action_type, default_view = "plugin", "common"
        elseif dispatcher_action and dispatcher_action ~= "" then
            action_type = "dispatcher"
            default_view = getDefaultViewForActionType("dispatcher", dispatcher_action)
        elseif menu_path and type(menu_path) == "table" then
            action_type = "menu"
            default_view = menu_path.view or "common"
        end
        local final_view
        if action_type == "menu" then final_view = default_view else final_view = user_view or default_view end
        local cfg_table = {
            label = final_label,
            icon = icon,
            is_in_place = (dispatcher_action ~= nil or plugin_key ~= nil),
            action_type = action_type,
        }
        if action_type ~= "menu" then cfg_table.view = final_view end
        if path and path ~= "" then
            cfg_table.action_value = path
        elseif collection and collection ~= "" then
            cfg_table.action_value = collection
        elseif plugin_key and plugin_key ~= "" then
            cfg_table.plugin_key = plugin_key
            if dispatcher_value and type(dispatcher_value) == "table" and dispatcher_value.type == "submenu" then
                cfg_table.plugin_method = "submenu"
                cfg_table.plugin_path_indices = dispatcher_value.path_indices
            else
                cfg_table.plugin_method = (type(plugin_method) == "string") and plugin_method or PluginScan.SENTINEL
            end
        elseif dispatcher_action and dispatcher_action ~= "" then
            cfg_table.dispatcher_action = dispatcher_action
            cfg_table.dispatcher_value = dispatcher_value
        elseif menu_path and type(menu_path) == "table" then
            cfg_table.menu_path = menu_path
        end
        custom_tbl[final_id] = cfg_table
        setTable("custom", custom_tbl)
        if getBool("qa_auto_add_to_panel") then
            local slots = getQASlots()
            local already_exists = false
            for _i, sid in ipairs(slots) do
                if sid == final_id then already_exists = true; break end
            end
            if not already_exists then
                if #slots < MAX_SLOTS then
                    slots[#slots + 1] = final_id
                    saveQASlots(slots)
                else
                    UIManager:show(InfoMessage:new{
                        text = string.format(_("按钮面板已满（最多 %d 个），无法自动添加。"), MAX_SLOTS),
                        timeout = 3,
                    })
                end
            end
        end
        if not qa_id then
            custom_list[#custom_list + 1] = final_id
            setSetting("custom_list", custom_list)
        end
        if on_done then on_done() end
    end

    local function cancelActionPicker()
        if not current_action_type and not qa_id then
            if on_done then on_done() end
        else
            if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
            buildSaveDialog(false)
        end
    end

    local function openIconPicker()
        local saved_label = existing_label
        if active_dialog then
            local inputs = active_dialog:getFields()
            if inputs and inputs[1] then
                saved_label = inputs[1]
                existing_label = inputs[1]
            end
            UIManager:close(active_dialog)
            active_dialog = nil
        end
        showIconPicker(function(result)
            chosen_icon = result
            buildSaveDialog(false, true) -- 不弹键盘：防误触（与视图选择器同模式）
        end, chosen_icon)
    end

    openActionPicker = function()
        if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
        choice_dialog = ButtonDialog:new{
            title = _("动作类型"),
            title_align = "center",
            buttons = {
                {{ text = _("文件夹"), callback = function()
                    UIManager:close(choice_dialog)
                    choice_dialog = nil
                    local pc = PathChooser:new{
                        select_directory = true,
                        select_file = false,
                        path = start_path,
                        onConfirm = function(path)
                            path = path:gsub("/$", "")
                            current_action_type = "folder"
                            current_action_val1 = path
                            current_action_title = path:match("([^/]+)$") or path
                            current_view = "filemanager"
                            buildSaveDialog(true)
                        end,
                        onCancel = function() cancelActionPicker() end,
                    }
                    UIManager:show(pc)
                end }},
                {{ text = _("集合"), enabled = #collections > 0, callback = function()
                    UIManager:close(choice_dialog)
                    choice_dialog = nil
                    local coll_buttons = {}
                    for _i, name in ipairs(collections) do
                        local _name = name
                        coll_buttons[#coll_buttons + 1] = {{ text = name, callback = function()
                            if coll_picker then UIManager:close(coll_picker); coll_picker = nil end
                            if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
                            current_action_type = "collection"
                            current_action_val1 = _name
                            current_action_title = _name
                            current_view = "filemanager"
                            buildSaveDialog(true)
                        end }}
                    end
                    coll_buttons[#coll_buttons + 1] = {{ text = _("返回"), callback = function()
                        if coll_picker then UIManager:close(coll_picker); coll_picker = nil end
                        openActionPicker()
                    end }}
                    coll_picker = ButtonDialog:new{ title = _("选择集合"), title_align = "center", buttons = coll_buttons }
                    UIManager:show(coll_picker)
                end }},
                {{ text = _("插件或补丁"), callback = function()
                    UIManager:close(choice_dialog)
                    choice_dialog = nil
                    local plugins = getPluginsList()
                    if #plugins == 0 then
                        UIManager:show(InfoMessage:new{ text = _("没有可用的插件或补丁"), timeout = 3 })
                        cancelActionPicker()
                        return
                    end
                    -- 递归显示插件子菜单（传递索引路径）
                    -- 前向声明：showPluginSubMenu/showPluginList 互相引用，必须先声明再赋值
                    -- （否则闭包引用会解析为全局 nil，点“返回”崩溃）
                    local showPluginSubMenu
                    local showPluginList
                    showPluginSubMenu = function(plugin_key, plugin_title, items, level, parent_indices)
                        parent_indices = parent_indices or {}
                        local buttons = {}
                        if level > 0 then
                            buttons[#buttons + 1] = {{ text = "◂ " .. _("返回"), callback = function()
                                if plugin_picker then UIManager:close(plugin_picker); plugin_picker = nil end
                                showPluginList()
                            end }}
                            buttons[#buttons + 1] = {}
                        end
                        for idx, item in ipairs(items or {}) do
                            if type(item) == "table" then
                                local text = entry_text(item) or _("未命名")
                                local sub = menuSubTable(item)
                                if sub and #sub > 0 then
                                    local new_indices = {}
                                    for _i, p in ipairs(parent_indices) do new_indices[#new_indices + 1] = p end
                                    new_indices[#new_indices + 1] = idx
                                    buttons[#buttons + 1] = {{
                                        text = text .. " ▸",
                                        callback = function()
                                            if plugin_picker then UIManager:close(plugin_picker); plugin_picker = nil end
                                            showPluginSubMenu(plugin_key, plugin_title .. " → " .. text, sub, level + 1, new_indices)
                                        end,
                                    }}
                                elseif type(item.callback) == "function" then
                                    local full_indices = {}
                                    for _i, p in ipairs(parent_indices) do full_indices[#full_indices + 1] = p end
                                    full_indices[#full_indices + 1] = idx
                                    buttons[#buttons + 1] = {{
                                        text = text,
                                        callback = function()
                                            if plugin_picker then UIManager:close(plugin_picker); plugin_picker = nil end
                                            if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
                                            current_action_type = "plugin"
                                            current_action_val1 = plugin_key
                                            current_action_val2 = { type = "submenu", path_indices = full_indices }
                                            current_action_title = text
                                            current_view = "common"
                                            buildSaveDialog(true)
                                        end,
                                    }}
                                end
                            end
                        end
                        if #buttons == (level > 0 and 2 or 0) then
                            buttons[#buttons + 1] = {{ text = _("（无可用动作）"), enabled = false }}
                        end
                        plugin_picker = ButtonDialog:new{
                            title = level == 0 and _("选择插件或补丁") or plugin_title,
                            title_align = "center",
                            buttons = buttons,
                            width = math.floor(Screen:getWidth() * 0.7),
                            max_height = math.floor(Screen:getHeight() * 0.7),
                        }
                        UIManager:show(plugin_picker)
                    end
                    -- 插件与补丁分开列出
                    showPluginList = function()
                        local buttons = {}
                        local plugin_buttons, patch_buttons = {}, {}
                        for _i, p in ipairs(plugins) do
                            if p.is_patch then
                                patch_buttons[#patch_buttons + 1] = {{
                                    text = p.display_title or p.title,
                                    callback = function()
                                        if plugin_picker then UIManager:close(plugin_picker); plugin_picker = nil end
                                        if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
                                        current_action_type = "plugin"
                                        current_action_val1 = p.key
                                        current_action_val2 = PluginScan.SENTINEL
                                        current_action_title = p.title
                                        current_view = "common"
                                        buildSaveDialog(true)
                                    end,
                                }}
                            else
                                local mod = live_plugin(p.key)
                                if mod and type(mod.addToMainMenu) == "function" then
                                    local entry = probe_menu_entry(mod, p.key)
                                    if entry then
                                        local sub = menuSubTable(entry)
                                        if sub and #sub > 0 then
                                            plugin_buttons[#plugin_buttons + 1] = {{
                                                text = p.title .. " ▸",
                                                callback = function()
                                                    if plugin_picker then UIManager:close(plugin_picker); plugin_picker = nil end
                                                    showPluginSubMenu(p.key, p.title, sub, 1, {})
                                                end,
                                            }}
                                        elseif type(entry.callback) == "function" then
                                            plugin_buttons[#plugin_buttons + 1] = {{
                                                text = p.title,
                                                callback = function()
                                                    if plugin_picker then UIManager:close(plugin_picker); plugin_picker = nil end
                                                    if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
                                                    current_action_type = "plugin"
                                                    current_action_val1 = p.key
                                                    current_action_val2 = PluginScan.SENTINEL
                                                    current_action_title = p.title
                                                    current_view = "common"
                                                    buildSaveDialog(true)
                                                end,
                                            }}
                                        end
                                    end
                                end
                            end
                        end
                        table.sort(plugin_buttons, function(a, b) return (a[1].text or ""):lower() < (b[1].text or ""):lower() end)
                        table.sort(patch_buttons, function(a, b) return (a[1].text or ""):lower() < (b[1].text or ""):lower() end)
                        for _i, btn in ipairs(plugin_buttons) do buttons[#buttons + 1] = btn end
                        if #plugin_buttons > 0 and #patch_buttons > 0 then
                            buttons[#buttons + 1] = {{ text = "──────────────────", enabled = false }}
                        end
                        for _i, btn in ipairs(patch_buttons) do buttons[#buttons + 1] = btn end
                        if #buttons == 0 then
                            buttons[#buttons + 1] = {{ text = _("没有可用的插件动作"), enabled = false }}
                        end
                        buttons[#buttons + 1] = {{ text = _("返回"), callback = function()
                            if plugin_picker then UIManager:close(plugin_picker); plugin_picker = nil end
                            openActionPicker()
                        end }}
                        plugin_picker = ButtonDialog:new{
                            title = _("选择插件或补丁"),
                            title_align = "center",
                            buttons = buttons,
                            width = math.floor(Screen:getWidth() * 0.7),
                            max_height = math.floor(Screen:getHeight() * 0.7),
                        }
                        UIManager:show(plugin_picker)
                    end
                    showPluginList()
                end }},
                {{ text = _("系统动作"), callback = function() openDispatcherPicker() end }},
                {{ text = _("录制菜单动作"), callback = function()
                    UIManager:close(choice_dialog)
                    choice_dialog = nil
                    local fm, rui = getInstances()
                    local target_menu = nil
                    local view = "reader"
                    if rui and rui.menu then
                        if not rui.menu.menu_container or not rui.menu.menu_container[1] then rui.menu:onShowMenu() end
                        target_menu = rui.menu.menu_container and rui.menu.menu_container[1]
                        view = "reader"
                    elseif fm and fm.menu then
                        if not fm.menu.menu_container or not fm.menu.menu_container[1] then fm.menu:onShowMenu() end
                        target_menu = fm.menu.menu_container and fm.menu.menu_container[1]
                        view = "filemanager"
                    end
                    if not target_menu then
                        UIManager:show(InfoMessage:new{ text = _("请先打开菜单"), timeout = 3 })
                        cancelActionPicker()
                        return
                    end
                    startPicking(target_menu, function(path_record)
                        if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
                        local function cleanString(s)
                            if not s then return "" end
                            return s:gsub("[\n\r]", ""):match("^%s*(.-)%s*$") or ""
                        end
                        local clean_record = {
                            tab_index = path_record.tab_index,
                            display_label = cleanString(path_record.display_label),
                            index_path = path_record.index_path,
                            view = view,
                            is_leaf = path_record.is_leaf,
                        }
                        current_action_type = "menu"
                        current_action_val1 = clean_record
                        current_action_title = clean_record.display_label
                        current_view = view
                        buildSaveDialog(true)
                    end, function() cancelActionPicker() end)
                end }},
                {{ text = _("返回"), callback = function()
                    if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
                    buildSaveDialog(false)
                end }},
            }
        }
        UIManager:show(choice_dialog)
    end

    buildSaveDialog = function(update_name_with_title, no_keyboard)
        if coll_picker then UIManager:close(coll_picker); coll_picker = nil end
        if plugin_picker then UIManager:close(plugin_picker); plugin_picker = nil end
        if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
        if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
        if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
        if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
        if update_name_with_title and current_action_title then existing_label = current_action_title end

        local action_label = _("动作") .. ": "
        if current_action_type then action_label = action_label .. (current_action_title or "")
        else action_label = action_label .. _("点击设置动作") end

        local function viewButtonText()
            if current_action_type == "menu" then
                return _("界面") .. ": " .. VIEW_LABELS[current_view] .. " (" .. _("已锁定") .. ")"
            end
            return _("界面") .. ": " .. VIEW_LABELS[current_view]
        end

        local fields = { { description = _("名称"), text = existing_label, hint = _("动作名称…") } }

        local function getCurrentPosition()
            if not qa_id then return nil, 0 end
            local slots = getQASlots()
            for i, sid in ipairs(slots) do
                if sid == qa_id then return i, #slots end
            end
            return nil, 0
        end

        local pos, total = getCurrentPosition()
        local last_row = { { text = _("取消"), callback = function()
            UIManager:close(active_dialog)
            active_dialog = nil
            if not qa_id and not current_action_type then if on_done then on_done() end end
        end } }
        local function grabLabel()
            if active_dialog then
                local inputs = active_dialog:getFields()
                if inputs and inputs[1] then existing_label = inputs[1] end
            end
        end
        if qa_id then
            last_row[#last_row + 1] = { text = _("删除"), callback = function()
                grabLabel()
                if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                UIManager:show(ConfirmBox:new{
                    text = string.format(_("删除快捷操作 \"%s\"？"), existing_label),
                    ok_text = _("删除"),
                    cancel_text = _("取消"),
                    ok_callback = function()
                        deleteCustomQA(qa_id)
                        local new_slots = {}
                        for _i, sid in ipairs(getQASlots()) do
                            if sid ~= qa_id then new_slots[#new_slots + 1] = sid end
                        end
                        saveQASlots(new_slots)
                        if on_done then on_done() end
                    end,
                })
            end }
        end
        if pos then
            last_row[#last_row + 1] = { text = "◀", enabled = (pos > 1), callback = function()
                grabLabel()
                if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                moveSlot(qa_id, -1)
                buildSaveDialog(false)
            end }
            last_row[#last_row + 1] = { text = pos .. "/" .. total, callback = function()
                if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                showArrangeDialog(touch_menu, nil, function()
                    if on_done then on_done() end
                end)
            end }
            last_row[#last_row + 1] = { text = "▶", enabled = (pos < total), callback = function()
                grabLabel()
                if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                moveSlot(qa_id, 1)
                buildSaveDialog(false)
            end }
        end
        last_row[#last_row + 1] = { text = _("移除"), callback = function()
            grabLabel()
            if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
            removeFromPanel(qa_id, nil)
            if on_done then on_done() end
        end }
        last_row[#last_row + 1] = { text = _("保存"), is_enter_default = true, callback = function()
            local inputs = active_dialog:getFields()
            local final_label = inputs[1] or ""
            if final_label == "" then
                UIManager:show(InfoMessage:new{ text = _("请输入名称"), timeout = 2 })
                return
            end
            if not current_action_type then
                UIManager:show(InfoMessage:new{ text = _("请选择动作类型"), timeout = 2 })
                return
            end
            UIManager:close(active_dialog)
            active_dialog = nil
            local default_icon = "nerd:F114"
            if current_action_type == "plugin" then default_icon = "nerd:F1B2"
            elseif current_action_type == "dispatcher" then default_icon = "nerd:E235"
            elseif current_action_type == "menu" then default_icon = "nerd:E7FB"
            elseif current_action_type == "collection" then default_icon = "nerd:E257" end
            local path, collection, plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path
            if current_action_type == "folder" then
                path = current_action_val1
            elseif current_action_type == "collection" then
                collection = current_action_val1
            elseif current_action_type == "plugin" then
                plugin_key = current_action_val1
                if type(current_action_val2) == "table" and current_action_val2.type == "submenu" then
                    dispatcher_value = current_action_val2
                    plugin_method = nil
                else
                    plugin_method = current_action_val2
                end
            elseif current_action_type == "dispatcher" then
                dispatcher_action = current_action_val1
                dispatcher_value = current_action_val2
            elseif current_action_type == "menu" then
                menu_path = current_action_val1
            end
            commitQA(final_label, path, collection, chosen_icon or default_icon, plugin_key, plugin_method, dispatcher_action, dispatcher_value, menu_path, current_view)
        end }
        local buttons = {
            { { text = action_label, callback = function()
                grabLabel()
                openActionPicker()
            end } },
            { { text = iconButtonText(chosen_icon), callback = function() openIconPicker() end } },
            { { text = viewButtonText(), enabled = (current_action_type ~= "menu"), callback = function()
                if current_action_type == "menu" then return end
                grabLabel()
                if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                showViewPickerDialog(current_view, function(v)
                    current_view = v
                    buildSaveDialog(false, true)
                end, function() buildSaveDialog(false, true) end)
            end } },
            last_row,
        }
        active_dialog = MultiInputDialog:new{
            title = dlg_title,
            fields = fields,
            tap_close_callback = function()
                UIManager:close(active_dialog)
                active_dialog = nil
                if not qa_id and not current_action_type then if on_done then on_done() end end
            end,
            buttons = buttons,
        }
        UIManager:show(active_dialog)
        -- no_keyboard：视图选择器关闭后重建不弹键盘（防 Enter 误触保存 / 视觉混淆）
        if not no_keyboard then
            pcall(function() active_dialog:onShowKeyboard() end)
        end
    end

    openDispatcherPicker = function(touch_menu)
        if choice_dialog then UIManager:close(choice_dialog); choice_dialog = nil end
        local actions = getDispatcherActions()
        if #actions == 0 then
            UIManager:show(InfoMessage:new{ text = _("没有可用的系统动作"), timeout = 3 })
            cancelActionPicker()
            return
        end
        local sections_map = {}
        for _i, sec in ipairs(DISPATCHER_SECTIONS) do
            sections_map[sec.key] = { title = sec.title, items = {} }
        end
        for _i, action in ipairs(actions) do
            sections_map[action.section_key or "general"].items[#sections_map[action.section_key or "general"].items + 1] = action
        end
        local section_buttons = {}
        for _i, sec in ipairs(DISPATCHER_SECTIONS) do
            local items = sections_map[sec.key].items
            if #items > 0 then
                table.sort(items, function(a, b) return a.title:lower() < b.title:lower() end)
                local action_buttons = {}
                action_buttons[#action_buttons + 1] = {{ text = "⚙️ " .. _("打开主菜单"), callback = function()
                    if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
                    if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
                    closeSettingsDialog()
                    showSettingsMenu(touch_menu)
                end }}
                action_buttons[#action_buttons + 1] = {{ text = "◂◂ " .. _("返回编辑框"), callback = function()
                    if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
                    if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
                    buildSaveDialog(false)
                end }}
                action_buttons[#action_buttons + 1] = {{ text = "◂ " .. _("返回"), callback = function()
                    if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
                    openDispatcherPicker(touch_menu)
                end }}
                action_buttons[#action_buttons + 1] = {}
                for _i, item in ipairs(items) do
                    local _item = item
                    local category, def = item.category, item.def
                    if category == "none" or category == "arg" then
                        action_buttons[#action_buttons + 1] = {{
                            text = item.title,
                            callback = function()
                                closeDispatcherDialogs()
                                current_action_type = "dispatcher"
                                current_action_val1 = _item.id
                                current_action_val2 = true
                                current_action_title = _item.title
                                current_view = dispatcherView(def)
                                buildSaveDialog(true)
                            end,
                        }}
                    elseif category == "absolutenumber" or category == "incrementalnumber" then
                        action_buttons[#action_buttons + 1] = {{
                            text = item.title,
                            callback = function()
                                if sub_dialog then UIManager:close(sub_dialog); sub_dialog = nil end
                                local spin = SpinWidget:new{
                                    title_text = _item.title,
                                    value = def.default or def.min or 0,
                                    value_min = def.min or 0,
                                    value_max = def.max or 100,
                                    value_step = def.step or 1,
                                    unit = def.unit,
                                    callback = function(spin)
                                        closeDispatcherDialogs()
                                        current_action_type = "dispatcher"
                                        current_action_val1 = _item.id
                                        current_action_val2 = spin.value
                                        current_action_title = _item.title .. ": " .. tostring(spin.value)
                                        current_view = dispatcherView(def)
                                        buildSaveDialog(true)
                                    end,
                                }
                                UIManager:show(spin)
                            end,
                        }}
                    elseif category == "string" or category == "configurable" then
                        action_buttons[#action_buttons + 1] = {{
                            text = item.title,
                            callback = buildConfigurableSubItems(_item, def, {
                                touch_menu = touch_menu,
                                buildSaveDialog = buildSaveDialog,
                                openDispatcherPicker = openDispatcherPicker,
                                closeSettingsDialog = closeSettingsDialog,
                                showSettingsMenu = showSettingsMenu,
                                set = {
                                    action_type = function(v) current_action_type = v end,
                                    action_val1 = function(v) current_action_val1 = v end,
                                    action_val2 = function(v) current_action_val2 = v end,
                                    action_title = function(v) current_action_title = v end,
                                    view = function(v) current_view = v end,
                                },
                            })
                        }}
                    end
                end
                if #action_buttons > 4 then
                    section_buttons[#section_buttons + 1] = {{
                        text = sec.title,
                        callback = function()
                            if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
                            sub_dialog = ButtonDialog:new{
                                title = sec.title,
                                title_align = "center",
                                buttons = action_buttons,
                                width = math.floor(Screen:getWidth() * 0.7),
                            }
                            UIManager:show(sub_dialog)
                        end,
                    }}
                else
                    for _i, btn in ipairs(action_buttons) do section_buttons[#section_buttons + 1] = btn end
                end
            end
        end
        local final_buttons = {}
        final_buttons[#final_buttons + 1] = {{ text = "⚙️ " .. _("打开主菜单"), callback = function()
            if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
            closeSettingsDialog()
            showSettingsMenu(touch_menu)
        end }}
        final_buttons[#final_buttons + 1] = {{ text = "◂◂ " .. _("返回编辑框"), callback = function()
            if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
            buildSaveDialog(false)
        end }}
        final_buttons[#final_buttons + 1] = {{ text = "◂ " .. _("返回"), callback = function()
            if disp_picker then UIManager:close(disp_picker); disp_picker = nil end
            openActionPicker()
        end }}
        final_buttons[#final_buttons + 1] = {}
        for _i, btn in ipairs(section_buttons) do final_buttons[#final_buttons + 1] = btn end
        disp_picker = ButtonDialog:new{
            title = _("系统动作"),
            title_align = "center",
            buttons = final_buttons,
            width = math.floor(Screen:getWidth() * 0.7),
        }
        UIManager:show(disp_picker)
    end

    buildSaveDialog(false)
end

-- ============================================================
-- 快捷方式：勾选的动作列表（设置子菜单与手势菜单共用）
-- （顶层局部变量已达 Lua 上限，此处改用全局函数）
-- ============================================================
function getShortcuts()
    local s = getSetting("qa_shortcuts")
    return type(s) == "table" and s or {}
end

function saveShortcuts(list) setSetting("qa_shortcuts", list) end

function isShortcut(id)
    for _i, v in ipairs(getShortcuts()) do
        if v == id then return true end
    end
    return false
end

function toggleShortcut(id)
    local list, found = getShortcuts(), false
    for i = #list, 1, -1 do
        if list[i] == id then table.remove(list, i); found = true end
    end
    if not found then list[#list + 1] = id end
    saveShortcuts(list)
end

-- 设置内子菜单：列出已添加到快捷操作菜单的动作，勾选即去除
function getShortcutMenuItems(touch_menu)
    local items = {}
    for _i, id in ipairs(getShortcuts()) do
        items[#items + 1] = {
            text = getLabelForAction(id),
            checked_func = function() return isShortcut(id) end,
            callback = function() toggleShortcut(id) end,
        }
    end
    if #items == 0 then
        items[#items + 1] = {
            text = _("还没有快捷操作，请在「编辑快捷操作」中勾选「添加到快捷操作菜单」"),
            enabled = false,
        }
    end
    return items
end

-- 手势唤出列表：无标题栏，运行后关闭
function getShortcutActionItems(touch_menu)
    local current_view = "filemanager"
    if getBool("qa_context_filter") then
        local reader = require("apps/reader/readerui").instance
        current_view = (reader and not reader.tearing_down) and "reader" or "filemanager"
    end
    local items = {}
    for _i, id in ipairs(getShortcuts()) do
        if getAction(id) and isActionVisible(id, current_view) then
            items[#items + 1] = {
                text = getLabelForAction(id),
                close_on_click = true,
                callback = function()
                    UIManager:scheduleIn(0, function()
                        executeAction(id, { touch_menu = touch_menu })
                    end)
                end,
            }
        end
    end
    if #items == 0 then
        items[#items + 1] = {
            text = _("还没有快捷方式，请在「编辑快捷操作」中勾选"),
            enabled = false,
        }
    end
    return items
end

-- ============================================================
-- 重置所有配置
-- ============================================================
local function resetAllSettings(touch_menu)
    picker_cache = {}
    cached_file_icons = nil
    system_temp_overrides = nil
    local new_config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        if type(v) == "table" then
            new_config[k] = {}
            for k2, v2 in pairs(v) do new_config[k][k2] = v2 end
        else
            new_config[k] = v
        end
    end
    local f = io.open(CONFIG_PATH, "w")
    if f then
        f:write("return " .. serializeTable(new_config))
        f:close()
    end
    CONFIG_DATA = new_config
    local fm = require("apps/filemanager/filemanager").instance
    local current_menu = fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1] or nil
    if not current_menu then
        local reader = require("apps/reader/readerui").instance
        current_menu = reader and reader.menu and reader.menu.menu_container and reader.menu.menu_container[1] or nil
    end
    if current_menu and current_menu.updateItems then current_menu:updateItems() end
end

-- ============================================================
-- 排列按钮：QuickCenter 框样式（灰底标题栏 + 返回导航 + ▲▼ 调整顺序）
-- ============================================================
function showArrangeDialog(touch_menu, on_back, on_done)
    local current_dialog = nil
    local slots = {}
    for _i, id in ipairs(getQASlots()) do slots[#slots + 1] = id end

    local function finish()
        UIManager:close(current_dialog)
        current_dialog = nil
        if on_done then on_done() end
    end

    local function rebuild()
        local buttons = {}
        buttons[#buttons + 1] = {{ text = _("排列按钮"), background = Blitbuffer.COLOR_LIGHT_GRAY, callback = function() end }}
        if on_back then
            buttons[#buttons + 1] = {{
                text = "◂◂ " .. _("返回根菜单"),
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                callback = function()
                    saveQASlots(slots)
                    if current_dialog then UIManager:close(current_dialog); current_dialog = nil end
                    if on_done then on_done() end
                    showSettingsMenu(touch_menu)
                end,
            }, {
                text = "◂ " .. _("返回"),
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                callback = function()
                    saveQASlots(slots)
                    if current_dialog then UIManager:close(current_dialog); current_dialog = nil end
                    if on_done then on_done() end
                    on_back()
                end,
            }}
            buttons[#buttons + 1] = {}
        end
        for i = 1, #slots do
            local idx = i
            local move_w = Screen:scaleBySize(44)
            buttons[#buttons + 1] = {
                { text = tostring(idx) .. ". " .. getLabelForAction(slots[i]), callback = function() end },
                { text = "▲", width = move_w, callback = function()
                    if idx > 1 then
                        slots[idx], slots[idx - 1] = slots[idx - 1], slots[idx]
                        saveQASlots(slots)
                        rebuild()
                    end
                end },
                { text = "▼", width = move_w, callback = function()
                    if idx < #slots then
                        slots[idx], slots[idx + 1] = slots[idx + 1], slots[idx]
                        saveQASlots(slots)
                        rebuild()
                    end
                end },
            }
        end
        buttons[#buttons + 1] = {{ text = _("完成"), callback = function()
            saveQASlots(slots)
            finish()
        end }}
        if current_dialog then UIManager:close(current_dialog) end
        current_dialog = ButtonDialog:new{
            title = nil, -- 标题由灰底栏承担
            buttons = buttons,
            width = math.floor(Screen:getWidth() * 0.7),
            max_height = math.floor(Screen:getHeight() * 0.7),
        }
        UIManager:show(current_dialog)
    end

    rebuild()
end

-- ============================================================
-- 设置菜单（主入口）
-- ============================================================
function showSettingsMenu(touch_menu)
    if not touch_menu then
        local fm = require("apps/filemanager/filemanager").instance
        touch_menu = fm and fm.menu and fm.menu.menu_container and fm.menu.menu_container[1]
        if not touch_menu then
            local reader = require("apps/reader/readerui").instance
            touch_menu = reader and reader.menu and reader.menu.menu_container and reader.menu.menu_container[1]
        end
    end

    local function getCustomActionSubMenu()
        local items = getCustomItems(touch_menu)
        local sub_items = {}
        local auto_add_key = "qa_auto_add_to_panel"
        sub_items[#sub_items + 1] = {
            text = function()
                return (getBool(auto_add_key) and "✓ " or "  ") .. _("保存时自动添加到按钮")
            end,
            callback = function()
                setBool(auto_add_key, not getBool(auto_add_key))
            end,
            separator = true,
        }
        sub_items[#sub_items + 1] = {
            text = "+ " .. _("新建操作"),
            close_on_click = true,
            callback = function()
                closeSettingsDialog()
                showCustomQADialog(nil, function() refreshQuickPanel(touch_menu) end)
            end,
        }
        local builtin_items, custom_items = {}, {}
        for _i, item in ipairs(items) do
            if item.is_builtin then builtin_items[#builtin_items + 1] = item else custom_items[#custom_items + 1] = item end
        end
        local function actionEntry(item)
            return {
                text = function() return (isShortcut(item.id) and "☑ " or "☐ ") .. item.text end,
                sub_item_table = {
                    {
                        text = "✎ " .. _("编辑动作"),
                        close_on_click = true,
                        callback = function()
                            closeSettingsDialog()
                            item.on_edit()
                        end,
                    },
                    {
                        text = _("添加到快捷操作菜单"),
                        checked_func = function() return isShortcut(item.id) end,
                        callback = function() toggleShortcut(item.id) end,
                    },
                },
            }
        end
        if #builtin_items > 0 then
            local builtin_sub = {}
            for _i, item in ipairs(builtin_items) do builtin_sub[#builtin_sub + 1] = actionEntry(item) end
            sub_items[#sub_items + 1] = { text = _("内置操作"), sub_item_table = builtin_sub }
        end
        local existing_sub = {}
        if #custom_items == 0 then
            existing_sub[#existing_sub + 1] = { text = _("还没有已建立的操作，请先新建"), enabled = false }
        else
            for _i, item in ipairs(custom_items) do existing_sub[#existing_sub + 1] = actionEntry(item) end
        end
        sub_items[#sub_items + 1] = { text = _("已有操作"), sub_item_table = existing_sub }
        return sub_items
    end

    local function getShapeSubMenu()
        return {
            { text = _("圆形"), radio = true, checked_func = function() return getShape() == "round" end, callback = function() setString("qa_shape", "round") end },
            { text = _("圆角方形"), radio = true, checked_func = function() return getShape() == "square_round" end, callback = function() setString("qa_shape", "square_round") end },
            { text = _("无边框"), radio = true, checked_func = function() return getShape() == "bare" end, callback = function() setString("qa_shape", "bare") end },
        }
    end

    local function getBgSubMenu()
        return {
            { text = _("透明"), radio = true, checked_func = function() return getBg() == "transparent" end, callback = function() setString("qa_bg", "transparent") end },
            { text = _("实色"), radio = true, checked_func = function() return getBg() == "solid" end, callback = function() setString("qa_bg", "solid") end },
            { text = _("浅灰"), radio = true, checked_func = function() return getBg() == "flat" end, callback = function() setString("qa_bg", "flat") end },
        }
    end

    -- 返回上一级：重新打开设置菜单并定位到指定子菜单（path 为各级显示文本）
    local root_menu_items
    local function reopenSettingsAt(touch_menu, path)
        local items = root_menu_items
        local title = _("快捷中心")
        local stack = {}
        for i = 1, #path do
            local target = path[i]
            local found = nil
            for _i, item in ipairs(items) do
                local t = item.text
                if type(t) == "function" then t = t() end
                if t == target then found = item; break end
            end
            if not found then
                showSettingsMenu(touch_menu)
                return
            end
            local new_stack = {}
            for _s, e in ipairs(stack) do new_stack[#new_stack + 1] = e end
            new_stack[#new_stack + 1] = { items = items, title = title, parent_stack = stack }
            stack = new_stack
            items = found.sub_item_table
            if type(items) == "function" then items = items() end
            title = target
        end
        showMenu(items, title, stack, touch_menu, root_menu_items)
    end

    -- 配置快照/应用（供 保存配置/更新配置 与 默认配置 复用）
    local function snapshotConfig()
        local json = require("json")
        local function deepCopy(v) return json.decode(json.encode(v)) end
        return {
            qa_tab_icon = getString("qa_tab_icon"),
            qa_enabled = isQAEnabled(),
            qa_slots = deepCopy(getQASlots()),
            qa_frontlight = showFrontlight(),
            qa_warmth = showWarmth(),
            qa_shape = getShape(),
            qa_bg = getBg(),
            qa_labels = showLabels(),
            qa_label_scale_pct = getLabelScalePct(),
            qa_settings_on_hold = settingsOnHold(),
            qa_button_size_pct = getButtonSizePct(),
            qa_button_hold_edit = buttonHoldEdit(),
            custom_list = deepCopy(getSetting("custom_list")),
            custom = deepCopy(getTable("custom")),
            builtin_overrides = deepCopy(getTable("builtin_overrides")),
            qa_context_filter = getBool("qa_context_filter"),
            qa_auto_add_to_panel = getBool("qa_auto_add_to_panel"),
            qa_slider_show_value = showSliderValue(),
            qa_slider_style = getSliderStyle(),
            qa_filter_initialized = getBool("qa_filter_initialized"),
            qa_shortcuts = deepCopy(getShortcuts()),
            qa_layout_enabled = getBool("qa_layout_enabled"),
            qa_layout_rows = getNumber("qa_layout_rows"),
            qa_layout_cols = getNumber("qa_layout_cols"),
            qa_icon_overrides = deepCopy(getTable("qa_icon_overrides")),
            ui_font_overrides = deepCopy(getTable("ui_font_overrides")),
        }
    end

    local function updateSavedConfig(nm)
        local cfg2 = getSetting("saved_configs")
        if type(cfg2) ~= "table" then cfg2 = {} end
        cfg2[nm] = snapshotConfig()
        setSetting("saved_configs", cfg2)
    end

    root_menu_items = {
        {
            text = _("快捷操作"),
            sub_item_table = {
                {
                    text = _("编辑快捷操作"),
                    sub_item_table = getCustomActionSubMenu,
                },
                {
                    text = _("快捷操作菜单"),
                    sub_item_table = function() return getShortcutMenuItems(touch_menu) end,
                },
            },
        },
        {
            text = _("控制中心"),
            sub_item_table = {
                {
                    text = _("排列按钮") .. " ▸",
                    close_on_click = true,
                    callback = function()
                        closeSettingsDialog()
                        showArrangeDialog(touch_menu,
                            function() reopenSettingsAt(touch_menu, { "控制中心" }) end,
                            function() refreshQuickPanel(touch_menu) end)
                    end,
                },
                {
                    text = _("编辑按钮"),
                    sub_item_table = {
                        {
                            text = _("添加按钮") .. " ▸",
                            close_on_click = true,
                            callback = function()
                                closeSettingsDialog()
                                showAddButtonMenu(touch_menu, function()
                                    reopenSettingsAt(touch_menu, { "控制中心", "编辑按钮" })
                                end)
                            end,
                        },
                        {
                            text = _("按钮布局"),
                            sub_item_table = {
                                {
                                    text = function() return (getBool("qa_layout_enabled") and "✓ " or "  ") .. _("启用按钮布局") end,
                                    callback = function()
                                        setBool("qa_layout_enabled", not getBool("qa_layout_enabled"))
                                        refreshQuickPanel(touch_menu)
                                    end,
                                },
                                {
                                    text = function() return _("按钮行数") .. ": " .. getNumber("qa_layout_rows") end,
                                    close_on_click = true,
                                    callback = function()
                                        closeSettingsDialog()
                                        local spin = SpinWidget:new{
                                            title_text = _("按钮行数"),
                                            value = getNumber("qa_layout_rows"),
                                            value_min = 1,
                                            value_max = 6,
                                            value_step = 1,
                                            unit = _("行"),
                                            callback = function(spin)
                                                setNumber("qa_layout_rows", spin.value)
                                                refreshQuickPanel(touch_menu)
                                            end,
                                        }
                                        UIManager:show(spin)
                                    end,
                                },
                                {
                                    text = function() return _("每行按钮数") .. ": " .. getNumber("qa_layout_cols") end,
                                    close_on_click = true,
                                    callback = function()
                                        closeSettingsDialog()
                                        local spin = SpinWidget:new{
                                            title_text = _("每行按钮数"),
                                            value = getNumber("qa_layout_cols"),
                                            value_min = 1,
                                            value_max = 12,
                                            value_step = 1,
                                            unit = _("个"),
                                            callback = function(spin)
                                                setNumber("qa_layout_cols", spin.value)
                                                refreshQuickPanel(touch_menu)
                                            end,
                                        }
                                        UIManager:show(spin)
                                    end,
                                },
                            },
                        },
                        {
                            text = _("按钮形状"),
                            sub_item_table = getShapeSubMenu,
                        },
                        {
                            text = _("按钮背景"),
                            enabled = getShape() ~= "bare",
                            sub_item_table = getBgSubMenu,
                        },
                    },
                },
                {
                    text = _("界面过滤"),
                    sub_item_table = function() return showInterfaceFilterMenu(touch_menu) end,
                },
                {
                    text = _("手势行为"),
                    sub_item_table = {
                        {
                            text = function() return (buttonHoldEdit() and "✓ " or "  ") .. _("长按按钮打开编辑框") end,
                            callback = function()
                                setBool("qa_button_hold_edit", not buttonHoldEdit())
                                refreshQuickPanel(touch_menu)
                            end,
                        },
                        {
                            text = function() return (settingsOnHold() and "✓ " or "  ") .. _("长按控制中心面板打开设置") end,
                            callback = function() setBool("qa_settings_on_hold", not settingsOnHold()) end,
                        },
                    },
                },
                {
                    text = _("滑块样式"),
                    sub_item_table = function()
                        return {
                            { text = _("线条"), radio = true, checked_func = function() return getSliderStyle() == "line" end, callback = function() setString("qa_slider_style", "line") end },
                            { text = _("分段按钮"), radio = true, checked_func = function() return getSliderStyle() == "segment" end, callback = function() setString("qa_slider_style", "segment") end },
                        }
                    end,
                },
                {
                    text = function() return (showLabels() and "✓ " or "  ") .. _("显示标签") end,
                    callback = function() setBool("qa_labels", not showLabels()) end,
                },
                {
                    text = function() return _("按钮大小") .. ": " .. getButtonSizePct() .. "%" end,
                    close_on_click = true,
                    callback = function()
                        closeSettingsDialog()
                        local spin = SpinWidget:new{
                            title_text = _("按钮大小"),
                            value = getButtonSizePct(),
                            value_min = 60,
                            value_max = 150,
                            value_step = 5,
                            unit = "%",
                            callback = function(spin)
                                setNumber("qa_button_size_pct", spin.value)
                                refreshQuickPanel(touch_menu)
                            end,
                        }
                        UIManager:show(spin)
                    end,
                },
                {
                    text = function() return _("标签大小") .. ": " .. getLabelScalePct() .. "%" end,
                    close_on_click = true,
                    callback = function()
                        closeSettingsDialog()
                        local spin = SpinWidget:new{
                            title_text = _("标签大小"),
                            value = getLabelScalePct(),
                            value_min = 50,
                            value_max = 200,
                            value_step = 10,
                            unit = "%",
                            callback = function(spin)
                                setNumber("qa_label_scale_pct", spin.value)
                                refreshQuickPanel(touch_menu)
                            end,
                        }
                        UIManager:show(spin)
                    end,
                },
            },
        },
        {
            text = _("设置"),
            sub_item_table = {
                {
                    text = function() return (isQAEnabled() and "✓ " or "  ") .. _("启用快捷中心") end,
                    callback = function()
                        setBool("qa_enabled", not isQAEnabled())
                        askRestart(_("重启后生效。\n\n立即重启 KOReader？"))
                    end,
                },
                {
                    text = _("配置管理"),
                    sub_item_table = {
                        {
                            text = _("保存配置"),
                            close_on_click = true,
                            callback = function()
                                closeSettingsDialog()
                                local active_dialog = nil
                                active_dialog = MultiInputDialog:new{
                                    title = _("保存配置"),
                                    fields = { { description = _("配置名称"), text = "", hint = _("输入配置名称...") } },
                                    tap_close_callback = function()
                                        UIManager:close(active_dialog)
                                        active_dialog = nil
                                    end,
                                    buttons = {
                                        {
                                            {
                                                text = _("保存"),
                                                is_enter_default = true,
                                                callback = function()
                                                    if not active_dialog then return end
                                                    local inputs = active_dialog:getFields()
                                                    local name = (inputs[1] or ""):gsub("^%s+", ""):gsub("%s+$", "")
                                                    if name == "" then
                                                        UIManager:show(InfoMessage:new{ text = _("请输入配置名称"), timeout = 2 })
                                                        return
                                                    end
                                                    local saved = getSetting("saved_configs")
                                                    if type(saved) ~= "table" then saved = {} end
                                                    saved[name] = snapshotConfig()
                                                    setSetting("saved_configs", saved)
                                                    UIManager:close(active_dialog)
                                                    active_dialog = nil
                                                    UIManager:show(Notification:new{
                                                        text = string.format(_("配置 \"%s\" 已保存"), name),
                                                        timeout = 2,
                                                    })
                                                    showSettingsMenu(touch_menu)
                                                end,
                                            },
                                            {
                                                text = _("取消"),
                                                callback = function()
                                                    if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                                                    showSettingsMenu(touch_menu)
                                                end,
                                            },
                                        },
                                    },
                                }
                                UIManager:show(active_dialog)
                                pcall(function() active_dialog:onShowKeyboard() end)
                            end,
                        },
                        {
                            text = _("编辑配置"),
                            sub_item_table = function()
                                local saved = getSetting("saved_configs")
                                if type(saved) ~= "table" then saved = {} end
                                local names = {}
                                for nm in pairs(saved) do names[#names + 1] = nm end
                                table.sort(names)
                                local items = {}
                                if #names == 0 then
                                    items[#items + 1] = { text = _("还没有保存的配置"), enabled = false }
                                end
                                for _i, nm in ipairs(names) do
                                    items[#items + 1] = {
                                        text = nm,
                                        hold_callback = function()
                                            closeSettingsDialog()
                                            updateSavedConfig(nm)
                                            UIManager:show(Notification:new{
                                                text = string.format(_("配置 \"%s\" 已更新为当前设置"), nm),
                                                timeout = 2,
                                            })
                                        end,
                                        sub_item_table = {
                                            {
                                                text = _("更新配置"),
                                                close_on_click = true,
                                                callback = function()
                                                    closeSettingsDialog()
                                                    updateSavedConfig(nm)
                                                    UIManager:show(Notification:new{
                                                        text = string.format(_("配置 \"%s\" 已更新为当前设置"), nm),
                                                        timeout = 2,
                                                    })
                                                end,
                                            },
                                            {
                                                text = _("重命名"),
                                                close_on_click = true,
                                                callback = function()
                                                    closeSettingsDialog()
                                                    local active_dialog = nil
                                                    active_dialog = MultiInputDialog:new{
                                                        title = _("重命名配置"),
                                                        fields = { { description = _("新名称"), text = nm, hint = _("输入新配置名称...") } },
                                                        tap_close_callback = function()
                                                            UIManager:close(active_dialog)
                                                            active_dialog = nil
                                                        end,
                                                        buttons = {
                                                            {
                                                                {
                                                                    text = _("确定"),
                                                                    is_enter_default = true,
                                                                    callback = function()
                                                                        if not active_dialog then return end
                                                                        local inputs = active_dialog:getFields()
                                                                        local new_nm = (inputs[1] or ""):gsub("^%s+", ""):gsub("%s+$", "")
                                                                        if new_nm ~= "" and new_nm ~= nm then
                                                                            local cfg2 = getSetting("saved_configs")
                                                                            if type(cfg2) ~= "table" then cfg2 = {} end
                                                                            cfg2[new_nm] = cfg2[nm]
                                                                            cfg2[nm] = nil
                                                                            setSetting("saved_configs", cfg2)
                                                                        end
                                                                        UIManager:close(active_dialog)
                                                                        active_dialog = nil
                                                                        showSettingsMenu(touch_menu)
                                                                    end,
                                                                },
                                                                {
                                                                    text = _("取消"),
                                                                    callback = function()
                                                                        if active_dialog then UIManager:close(active_dialog); active_dialog = nil end
                                                                        showSettingsMenu(touch_menu)
                                                                    end,
                                                                },
                                                            },
                                                        },
                                                    }
                                                    UIManager:show(active_dialog)
                                                    pcall(function() active_dialog:onShowKeyboard() end)
                                                end,
                                            },
                                            {
                                                text = _("删除"),
                                                close_on_click = true,
                                                callback = function()
                                                    closeSettingsDialog()
                                                    UIManager:show(ConfirmBox:new{
                                                        text = string.format(_("删除配置 \"%s\"？"), nm),
                                                        ok_text = _("删除"),
                                                        cancel_text = _("取消"),
                                                        ok_callback = function()
                                                            local cfg2 = getSetting("saved_configs")
                                                            if type(cfg2) ~= "table" then cfg2 = {} end
                                                            cfg2[nm] = nil
                                                            setSetting("saved_configs", cfg2)
                                                            UIManager:show(Notification:new{ text = _("配置已删除"), timeout = 2 })
                                                        end,
                                                    })
                                                end,
                                            },
                                        },
                                    }
                                end
                                return items
                            end,
                        },
                        {
                            text = _("重设配置"),
                            close_on_click = true,
                            callback = function()
                                closeSettingsDialog()
                                UIManager:show(ConfirmBox:new{
                                    text = _("重置所有设置到初始默认值？\n这将清除所有自定义动作及您保存的配置。"),
                                    ok_text = _("重置"),
                                    cancel_text = _("取消"),
                                    ok_callback = function()
                                        resetAllSettings(touch_menu)
                                        UIManager:show(Notification:new{ text = _("设置已重置"), timeout = 2 })
                                    end,
                                })
                            end,
                        },
                    },
                },
                {
                    text = _("外观设置"),
                    sub_item_table = {
                        {
                            text = function() return _("控制中心图标") .. ": controlcenter" end,
                            close_on_click = true,
                            callback = function()
                                closeSettingsDialog()
                                showIconPicker(
                                    function(file_path)
                                        if file_path then
                                            local filename = file_path:match("([^/]+)$"):gsub("%.[^%.]+$", "")
                                            setString("qa_tab_icon", filename)
                                            askRestart()
                                        end
                                    end,
                                    nil,
                                    "file"
                                )
                            end,
                        },
                        {
                            text = _("系统图标替换"),
                            close_on_click = true,
                            callback = function()
                                closeSettingsDialog()
                                showIconPicker(nil, nil, nil, "system")
                            end,
                        },
                        {
                            text = _("UI字体切换"),
                            close_on_click = true,
                            callback = function()
                                closeSettingsDialog()
                                showUIFontSwitcher()
                            end,
                        },
                    },
                },
            },
        },
    }
    showMenu(root_menu_items, _("快捷中心"), nil, touch_menu, root_menu_items)
end

-- ============================================================
-- SlimSlider: 细轨滑块
-- ============================================================
local SlimSlider = Widget:extend{
    width = 200,
    height = Screen:scaleBySize(28),
    minimum = 0,
    maximum = 100,
    value = 0,
    show_parent = nil,
    enabled = true,
}

function SlimSlider:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function SlimSlider:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function SlimSlider:setValue(v)
    self.value = math.max(self.minimum, math.min(self.maximum, v or 0))
end

function SlimSlider:getValueFromPosition(pos)
    if not self.dimen or not pos then return nil end
    local rel_x = math.max(0, math.min(self.width, pos.x - self.dimen.x))
    local range = self.maximum - self.minimum
    if range <= 0 then return self.minimum end
    return self.minimum + (rel_x / self.width) * range
end

function SlimSlider:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local track_h = Screen:scaleBySize(2)
    local thumb_w = Screen:scaleBySize(3)
    local thumb_h = Screen:scaleBySize(14)
    local cy = y + math.floor(self.height / 2)
    local range = math.max(1, self.maximum - self.minimum)
    local pct = (self.value - self.minimum) / range
    local fill_w = math.max(0, math.min(self.width, math.floor(pct * self.width)))
    bb:paintRect(x, cy - math.floor(track_h / 2), self.width, track_h, Blitbuffer.COLOR_LIGHT_GRAY)
    if fill_w > 0 then
        bb:paintRect(x, cy - math.floor(track_h / 2), fill_w, track_h, Blitbuffer.COLOR_BLACK)
    end
    local tx = math.max(x, math.min(x + self.width - thumb_w, x + fill_w - math.floor(thumb_w / 2)))
    bb:paintRect(tx, cy - math.floor(thumb_h / 2), thumb_w, thumb_h, Blitbuffer.COLOR_BLACK)
end

-- ============================================================
-- 面板构建器
-- ============================================================
local function buildQSPanel(touch_menu)
    -- 延迟加载：避免顶层局部变量超过 Lua 的 200 槽上限（LUAI_MAXVARS）
    local ButtonProgressWidget = require("ui/widget/buttonprogresswidget")
    local ProgressWidget = require("ui/widget/progresswidget")
    local slots = getQASlots()
    local panel_w = touch_menu.item_width
    local padding = Screen:scaleBySize(28)
    local inner_w = panel_w - padding * 2
    local base_btn_size = Screen:scaleBySize(60)
    local button_scale = getButtonSizePct() / 100
    local btn_size = math.floor(base_btn_size * button_scale)
    local icon_size = math.floor(btn_size * 0.52)
    local label_fs = math.max(6, math.floor(15 * getLabelScale()))
    local label_face = Font:getFace("cfont", label_fs)
    local medium_face = Font:getFace("ffont")
    local shape = getShape()
    local is_bare = (shape == "bare")
    local border_sz = 1

    -- 滑块行小按钮工厂（前光/色温两处共用）
    local function makeSliderBtn(text, width, cb)
        return Button:new{
            text = text, width = width, show_parent = touch_menu.show_parent,
            callback = cb, bordersize = 0, background = nil, framebg = nil,
        }
    end
    -- 滑块按钮高度（惰性测量一次，避免每次构建面板都创建测量用 Button）
    local btn_h = nil
    local function sliderBtnHeight()
        if not btn_h then
            btn_h = math.max(30, makeSliderBtn("−", Screen:scaleBySize(40), function() end):getSize().h)
        end
        return btn_h
    end

    local function makeButton(action_id)
        local label = getLabelForAction(action_id)
        local icon_widget = getIconWidget(getIconForAction(action_id), icon_size)
        if not icon_widget then
            local chars = util.splitToChars(label)
            icon_widget = TextWidget:new{
                text = (chars and #chars > 0) and chars[1] or label,
                face = Font:getFace("cfont", math.floor(icon_size * 0.55)),
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
        end
        local corner_r = (shape == "round") and math.floor(btn_size / 2) or math.floor(btn_size / 4)
        local bg = getBg()
        local current_border, bg_color = 0, nil
        if not is_bare then
            current_border = (bg == "solid" or bg == "transparent") and border_sz or 0
            if bg == "flat" then bg_color = Blitbuffer.gray(0.08)
            elseif bg == "solid" then bg_color = Blitbuffer.COLOR_WHITE end
        end
        local btn_frame = FrameContainer:new{
            width = btn_size,
            height = btn_size,
            radius = corner_r,
            bordersize = current_border,
            color = current_border > 0 and Blitbuffer.gray(0.75) or nil,
            background = bg_color,
            padding = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = btn_size - current_border * 2, h = btn_size - current_border * 2 },
                icon_widget,
            },
        }
        local btn_wrapper = InputContainer:new{ dimen = Geom:new{ w = btn_size, h = btn_size } }
        btn_wrapper[1] = btn_frame
        local function applyPressFeedback(widget)
            local original_bg, original_color = widget.background, widget.color
            widget.background = Blitbuffer.gray(0.3)
            if widget.color then widget.color = Blitbuffer.gray(0.3) end
            UIManager:setDirty(touch_menu.show_parent, function() return "ui", widget.dimen end)
            UIManager:scheduleIn(0.1, function()
                widget.background = original_bg
                widget.color = original_color
                UIManager:setDirty(touch_menu.show_parent, function() return "ui", widget.dimen end)
            end)
        end
        local zones = {
            {
                id = "btn_tap_" .. action_id,
                ges = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges)
                    local d = btn_wrapper.dimen
                    local rel_x, rel_y = ges.pos.x - (d and d.x or 0), ges.pos.y - (d and d.y or 0)
                    if rel_x >= 0 and rel_x <= btn_size and rel_y >= 0 and rel_y <= btn_size then
                        applyPressFeedback(btn_frame)
                        if isInPlace(action_id) then
                            executeAction(action_id, { touch_menu = touch_menu })
                            touch_menu:updateItems()
                        else
                            UIManager:scheduleIn(0.05, function()
                                executeAction(action_id, { touch_menu = touch_menu })
                            end)
                        end
                        return true
                    end
                    return false
                end,
            },
        }
        if buttonHoldEdit() then
            zones[#zones + 1] = {
                id = "btn_hold_" .. action_id,
                ges = "hold",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges)
                    local d = btn_wrapper.dimen
                    local rel_x, rel_y = ges.pos.x - (d and d.x or 0), ges.pos.y - (d and d.y or 0)
                    if rel_x >= 0 and rel_x <= btn_size and rel_y >= 0 and rel_y <= btn_size then
                        if ACTION_ORDER then
                            for _i, builtin_id in ipairs(ACTION_ORDER) do
                                if builtin_id == action_id then
                                    showEditActionDialog(action_id, function() refreshQuickPanel(touch_menu) end)
                                    return true
                                end
                            end
                        end
                        showCustomQADialog(action_id, function() refreshQuickPanel(touch_menu) end)
                        return true
                    end
                    return false
                end,
            }
        end
        btn_wrapper:registerTouchZones(zones)
        local vg = VerticalGroup:new{ align = "center", btn_wrapper }
        if showLabels() then
            local lbl_w = btn_size + Screen:scaleBySize(6)
            vg[#vg + 1] = VerticalSpan:new{ width = Screen:scaleBySize(2) }
            vg[#vg + 1] = CenterContainer:new{
                dimen = Geom:new{ w = lbl_w, h = label_face.size },
                TextWidget:new{
                    text = label,
                    face = label_face,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    max_width = lbl_w,
                    width = lbl_w,
                    truncate_with_ellipsis = true,
                },
            }
        end
        return vg, btn_frame
    end

    local current_view = "filemanager"
    if getBool("qa_context_filter") then
        local reader = require("apps/reader/readerui").instance
        current_view = (reader and not reader.tearing_down) and "reader" or "filemanager"
    end
    local visible_slots = {}
    for _i, id in ipairs(slots) do
        if getAction(id) and isActionVisible(id, current_view) then visible_slots[#visible_slots + 1] = id end
    end
    local n = #visible_slots
    local fixed_gap = Screen:scaleBySize(8)
    -- 布局：固定网格（行×列）或自适应换行
    local rows = {}
    if getBool("qa_layout_enabled") then
        local cols = math.max(1, getNumber("qa_layout_cols"))
        local max_rows = math.max(1, getNumber("qa_layout_rows"))
        local grid_gap = (cols > 1) and math.max(0, math.floor((inner_w - cols * btn_size) / (cols - 1))) or 0
        for r = 1, max_rows do
            local row_slots = {}
            for c = 1, cols do
                local idx = (r - 1) * cols + c
                if idx <= n then row_slots[#row_slots + 1] = visible_slots[idx] end
            end
            if #row_slots > 0 then rows[#rows + 1] = { slots = row_slots, cols = cols, gap = grid_gap } end
        end
    else
        local max_per_row = math.max(1, math.floor((inner_w + fixed_gap) / (btn_size + fixed_gap)))
        for i = 1, n, max_per_row do
            local row_slots = {}
            for j = i, math.min(i + max_per_row - 1, n) do row_slots[#row_slots + 1] = visible_slots[j] end
            rows[#rows + 1] = {
                slots = row_slots,
                cols = #row_slots,
                gap = (#row_slots > 1) and math.max(0, math.floor((inner_w - #row_slots * btn_size) / (#row_slots - 1))) or 0,
            }
        end
    end
    local rows_vg = VerticalGroup:new{ align = "center" }
    local row_gap = Screen:scaleBySize(8)
    local refs = { buttons = {} }
    if n > 0 then
        for ri, row in ipairs(rows) do
            local row_slots, row_n, gap = row.slots, row.cols, row.gap
            local hg = HorizontalGroup:new{ align = "center" }
            for i = 1, row_n do
                local action_id = row_slots[i]
                if action_id then
                    local vg, btn_frame = makeButton(action_id)
                    local _aid = action_id
                    refs.buttons[#refs.buttons + 1] = {
                        widget = btn_frame,
                        callback = function()
                            if isInPlace(_aid) then
                                executeAction(_aid, { touch_menu = touch_menu })
                                touch_menu:updateItems()
                                return true
                            end
                            UIManager:scheduleIn(0, function() executeAction(_aid, { touch_menu = touch_menu }) end)
                            return false
                        end,
                    }
                    hg[#hg + 1] = vg
                else
                    hg[#hg + 1] = HorizontalSpan:new{ width = btn_size } -- 空位占位，保持对齐
                end
                if i < row_n then hg[#hg + 1] = HorizontalSpan:new{ width = gap } end
            end
            rows_vg[#rows_vg + 1] = hg
            if ri < #rows then rows_vg[#rows_vg + 1] = VerticalSpan:new{ width = row_gap } end
        end
    else
        rows_vg[#rows_vg + 1] = TextWidget:new{
            text = _("没有配置动作"),
            face = Font:getFace("cfont"),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
    end
    local panel = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = Screen:scaleBySize(20) },
        CenterContainer:new{ dimen = Geom:new{ w = panel_w, h = rows_vg:getSize().h }, rows_vg },
        VerticalSpan:new{ width = Screen:scaleBySize(16) },
    }
    if showFrontlight() and Device:hasFrontlight() then
        local powerd = Device:getPowerDevice()
        local fl = {
            min = powerd.fl_min,
            max = powerd.fl_max,
            cur = powerd:frontlightIntensity(),
        }
        local small_btn_w = Screen:scaleBySize(40)
        local max_btn_w = Screen:scaleBySize(50)
        local slider_gap = Screen:scaleBySize(4)
        local slider_width = inner_w - 2 * small_btn_w - max_btn_w - 3 * slider_gap
        local fl_label = nil
        if showSliderValue() then
            fl_label = TextWidget:new{ text = _("前光") .. ": " .. tostring(fl.cur), face = medium_face, max_width = inner_w }
        end
        local btn_height = sliderBtnHeight()
        local fl_slider, fl_progress, fl_hit_test
        if getSliderStyle() == "segment" then
            -- simpleui 风格：进度条 + 刻度
            local fl_steps = fl.max - fl.min + 1
            local fl_stride = math.ceil(fl_steps * (1 / 25))
            local fl_num_ticks = math.ceil(fl_steps / fl_stride)
            if (fl_num_ticks - 1) * fl_stride < fl.max - fl.min then fl_num_ticks = fl_num_ticks + 1 end
            fl_num_ticks = math.min(fl_num_ticks, fl_steps)
            local fl_ticks = {}
            for i = 1, fl_num_ticks - 2 do fl_ticks[#fl_ticks + 1] = i * fl_stride end
            fl_progress = ProgressWidget:new{
                width = slider_width,
                height = btn_height,
                percentage = (fl.max > 0) and (fl.cur / fl.max) or 0,
                ticks = fl_ticks,
                tick_width = Screen:scaleBySize(0.5),
                last = fl.max,
            }
            fl_hit_test = function(pos)
                if not (fl_progress.dimen and pos:intersectWith(fl_progress.dimen)) then return nil end
                local perc = fl_progress:getPercentageFromPosition(pos)
                if not perc then return nil end
                return math.floor(perc * fl.max + 0.5)
            end
        else
            fl_slider = SlimSlider:new{
                width = slider_width,
                height = btn_height,
                minimum = fl.min,
                maximum = fl.max,
                value = fl.cur,
                show_parent = touch_menu.show_parent,
                enabled = true,
            }
            fl_hit_test = function(pos)
                if not (fl_slider.dimen and pos:intersectWith(fl_slider.dimen)) then return nil end
                local v = fl_slider:getValueFromPosition(pos)
                if not v then return nil end
                return math.floor(v + 0.5)
            end
        end
        local fl_saved_brightness = (fl.cur > fl.min) and fl.cur or fl.max
        local fl_toggle_btn
        local function updateFLWidgets()
            if fl_slider then fl_slider:setValue(fl.cur) end
            if fl_progress then fl_progress:setPercentage(fl.cur / fl.max) end
            if fl_label then fl_label:setText(_("前光") .. ": " .. tostring(fl.cur)) end
            if fl_toggle_btn then fl_toggle_btn:setText(fl.cur > fl.min and "ON" or "OFF") end
            UIManager:setDirty(touch_menu.show_parent, "ui")
        end
        local function setBrightness(intensity)
            if intensity ~= fl.min and intensity == fl.cur then return end
            intensity = math.max(fl.min, math.min(fl.max, intensity))
            powerd:setIntensity(intensity)
            fl.cur = powerd:frontlightIntensity()
            updateFLWidgets()
        end
        local fl_minus = makeSliderBtn("−", small_btn_w, function() setBrightness(fl.cur - 1) end)
        local fl_plus = makeSliderBtn("＋", small_btn_w, function() setBrightness(fl.cur + 1) end)
        fl_toggle_btn = makeSliderBtn(fl.cur > fl.min and "ON" or "OFF", max_btn_w, function()
            if fl.cur > fl.min then
                fl_saved_brightness = fl.cur
                setBrightness(fl.min)
            else
                setBrightness(fl_saved_brightness)
            end
        end)
        local fl_group = VerticalGroup:new{ align = "center" }
        if fl_label then
            fl_group[#fl_group + 1] = fl_label
            fl_group[#fl_group + 1] = VerticalSpan:new{ width = Screen:scaleBySize(6) }
        end
        fl_group[#fl_group + 1] = HorizontalGroup:new{
            align = "center",
            fl_minus,
            HorizontalSpan:new{ width = slider_gap },
            fl_slider or fl_progress,
            HorizontalSpan:new{ width = slider_gap },
            fl_plus,
            HorizontalSpan:new{ width = slider_gap },
            fl_toggle_btn,
        }
        panel[#panel + 1] = VerticalSpan:new{ width = Screen:scaleBySize(10) }
        panel[#panel + 1] = CenterContainer:new{ dimen = Geom:new{ w = panel_w, h = fl_group:getSize().h }, fl_group }
        refs.fl_hit_test = fl_hit_test
        refs.setBrightness = setBrightness
    end
    if showWarmth() and Device:hasNaturalLight() then
        local powerd = Device:getPowerDevice()
        local nl = {
            min = powerd.fl_warmth_min,
            max = powerd.fl_warmth_max,
            cur = powerd:toNativeWarmth(powerd:frontlightWarmth()),
        }
        local small_btn_w = Screen:scaleBySize(40)
        local max_btn_w = Screen:scaleBySize(50)
        local slider_gap = Screen:scaleBySize(4)
        local warmth_slider_w = inner_w - 2 * small_btn_w - max_btn_w - 3 * slider_gap
        local nl_label = nil
        if showSliderValue() then
            nl_label = TextWidget:new{ text = _("色温") .. ": " .. tostring(nl.cur), face = medium_face, max_width = inner_w }
        end
        local btn_height2 = sliderBtnHeight()
        local nl_slider, nl_progress, nl_stride, setWarmth
        if getSliderStyle() == "segment" then
            -- simpleui 风格：分段按钮（自身处理点击）
            local nl_steps = nl.max - nl.min + 1
            nl_stride = math.ceil(nl_steps * (1 / 25))
            local nl_num_btns = math.ceil(nl_steps / nl_stride)
            if (nl_num_btns - 1) * nl_stride < nl.max - nl.min then nl_num_btns = nl_num_btns + 1 end
            nl_num_btns = math.min(nl_num_btns, nl_steps)
            nl_progress = ButtonProgressWidget:new{
                width = warmth_slider_w,
                height = btn_height2,
                font_size = 20,
                padding = 0,
                thin_grey_style = false,
                num_buttons = nl_num_btns - 1,
                position = math.floor(nl.cur / nl_stride),
                default_position = math.floor(nl.cur / nl_stride),
                show_parent = touch_menu.show_parent,
                enabled = true,
                callback = function(i)
                    setWarmth(math.min(math.floor(i * nl_stride + 0.5), nl.max))
                end,
            }
        else
            nl_slider = SlimSlider:new{
                width = warmth_slider_w,
                height = btn_height2,
                minimum = nl.min,
                maximum = nl.max,
                value = nl.cur,
                show_parent = touch_menu.show_parent,
                enabled = true,
            }
        end
        -- NOTE: setWarmth 必须先声明（前向引用），否则回调闭包会绑定到全局 nil 而崩溃
        setWarmth = function(warmth)
            if warmth == nl.cur then return end
            warmth = math.max(nl.min, math.min(nl.max, warmth))
            powerd:setWarmth(powerd:fromNativeWarmth(warmth))
            nl.cur = powerd:toNativeWarmth(powerd:frontlightWarmth())
            if nl_slider then
                nl_slider:setValue(nl.cur)
            elseif nl_progress then
                nl_progress:setPosition(math.floor(nl.cur / nl_stride), nl_progress.default_position)
            end
            if nl_label then nl_label:setText(_("色温") .. ": " .. tostring(nl.cur)) end
            UIManager:setDirty(touch_menu.show_parent, "ui")
        end
        local warmth_group = VerticalGroup:new{ align = "center" }
        warmth_group[#warmth_group + 1] = VerticalSpan:new{ width = Screen:scaleBySize(12) }
        if nl_label then
            warmth_group[#warmth_group + 1] = nl_label
            warmth_group[#warmth_group + 1] = VerticalSpan:new{ width = Screen:scaleBySize(6) }
        end
        warmth_group[#warmth_group + 1] = HorizontalGroup:new{
            align = "center",
            makeSliderBtn("−", small_btn_w, function() setWarmth(nl.cur - 1) end),
            HorizontalSpan:new{ width = slider_gap },
            nl_slider or nl_progress,
            HorizontalSpan:new{ width = slider_gap },
            makeSliderBtn("＋", small_btn_w, function() setWarmth(nl.cur + 1) end),
            HorizontalSpan:new{ width = slider_gap },
            makeSliderBtn(_("Max"), max_btn_w, function() setWarmth(nl.max) end),
        }
        panel[#panel + 1] = CenterContainer:new{ dimen = Geom:new{ w = panel_w, h = warmth_group:getSize().h }, warmth_group }
        refs.nl_slider = nl_slider
        refs.setWarmth = setWarmth
    end
    panel[#panel + 1] = VerticalSpan:new{ width = Screen:scaleBySize(14) }
    local panel_h = panel:getSize().h
    local ic = InputContainer:new{ dimen = Geom:new{ w = panel_w, h = panel_h }, [1] = panel }
    ic.ges_events = {
        HoldPanel = { GestureRange:new{ ges = "hold", range = function() return ic.dimen end } },
    }
    function ic:onHoldPanel()
        if not settingsOnHold() then return false end
        showSettingsMenu(touch_menu)
        return true
    end
    return ic, refs
end

-- ============================================================
-- TouchMenu 补丁（面板 + 滑块/按钮手势）
-- ============================================================
local TouchMenu = require("ui/widget/touchmenu")
local FocusManager = require("ui/widget/focusmanager")
local _orig_updateItems = TouchMenu.updateItems
local _orig_onTap = TouchMenu.onTapCloseAllMenus
local _orig_onSwipe = TouchMenu.onSwipe
local _orig_onPan = TouchMenu.onPan

-- 面板滑动手势共用命中逻辑（with_buttons: 是否处理按钮点击）
local function _qsHandleTap(self, ges_ev, with_buttons)
    local refs = self._qs_refs
    if not (refs and self.item_table and self.item_table._qs_panel) then return false end
    if refs.fl_hit_test then
        local new_val = refs.fl_hit_test(ges_ev.pos)
        if new_val and refs.setBrightness then
            refs.setBrightness(new_val)
            return true
        end
    end
    if refs.nl_slider and refs.nl_slider.dimen and ges_ev.pos:intersectWith(refs.nl_slider.dimen) then
        local new_val = refs.nl_slider:getValueFromPosition(ges_ev.pos)
        if new_val and refs.setWarmth then
            refs.setWarmth(math.floor(new_val + 0.5))
            return true
        end
    end
    if with_buttons then
        for _i, ref in ipairs(refs.buttons or {}) do
            if ref.widget.dimen and ges_ev.pos:intersectWith(ref.widget.dimen) then
                local stay_open = ref.callback()
                if stay_open then return true end
                self:onClose()
                return true
            end
        end
    end
    return false
end

function TouchMenu:updateItems(target_page, target_item_id)
    if not self.item_table or not self.item_table._qs_panel then
        self._qs_refs = nil
        return _orig_updateItems(self, target_page, target_item_id)
    end
    self.page = 1
    self.page_num = 1
    self.item_group:clear()
    self.layout = {}
    self.item_group[#self.item_group + 1] = self.bar
    self.layout[#self.layout + 1] = self.bar.icon_widgets
    local panel, refs = buildQSPanel(self)
    self._qs_refs = refs
    self.item_group[#self.item_group + 1] = panel
    self.item_group[#self.item_group + 1] = self.footer_top_margin
    self.item_group[#self.item_group + 1] = self.footer
    self.page_info_text:setText("")
    self.page_info_left_chev:showHide(false)
    self.page_info_right_chev:showHide(false)
    if self.page_info_left_chev then self.page_info_left_chev.hold_callback = nil end
    if self.page_info_right_chev then self.page_info_right_chev.hold_callback = nil end
    local G = rawget(_G, "G_reader_settings")
    local time_txt = datetime.secondsToHour(os.time(), G and G:isTrue("twelve_hour_clock") or false)
    if Device:hasBattery() then
        local powerd = Device:getPowerDevice()
        local lvl = powerd:getCapacity()
        local sym = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), lvl)
        time_txt = BD.wrap(time_txt) .. " " .. BD.wrap("⌁") .. BD.wrap(sym) .. BD.wrap(lvl .. "%")
    end
    self.time_info:setText(time_txt)
    local old_dimen = self.dimen:copy()
    self.dimen.w = self.width
    self.dimen.h = self.item_group:getSize().h + self.bordersize * 2 + self.padding
    self:moveFocusTo(self.cur_tab, 1, FocusManager.NOT_FOCUS)
    local keep_bg = old_dimen and self.dimen.h >= old_dimen.h
    UIManager:setDirty(
        (self.is_fresh or keep_bg) and self.show_parent or "all",
        function()
            local refresh_dimen = old_dimen and old_dimen:combine(self.dimen) or self.dimen
            local refresh_type = self.is_fresh and "flashui" or "ui"
            self.is_fresh = false
            return refresh_type, refresh_dimen
        end)
end

function TouchMenu:onTapCloseAllMenus(arg, ges_ev)
    if _qsHandleTap(self, ges_ev, true) then return true end
    return _orig_onTap(self, arg, ges_ev)
end

function TouchMenu:onSwipe(arg, ges_ev)
    if _qsHandleTap(self, ges_ev, true) then return true end
    if _orig_onSwipe then return _orig_onSwipe(self, arg, ges_ev) end
end

function TouchMenu:onPan(arg, ges_ev)
    if _qsHandleTap(self, ges_ev, false) then return true end
    if _orig_onPan then return _orig_onPan(self, arg, ges_ev) end
end

-- ============================================================
-- 优先显示快捷操作面板（关闭菜单时回到第 1 个标签页）
-- ============================================================
-- 前向声明：injectPanelTab 定义在本函数之后
local injectPanelTab
local function patchFileManagerMenu()
    local FMMenu = require("apps/filemanager/filemanagermenu")
    if FMMenu._qs_patched then return end
    FMMenu._qs_patched = true
    local orig_onCloseFileManagerMenu = FMMenu.onCloseFileManagerMenu
    FMMenu.onCloseFileManagerMenu = function(self)
        if self.menu_container and self.menu_container[1] then self.menu_container[1].last_index = 1 end
        return orig_onCloseFileManagerMenu(self)
    end
    local orig_sut = FMMenu.setUpdateItemTable
    FMMenu.setUpdateItemTable = function(m_self)
        local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")
        if FileManagerMenuOrder.tools then
            local already = false
            for _i, v in ipairs(FileManagerMenuOrder.tools) do
                if v == "qa_settings" then already = true; break end
            end
            if not already then
                table.insert(FileManagerMenuOrder.tools, 1, "----------------------------")
                table.insert(FileManagerMenuOrder.tools, 2, "qa_settings")
            end
        end
        if not m_self.menu_items then m_self.menu_items = {} end
        m_self.menu_items.qa_settings = {
            text = _("快捷中心"),
            callback = function() showSettingsMenu() end,
        }
        orig_sut(m_self)
        injectPanelTab(m_self)
    end
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.menu and fm.menu.setUpdateItemTable then fm.menu:setUpdateItemTable() end
end

local function patchReaderMenu()
    local RMenu = require("apps/reader/modules/readermenu")
    if RMenu._qs_patched then return end
    RMenu._qs_patched = true
    local orig_onCloseReaderMenu = RMenu.onCloseReaderMenu
    RMenu.onCloseReaderMenu = function(self)
        if self.menu_container and self.menu_container[1] then
            self.menu_container[1].last_index = 1
            self.last_tab_index = 1
        end
        return orig_onCloseReaderMenu(self)
    end
    local orig_sut = RMenu.setUpdateItemTable
    RMenu.setUpdateItemTable = function(m_self)
        local ReaderMenuOrder = require("ui/elements/reader_menu_order")
        if ReaderMenuOrder.tools then
            local already = false
            for _i, v in ipairs(ReaderMenuOrder.tools) do
                if v == "qa_settings" then already = true; break end
            end
            if not already then table.insert(ReaderMenuOrder.tools, "qa_settings") end
        end
        if not m_self.menu_items then m_self.menu_items = {} end
        m_self.menu_items.qa_settings = {
            text = _("快捷中心"),
            callback = function() showSettingsMenu() end,
        }
        orig_sut(m_self)
        injectPanelTab(m_self)
    end
    local orig_show_menu = RMenu.onShowMenu
    RMenu.onShowMenu = function(m_self, ...)
        if m_self.tab_item_table then
            local tabs = m_self.tab_item_table
            for i, tab in ipairs(tabs) do
                if tab.id == "filemanager" or (tab.text and tab.text == _("File manager")) then
                    if i < #tabs then
                        table.remove(tabs, i)
                        table.insert(tabs, tab)
                    end
                    break
                end
            end
            injectPanelTab(m_self)
        end
        return orig_show_menu(m_self, ...)
    end
    local readerui = require("apps/reader/readerui").instance
    if readerui and readerui.menu then
        readerui.menu:onCloseMenu()
        readerui.menu:onShowMenu()
    end
end

-- ============================================================
-- 注入标签页到菜单
-- ============================================================
local QS_PANEL_TAB = {
    icon = getString("qa_tab_icon"),
    remember = false,
    _qs_panel = true,
}

injectPanelTab = function(m_self)
    if not isQAEnabled() then return end
    if type(m_self.tab_item_table) ~= "table" then return end
    for _i, tab in ipairs(m_self.tab_item_table) do
        if tab._qs_panel then return end
    end
    table.insert(m_self.tab_item_table, 1, QS_PANEL_TAB)
end

-- ============================================================
-- 补丁 IconWidget，支持用户图标覆盖
-- ============================================================
local function patchIconWidget()
    local IconWidget = require("ui/widget/iconwidget")
    if IconWidget._qa_patched then return end
    IconWidget._qa_patched = true
    local orig_init = IconWidget.init
    function IconWidget:init()
        if self.icon then
            local overrides = getTable("qa_icon_overrides")
            if overrides and overrides[self.icon] then
                local user_icon = overrides[self.icon]
                local full_path = getIconsDir() .. "/" .. user_icon
                if lfs.attributes(full_path, "mode") == "file" then
                    self.file = full_path
                    self.icon = nil
                elseif lfs.attributes(user_icon, "mode") == "file" then
                    self.file = user_icon
                    self.icon = nil
                end
            end
        end
        return orig_init(self)
    end
end

-- ============================================================
-- 手势注册（三个 Dispatcher 动作，幂等注册）
-- ============================================================
-- 全局函数（顶层局部变量已达 Lua 200 上限）
-- 动作定义只构建一次，避免每次 Dispatcher:execute 都重建 3 个表
QA_DISPATCHER_ACTIONS = {
    quick_actions_panel = {
        category = "none",
        event = "QuickActionsPanel",
        title = _("QuickCenter：控制中心面板"),
        general = true,
    },
    qa_settings_action = {
        category = "none",
        event = "QuickActionsSettings",
        title = _("QuickCenter：快捷中心设置"),
        general = true,
    },
    qa_shortcuts_menu = {
        category = "none",
        event = "QuickActionsShortcuts",
        title = _("QuickCenter：快捷操作菜单"),
        general = true,
    },
}

function registerQAGestureActions()
    for name, def in pairs(QA_DISPATCHER_ACTIONS) do
        Dispatcher:registerAction(name, def)
    end
end

local function registerGestures()
    registerQAGestureActions()
    -- 兜底：手势执行依赖 Dispatcher.settingsList 里已注册动作，若因版本/时机缺失会静默失效。
    -- 每次 Dispatcher:execute 前确保动作已注册（幂等，开销可忽略）。
    if not Dispatcher._qa_execute_patched then
        Dispatcher._qa_execute_patched = true
        local orig_dispatcher_execute = Dispatcher.execute
        function Dispatcher:execute(settings, exec_props)
            registerQAGestureActions()
            return orig_dispatcher_execute(self, settings, exec_props)
        end
    end
    local function addGestures(mod)
        if not mod or mod._qs_gesture_added then return end
        function mod:onQuickActionsShortcuts()
            showMenu(getShortcutActionItems(), _("快捷方式"), nil, nil, nil, true)
            return true
        end
        function mod:onQuickActionsPanel()
            local menu = self.menu
            if menu then
                if not menu.menu_container or not menu.menu_container[1] then menu:onShowMenu() end
                local target_menu = menu.menu_container and menu.menu_container[1]
                if target_menu then
                    for i, tab in ipairs(target_menu.tab_item_table or {}) do
                        if tab._qs_panel then
                            target_menu:switchMenuTab(i)
                            break
                        end
                    end
                end
            end
            return true
        end
        function mod:onQuickActionsSettings()
            showSettingsMenu()
            return true
        end
        mod._qs_gesture_added = true
    end
    addGestures(require("apps/filemanager/filemanager"))
    addGestures(require("apps/reader/readerui"))
end

-- ============================================================
-- 退出/重启前刷新设置
-- 修复：KOReader 的 UIManager:quit 直接丢弃窗口栈，不广播 FlushSettings，
-- 导致手势等 LuaSettings 插件设置不落盘，重启后丢失。
-- ============================================================
function patchUIManagerQuit()
    if UIManager._qa_quit_patched then return end
    UIManager._qa_quit_patched = true
    local orig_quit = UIManager.quit
    function UIManager:quit(exit_code, implicit)
        self:flushSettings()
        return orig_quit(self, exit_code, implicit)
    end
end

local function initDefaultDedicatedLists()
    if getBool("qa_filter_initialized") then return end
    setBool("qa_filter_initialized", true)
end

-- ============================================================
-- 初始化
-- ============================================================
local function install()
    logger.info("[QuickActions] 安装中...")
    patchFileManagerMenu()
    patchReaderMenu()
    registerGestures()
    patchUIManagerQuit()
    initDefaultDedicatedLists()
    patchIconWidget()
    logger.info("[QuickActions] 安装完成，配置路径:", getConfigPath())
end

install()

logger.info("[QuickActions] 加载完成")
