-- KOReader's HTTP proxy setting only covers plain HTTP. LuaSec refuses to run when http.PROXY is set,
-- and socket.http then sends "GET https://..." in clear text, so HTTPS breaks (Wikipedia, OPDS, updates).
-- While M.port is set, https requests go through a CONNECT tunnel to the proxy on that port instead.
local http = require("socket.http")
local https = require("ssl.https")
local socket = require("socket")

local M = { port = nil }
local busy = false

local function connectViaProxy(orig, port)
    return function(self, host, p)
        local ok, err = orig(self, "127.0.0.1", port)
        if not ok then return nil, err end
        self:send(string.format("CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\n\r\n", host, p, host, p))
        local line = self:receive("*l")
        if not (line and line:find(" 200")) then return nil, line or "proxy closed" end
        repeat line = self:receive("*l") until not line or line == ""
        return 1
    end
end

local function tunneled(orig)
    return function(...)
        local a = ...
        local url = type(a) == "table" and a.url or a
        if not M.port or busy or type(url) ~= "string" or not url:find("^https:") then return orig(...) end
        busy = true
        local s = socket.tcp()
        local mt = getmetatable(s).__index
        s:close()
        local real, proxy = mt.connect, http.PROXY
        mt.connect = connectViaProxy(real, M.port)
        http.PROXY = nil -- LuaSec refuses to run with a proxy set
        local r = table.pack(pcall(orig, ...))
        mt.connect, http.PROXY, busy = real, proxy, false
        if not r[1] then error(r[2], 0) end
        return table.unpack(r, 2, r.n)
    end
end

function M.install()
    if http._nordvpn_tunnel then return end
    http._nordvpn_tunnel = true
    http.request = tunneled(http.request)
    https.request = tunneled(https.request)
end

return M
