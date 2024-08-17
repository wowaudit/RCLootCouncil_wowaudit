syncedDataTimestamp = nil
syncedWowauditData = {}

wowauditDataPresent = function()
  if wowauditTimestamp == nil and syncedDataTimestamp == nil then
    return false
  else
    return true
  end
end

wowauditDataToDisplay = function(itemID, itemString, character)
  if syncedDataTimestamp ~= nil and (wowauditTimestamp == nil or syncedDataTimestamp > wowauditTimestamp) then
    if syncedWowauditData[itemID] and syncedWowauditData[itemID][character] then
      return syncedWowauditData[itemID][character]
    end
  else
    return wowauditDataForCharacter(itemID, itemString, character)
  end
end

wowauditDataForCharacter = function(itemID, itemString, character)
  local wishes = {}
  for property in string.gmatch(itemString, "([^:]+)") do
    if difficulties[property] then
      local diff = difficulties[property]

      if wishlistData[character] and wishlistData[character][diff] then
        for _, item in ipairs(wishlistData[character][diff]) do
          if item.id == itemID then
            tinsert(wishes, item)
          end
        end
      end
    end
  end

  return wishes
end

wowauditDataForItem = function(itemID, itemString)
  local characters = {}
  for character, _ in pairs(wishlistData) do
    local wishes = wowauditDataForCharacter(itemID, itemString, character)
    if #wishes > 0 then
      characters[character] = wishes
    end
  end

  return characters
end

highestWishValue = function(wishes)
  local highest = 0
  for i, wish in ipairs(wishes) do
    if wish.value > highest then
      highest = wish.value
    end
  end

  return highest
end

-- status values are one-character acronyms on purpose, to save space.
textColors = {
  b = "DIM_GREEN_FONT_COLOR", -- BIS
  n = "YELLOW_THREAT_COLOR", -- not BIS
  o = "DRAGONFLIGHT_RED_COLOR", -- outdated
}

withColor = function(text, colorKey)
  return "|cn" .. textColors[colorKey] .. ":" .. text .. "|r"
end

-- Copied from Details/functions/profiles.lua
specCoords = {
  [577] = {128/512, 192/512, 256/512, 320/512}, --havoc demon hunter
  [581] = {192/512, 256/512, 256/512, 320/512}, --vengeance demon hunter

  [250] = {0, 64/512, 0, 64/512}, --blood dk
  [251] = {64/512, 128/512, 0, 64/512}, --frost dk
  [252] = {128/512, 192/512, 0, 64/512}, --unholy dk

  [102] = {192/512, 256/512, 0, 64/512}, -- druid balance
  [103] = {256/512, 320/512, 0, 64/512}, -- druid feral
  [104] = {320/512, 384/512, 0, 64/512}, -- druid guardian
  [105] = {384/512, 448/512, 0, 64/512}, -- druid resto

  [253] = {448/512, 512/512, 0, 64/512}, -- hunter bm
  [254] = {0, 64/512, 64/512, 128/512}, --hunter marks
  [255] = {64/512, 128/512, 64/512, 128/512}, --hunter survivor

  [62] = {(128/512) + 0.001953125, 192/512, 64/512, 128/512}, --mage arcane
  [63] = {192/512, 256/512, 64/512, 128/512}, --mage fire
  [64] = {256/512, 320/512, 64/512, 128/512}, --mage frost

  [268] = {320/512, 384/512, 64/512, 128/512}, --monk bm
  [269] = {448/512, 512/512, 64/512, 128/512}, --monk ww
  [270] = {384/512, 448/512, 64/512, 128/512}, --monk mw

  [65] = {0, 64/512, 128/512, 192/512}, --paladin holy
  [66] = {64/512, 128/512, 128/512, 192/512}, --paladin protect
  [70] = {(128/512) + 0.001953125, 192/512, 128/512, 192/512}, --paladin ret

  [256] = {192/512, 256/512, 128/512, 192/512}, --priest disc
  [257] = {256/512, 320/512, 128/512, 192/512}, --priest holy
  [258] = {(320/512) + (0.001953125 * 4), 384/512, 128/512, 192/512}, --priest shadow

  [259] = {384/512, 448/512, 128/512, 192/512}, --rogue assassination
  [260] = {448/512, 512/512, 128/512, 192/512}, --rogue combat
  [261] = {0, 64/512, 192/512, 256/512}, --rogue sub

  [262] = {64/512, 128/512, 192/512, 256/512}, --shaman elemental
  [263] = {128/512, 192/512, 192/512, 256/512}, --shamel enhancement
  [264] = {192/512, 256/512, 192/512, 256/512}, --shaman resto

  [265] = {256/512, 320/512, 192/512, 256/512}, --warlock aff
  [266] = {320/512, 384/512, 192/512, 256/512}, --warlock demo
  [267] = {384/512, 448/512, 192/512, 256/512}, --warlock destro

  [71] = {448/512, 512/512, 192/512, 256/512}, --warrior arms
  [72] = {0, 64/512, 256/512, 320/512}, --warrior fury
  [73] = {64/512, 128/512, 256/512, 320/512}, --warrior protect

  [1467] = {256/512, 320/512, 256/512, 320/512}, -- Devastation
  [1468] = {320/512, 384/512, 256/512, 320/512}, -- Preservation
  [1473] = {384/512, 448/512, 256/512, 320/512}, -- Augmentation
}

logoIcon = "|TInterface\\AddOns\\RCLootCouncil_wowaudit\\Media\\logo:16:16:0:0:0:0:0:0:0:0|t"

specIcon = function(specID)
  local iconSize = 12
  local L, R, T, B = unpack(specCoords[specID])
  return "|TInterface\\AddOns\\RCLootCouncil_wowaudit\\Media\\spec_icons_normal:" .. iconSize .. ":" .. iconSize .. ":0:0:512:512:" .. (L * 512) .. ":" .. (R * 512) .. ":" .. (T * 512) .. ":" .. (B * 512) .. "|t "
end

printtable = function(data, level)
	if not data then return end
	level = level or 0
	local ident = strrep('     ', level)
	if level > 6 then return end
	if type(data) ~= 'table' then print(tostring(data)) end
	for index, value in pairs(data) do
		repeat
			if type(value) ~= 'table' then
				print(ident .. '[' .. tostring(index) .. '] = ' .. tostring(value) .. ' (' .. type(value) .. ')');
				break
			end
			print(ident .. '[' .. tostring(index) .. '] = {')
			_G.printtable(value, level + 1)
			print(ident .. '}');
		until true
	end
end