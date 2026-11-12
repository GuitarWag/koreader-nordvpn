local R = "/opt/lib/koreader/"
package.path = R.."common/?.lua;"..R.."frontend/?.lua;"..R.."plugins/nordvpn.koplugin/?.lua;"..package.path
package.cpath = R.."common/?.so;"..R.."libs/?.so;"..package.cpath
local http, https, ltn12 = require("socket.http"), require("ssl.https"), require("ltn12")
local tunnel = require("nordvpn_tunnel")
tunnel.install()
http.PROXY = "http://127.0.0.1:25345" -- what NetworkMgr:setHTTPProxy does
local function show(label, ...) print(label, ...) end
show("A https.request, tunnel off:", https.request("https://ipinfo.io/country"))
tunnel.port = 25345
show("B https.request, tunnel on :", https.request("https://ipinfo.io/country"))
local t = {}
local ok, code = http.request{url = "https://en.wikipedia.org/w/api.php?action=query&meta=siteinfo&format=json", sink = ltn12.sink.table(t)}
show("C http.request wikipedia   :", ok, code, #table.concat(t) .. " bytes")
show("D plain http still proxied :", http.PROXY, select(2, http.request("http://example.com/")))
