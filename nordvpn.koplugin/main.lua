local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local https = require("ssl.https")
local json = require("json")
local ltn12 = require("ltn12")
local mime = require("mime")
local socket = require("socket")
local tunnel = require("nordvpn_tunnel")

local PROXY_PORT = 25345
local PROXY = "http://127.0.0.1:" .. PROXY_PORT
local API = "https://api.nordvpn.com/v1/"
local WP = "https://github.com/pufferffish/wireproxy/releases/latest/download/"

local Nord = WidgetContainer:extend{ name = "nordvpn" }

local function sh(fmt, ...) return os.execute(string.format(fmt, ...)) end

local function request(url, token, sink)
    local body = {}
    local _, code = https.request{
        url = url,
        headers = token and { Authorization = "Basic " .. mime.b64("token:" .. token) } or nil,
        sink = sink or ltn12.sink.table(body),
    }
    if code ~= 200 then return nil, tostring(code) end
    return table.concat(body)
end

local function api(path, token)
    local body, err = request(API .. path, token)
    if not body then return nil, err end
    local ok, data = pcall(json.decode, body)
    if not ok then return nil, "bad json" end
    return data
end

function Nord:init()
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    self.dir = src:gsub("/main%.lua$", "")
    self.bin = self.dir .. "/bin"
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/nordvpn.lua")
    self.ui.menu:registerToMainMenu(self)
    tunnel.install()
    self.on = self:isRunning()
    if self.on then tunnel.port = PROXY_PORT end
end

-- Menu state is a flag, not a live pgrep: killall is async, so pgrep right after a stop still sees the process.
function Nord:setOn(on)
    self.on = on
    if self.tm then self.tm:updateItems() end
end

function Nord:say(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

function Nord:isRunning()
    return sh("pgrep wireproxy >/dev/null 2>&1") == 0
end

function Nord:ensureBinary()
    local path = self.bin .. "/wireproxy"
    local f = io.open(path, "r")
    if f then f:close() return true end
    local p = io.popen("uname -m")
    local arch = (p:read("*a") or ""):match("a?arch64") and "arm64" or "arm"
    p:close()
    local name = "wireproxy_linux_" .. arch .. ".tar.gz"
    local tgz = self.bin .. "/" .. name
    sh("mkdir -p '%s'", self.bin)
    local out = io.open(tgz, "wb")
    if not out then return nil, "cannot write " .. tgz end
    local ok, err = request(WP .. name, nil, ltn12.sink.file(out))
    if not ok then
        -- sink.file closes the handle on success; on failure drop the partial file
        os.remove(tgz)
        return nil, "download failed " .. tostring(err)
    end
    local sums = request(WP .. "checksums.txt")
    local want = sums and sums:match("(%x+)%s+" .. name:gsub("%p", "%%%0"))
    local h = io.popen(string.format("sha256sum '%s'", tgz))
    local got = (h:read("*a") or ""):match("^(%x+)")
    h:close()
    if not want or want ~= got then os.remove(tgz) return nil, "checksum mismatch" end
    sh("cd '%s' && tar xzf '%s' wireproxy && chmod +x wireproxy && rm -f '%s'", self.bin, name, name)
    return true
end

function Nord:writeConf()
    local token = self.settings:readSetting("token")
    local country = self.settings:readSetting("country_id")
    if not token then return nil, "no token" end
    if not country then return nil, "no country" end
    local key = self.settings:readSetting("private_key")
    if not key then
        local c, err = api("users/services/credentials", token)
        key = c and c.nordlynx_private_key
        if not key then return nil, "token rejected " .. tostring(err) end
        self.settings:saveSetting("private_key", key):flush()
    end
    local s, err = api("servers/recommendations?filters%5Bcountry_id%5D=" .. country
        .. "&filters%5Bservers_technologies%5D%5Bidentifier%5D=wireguard_udp&limit=1")
    s = s and s[1]
    if not s then return nil, "no server " .. tostring(err) end
    local pub
    for _i, t in ipairs(s.technologies or {}) do
        if t.identifier == "wireguard_udp" then pub = t.metadata[1].value end
    end
    -- values go into a config file, so refuse anything that is not an IP and a base64 key
    if not (pub and pub:match("^[%w+/]+=*$") and s.station:match("^[%d.]+$")) then
        return nil, "unexpected server data"
    end
    local f = io.open(self.bin .. "/wireproxy.conf", "w")
    f:write(string.format([[
[Interface]
PrivateKey = %s
Address = 10.5.0.2/32
DNS = 103.86.96.100

[Peer]
PublicKey = %s
Endpoint = %s:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

[http]
BindAddress = 127.0.0.1:%d
]], key, pub, s.station, PROXY_PORT))
    f:close()
    sh("chmod 600 '%s/wireproxy.conf'", self.bin)
    return s.hostname
end

-- Optional nordvpn.conf next to main.lua: "token = ..." and "country = Germany" (name or code).
-- It wins over the menu choices. Without it, the menu dialogs work as before.
function Nord:applyConf()
    local f = io.open(self.dir .. "/nordvpn.conf", "r")
    if not f then return end
    local c = {}
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k and v ~= "" then c[k] = v end
    end
    f:close()
    if c.token and c.token ~= self.settings:readSetting("token") then
        self.settings:saveSetting("token", c.token):delSetting("private_key")
    end
    if c.country and c.country:lower() ~= (self.settings:readSetting("country_name") or ""):lower() then
        for _i, x in ipairs(api("servers/countries") or {}) do
            if x.name:lower() == c.country:lower() or x.code:lower() == c.country:lower() then
                self.settings:saveSetting("country_id", x.id):saveSetting("country_name", x.name)
            end
        end
    end
    self.settings:flush()
end

-- End-to-end probe: ask wireproxy's HTTP proxy to CONNECT to Nord's API through the tunnel.
-- It also queues traffic, which makes WireGuard retry a lost handshake.
local function tunnelUp()
    local c = socket.tcp()
    c:settimeout(3)
    if not c:connect("127.0.0.1", PROXY_PORT) then c:close() return false end
    c:send("CONNECT api.nordvpn.com:443 HTTP/1.1\r\nHost: api.nordvpn.com:443\r\n\r\n")
    local line = c:receive("*l")
    c:close()
    return line ~= nil and line:find(" 200") ~= nil
end

-- The proxy is set only once the tunnel passes traffic. Setting it earlier cuts all KOReader traffic.
function Nord:waitTunnel(host, tries)
    if tunnelUp() then
        NetworkMgr:setHTTPProxy(PROXY)
        tunnel.port = PROXY_PORT
        self.busy = false
        self:setOn(true)
        self:say(_("NordVPN on: ") .. host, 3)
    elseif tries <= 0 then
        sh("pkill wireproxy 2>/dev/null || killall wireproxy 2>/dev/null")
        self.busy = false
        self:say(_("NordVPN failed: no tunnel. See bin/wireproxy.log"))
    else
        UIManager:scheduleIn(2, function() self:waitTunnel(host, tries - 1) end)
    end
end

function Nord:fail(msg)
    self.busy = false
    if msg then self:say(_("NordVPN failed: ") .. tostring(msg)) end
end

function Nord:connect()
    if self.busy then return end
    self.busy = true
    tunnel.port = nil -- our own API calls must not go through a tunnel that is about to restart
    self:say(_("Connecting to NordVPN..."), 2)
    NetworkMgr:runWhenOnline(function()
        UIManager:scheduleIn(0.2, function()
            self:applyConf()
            if not self.settings:readSetting("token") then
                self:fail()
                return self:askToken(function() self:connect() end)
            end
            if not self.settings:readSetting("country_id") then
                self:fail()
                return self:pickCountry(function() self:connect() end)
            end
            local ok, err = self:ensureBinary()
            local host
            if ok then host, err = self:writeConf() end
            if not host then return self:fail(err) end
            sh("pkill wireproxy 2>/dev/null || killall wireproxy 2>/dev/null; sleep 1") -- a stale instance would hold the port
            sh("cd '%s' && (nohup ./wireproxy -c wireproxy.conf > wireproxy.log 2>&1 &)", self.bin)
            self:waitTunnel(host, 20)
        end)
    end)
end

function Nord:disconnect()
    sh("pkill wireproxy 2>/dev/null || killall wireproxy 2>/dev/null")
    tunnel.port = nil
    NetworkMgr:setHTTPProxy(nil) -- ponytail: clears, does not restore a proxy set before
    self:setOn(false)
    self:say(_("NordVPN off"), 2)
end

function Nord:askToken(then_do)
    local dlg
    dlg = InputDialog:new{
        title = _("NordVPN access token"),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local t = dlg:getInputText():gsub("%s", "")
                UIManager:close(dlg)
                if t == "" then return end
                self.settings:saveSetting("token", t):delSetting("private_key"):flush()
                if then_do then then_do() end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function Nord:pickCountry(then_do)
    NetworkMgr:runWhenOnline(function()
        local list, err = api("servers/countries")
        if not list then return self:say(_("Country list failed: ") .. tostring(err)) end
        table.sort(list, function(a, b) return a.name < b.name end)
        local menu
        local items = {}
        for _i, c in ipairs(list) do
            items[#items + 1] = { text = c.name, callback = function()
                UIManager:close(menu)
                self.settings:saveSetting("country_id", c.id):saveSetting("country_name", c.name):flush()
                if then_do then then_do() end
            end }
        end
        menu = Menu:new{
            title = _("Country"), item_table = items,
            width = Screen:getWidth(), height = Screen:getHeight(),
            covers_fullscreen = true, is_borderless = true, is_popout = false,
            close_callback = function() UIManager:close(menu) end,
        }
        UIManager:show(menu)
    end)
end

function Nord:addToMainMenu(items)
    items.nordvpn = {
        text = _("NordVPN"),
        sorting_hint = "network",
        sub_item_table = {
            { text = _("Connect"),
              checked_func = function() return self.on end,
              keep_menu_open = true,
              callback = function(tm)
                  self.tm = tm
                  if self.on then self:disconnect() else self:connect() end
              end },
            { text_func = function()
                  return _("Country: ") .. (self.settings:readSetting("country_name") or _("not set"))
              end,
              keep_menu_open = true,
              callback = function() self:pickCountry() end },
            { text = _("Access token"), keep_menu_open = true, callback = function() self:askToken() end },
        },
    }
end

return Nord
