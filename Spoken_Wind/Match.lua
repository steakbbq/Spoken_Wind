-- Spoken Wind: which emote (token in ns.EMOTES) a CHAT_MSG_TEXT_EMOTE line is.
--
-- The client has no Lua API for emote texts (the texts live in the game's
-- data files). It only has EMOTEn_TOKEN and the localized slash words
-- EMOTEn_CMDn. So each emote row has its verb as short stems per locale.
-- A locale with no stems uses the game's own slash word for that token.
local _, ns = ...

-- The game's own slash word for an emote token ("/fart"), or nil.
function ns.EmoteCommand(token)
	local last = math.max(tonumber(_G.MAXEMOTEINDEX) or 0, 1000)
	for i = 1, last do
		if _G["EMOTE" .. i .. "_TOKEN"] == token then
			local cmd = _G["EMOTE" .. i .. "_CMD1"]
			if type(cmd) == "string" and cmd ~= "" then return cmd end
			return nil
		end
	end
	return nil
end

-- Stems for one emote row on this locale, and where they came from:
-- "checked", "guess", "cmd" (the game's slash word) or "none" (English stems).
function ns.Stems(token, locale)
	local row = ns.EMOTES[token]
	local list = row.stems[locale or ""]
	if list then return list, row.checked and row.checked[locale] and "checked" or "guess" end
	local cmd = ns.EmoteCommand(token)
	local word = cmd and cmd:gsub("^/", ""):lower()
	if word and #word >= 3 then
		local esc = word:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
		if word:find("^[%a]+$") then esc = "%f[%a]" .. esc end
		return { esc }, "cmd"
	end
	return row.stems.enUS or {}, "none"
end

local order, stems = nil, nil

-- Emote tokens in a fixed order (first hit wins).
function ns.Tokens()
	local list = {}
	for token in pairs(ns.EMOTES) do list[#list + 1] = token end
	table.sort(list)
	return list
end

-- Builds the stems for every row. Returns { token = source } for the log.
function ns.SetLocale(locale)
	order, stems = ns.Tokens(), {}
	local srcs = {}
	for _, token in ipairs(order) do
		stems[token], srcs[token] = ns.Stems(token, locale)
	end
	return srcs
end

-- The emote token this line is, or nil. sender: the name the event gave.
function ns.Match(text, sender)
	if type(text) ~= "string" then return nil end
	if issecretvalue and issecretvalue(text) then return nil end
	if not stems then ns.SetLocale(GetLocale and GetLocale() or "enUS") end
	-- cut the sender's name out first (scripts with no upper case: zhCN / koKR)
	if type(sender) == "string" and sender ~= "" and not (issecretvalue and issecretvalue(sender)) then
		local base = sender:match("^[^%-]+") or sender
		local a, b = text:find(base, 1, true)
		if a then text = text:sub(1, a - 1) .. text:sub(b + 1) end
	end
	for _, token in ipairs(order) do
		for _, p in ipairs(stems[token]) do
			if text:find(p) then return token end
		end
	end
	return nil
end
