local ADDON, SF = ...
local C = SF.Components
local T = SF.Theme

SF.Setup(ADDON)
SF.InitTheme()

local DURATION = 2 -- 1 = 12h, 2 = 24h, 3 = 48h
local SEARCH_TIMEOUT = 3
local ROW_HEIGHT = 22
local FRAME_WIDTH = 300
local BUTTON_HEIGHT = 26
local FOOTER_HEIGHT = 60
local PRICE_WIDTH = 100
local COMMODITY_SORT = {sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false}
local ITEM_SORT = {sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false}

local items = {}
local rows = {}
local searching = nil
local searchSentAt = 0

local updateInterval = 0.5
local timeSinceLastUpdate = 0

local function Print(msg)
    print("|cff02fd98Dump Truck:|r " .. msg)
end

local frame = CreateFrame("Frame", "DumpTruckFrame", UIParent, "BackdropTemplate")
frame:SetWidth(FRAME_WIDTH)
C.SetBackdrop(frame, T.bg.dark, T.border.color)
frame:Hide()

local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
header:SetHeight(T.headerHeight)
header:SetPoint("TOPLEFT")
header:SetPoint("TOPRIGHT")
C.SetBackdrop(header, T.bg.med, T.border.color)

local headerLine = frame:CreateTexture(nil, "ARTWORK")
headerLine:SetHeight(1)
headerLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
headerLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")
headerLine:SetColorTexture(1, 1, 1, 0.12)

local titleIcon = header:CreateTexture(nil, "OVERLAY")
titleIcon:SetSize(18, 18)
titleIcon:SetPoint("LEFT", T.padding.med, 0)
titleIcon:SetTexture("Interface\\Icons\\achievement_guildperk_cashflow_rank2")
titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local title = header:CreateFontString(nil, "OVERLAY")
C.ApplyFont(title, "large")
title:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
title:SetText("Dump Truck")
title:SetTextColor(T.accent.r, T.accent.g, T.accent.b, 1)

local subtitle = header:CreateFontString(nil, "OVERLAY")
C.ApplyFont(subtitle, 12)
subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 4, 0)
subtitle:SetText("*beep beep*")
subtitle:SetTextColor(T.text.muted.r, T.text.muted.g, T.text.muted.b, 1)

local listArea = CreateFrame("Frame", nil, frame)
listArea:SetPoint("TOPLEFT", header, "BOTTOMLEFT", T.padding.small, -T.padding.small)
listArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -T.padding.small, FOOTER_HEIGHT)

local scrollFrame = CreateFrame("ScrollFrame", nil, listArea)
scrollFrame:SetPoint("TOPLEFT")
scrollFrame:SetPoint("BOTTOMRIGHT", -(T.scrollbarWidth + 2), 0)
scrollFrame:EnableMouseWheel(true)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local maxScroll = self:GetVerticalScrollRange()
    self:SetVerticalScroll(delta > 0 and math.max(cur - ROW_HEIGHT * 2, 0) or math.min(cur + ROW_HEIGHT * 2, maxScroll))
end)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetHeight(1)
scrollFrame:SetScrollChild(content)
scrollFrame:SetScript("OnSizeChanged", function(_, width)
    content:SetWidth(width)
end)

C:ApplyScrollbar(scrollFrame, content, listArea)

local hintText = frame:CreateFontString(nil, "OVERLAY")
C.ApplyFont(hintText, "small")
hintText:SetPoint("BOTTOM", 0, BUTTON_HEIGHT + T.padding.small * 2)
hintText:SetText("Right-click bag items to add, rows to remove")
hintText:SetTextColor(T.text.muted.r, T.text.muted.g, T.text.muted.b, 1)

local PostNext

local postButton = C:CreateButton(frame, "Post Next", {
    width = 170,
    height = BUTTON_HEIGHT,
    callback = function() PostNext() end,
})
postButton:SetPoint("BOTTOMLEFT", T.padding.small, T.padding.small)
-- global so a keybound /click DumpTruckPostButton macro can spam it
DumpTruckPostButton = postButton

local clearButton = C:CreateButton(frame, "Clear", {
    width = 100,
    height = BUTTON_HEIGHT,
})
clearButton:SetPoint("BOTTOMRIGHT", -T.padding.small, T.padding.small)

local UpdateList

local function RemoveItem(item)
    for i, entry in ipairs(items) do
        if entry == item then
            table.remove(items, i)
            break
        end
    end
    if searching == item then
        searching = nil
    end
    UpdateList()
end

local function GetNextPostable()
    for _, item in ipairs(items) do
        if item.price then
            return item
        end
    end
end

local function UpdatePostButton()
    local count = 0
    for _, item in ipairs(items) do
        if item.price then
            count = count + 1
        end
    end
    postButton:SetLabel(string.format("Post Next (%d)", count))
    postButton:SetEnabled(count > 0 and C_AuctionHouse.IsThrottledMessageSystemReady())
end

local function GetRow(index)
    if rows[index] then
        return rows[index]
    end

    local row = CreateFrame("Button", nil, content, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", content, "RIGHT")
    row:RegisterForClicks("RightButtonUp")
    C.SetBackdrop(row, CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0))

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.price = row:CreateFontString(nil, "OVERLAY")
    C.ApplyFont(row.price, "small")
    row.price:SetWidth(PRICE_WIDTH)
    row.price:SetPoint("RIGHT", -2, 0)
    row.price:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY")
    C.ApplyFont(row.name, "small")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row.price, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        RemoveItem(self.item)
    end)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(T.bg.hover.r, T.bg.hover.g, T.bg.hover.b, T.bg.hover.a)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self.item.bag, self.item.slot)
        GameTooltip:AddLine("Right-click to remove", T.text.muted.r, T.text.muted.g, T.text.muted.b)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        GameTooltip:Hide()
    end)

    rows[index] = row
    return row
end

UpdateList = function()
    for i, item in ipairs(items) do
        local row = GetRow(i)
        row.item = item
        row.icon:SetTexture(item.icon)
        if item.quantity > 1 then
            row.name:SetText(item.link .. " x" .. item.quantity)
        else
            row.name:SetText(item.link)
        end
        if item.price then
            row.price:SetText(C_CurrencyInfo.GetCoinTextureString(item.price))
            row.price:SetTextColor(T.text.primary.r, T.text.primary.g, T.text.primary.b, 1)
        elseif item.noListings then
            row.price:SetText("No listings")
            row.price:SetTextColor(T.error.r, T.error.g, T.error.b, 1)
        else
            row.price:SetText("Searching...")
            row.price:SetTextColor(T.text.muted.r, T.text.muted.g, T.text.muted.b, 1)
        end
        row:Show()
    end
    for i = #items + 1, #rows do
        rows[i]:Hide()
    end
    content:SetHeight(math.max(1, #items * ROW_HEIGHT))
    UpdatePostButton()
end

local function SendSearch(item)
    searching = item
    searchSentAt = GetTime()
    -- priming the item cache, otherwise the search can get silently ignored
    C_AuctionHouse.GetItemKeyInfo(item.searchKey)
    if item.isCommodity then
        C_AuctionHouse.SendSearchQuery(item.searchKey, {COMMODITY_SORT}, false)
    elseif item.isEquipment then
        C_AuctionHouse.SendSellSearchQuery(item.searchKey, {ITEM_SORT}, true)
    else
        C_AuctionHouse.SendSearchQuery(item.searchKey, {ITEM_SORT}, true)
    end
end

local function ProcessQueue()
    if searching and GetTime() - searchSentAt > SEARCH_TIMEOUT then
        searching = nil
    end
    if searching or not C_AuctionHouse.IsThrottledMessageSystemReady() then
        return
    end
    for _, item in ipairs(items) do
        if not item.price and not item.noListings then
            SendSearch(item)
            return
        end
    end
end

local function SetPrice(item, lowest, ownsLowest)
    if lowest then
        -- undercut unless the lowest is ours, retail requires whole silver
        local price = ownsLowest and lowest or lowest - 1
        item.price = math.max(COPPER_PER_SILVER, math.floor(price / COPPER_PER_SILVER) * COPPER_PER_SILVER)
    else
        item.noListings = true
    end
    searching = nil
    UpdateList()
    ProcessQueue()
end

local function AddItem(location)
    if not location:IsValid() or not C_AuctionHouse.IsSellItemValid(location, false) then
        return
    end

    local status = C_AuctionHouse.GetItemCommodityStatus(location)
    if status == Enum.ItemCommodityStatus.Unknown then
        Print("Item info not loaded yet, try again")
        return
    end

    local bag, slot = location:GetBagAndSlot()
    local isCommodity = status == Enum.ItemCommodityStatus.Commodity
    local itemKey = C_AuctionHouse.GetItemKeyFromItem(location)

    for _, item in ipairs(items) do
        -- a commodity post takes every stack in the bags, so one entry per item
        if (item.bag == bag and item.slot == slot) or (isCommodity and item.isCommodity and item.itemKey.itemID == itemKey.itemID) then
            return
        end
    end

    local classID = select(6, C_Item.GetItemInfoInstant(itemKey.itemID))
    local isEquipment = not isCommodity and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor or classID == Enum.ItemClass.Profession)

    -- the ah returns results under a normalized key, gear gets filtered by item level after
    local searchKey
    if isEquipment then
        searchKey = C_AuctionHouse.MakeItemKey(itemKey.itemID, 0)
    else
        searchKey = C_AuctionHouse.MakeItemKey(itemKey.itemID, nil, nil, itemKey.battlePetSpeciesID)
    end

    local info = C_Container.GetContainerItemInfo(bag, slot)
    table.insert(items, {
        location = location,
        bag = bag,
        slot = slot,
        itemKey = itemKey,
        searchKey = searchKey,
        isCommodity = isCommodity,
        isEquipment = isEquipment,
        link = info.hyperlink,
        icon = info.iconFileID,
        quantity = C_AuctionHouse.GetAvailablePostCount(location),
    })
    UpdateList()
    ProcessQueue()
end

PostNext = function()
    local item = GetNextPostable()
    if not item then
        return
    end

    if not C_Item.DoesItemExist(item.location) or C_Item.GetItemID(item.location) ~= item.itemKey.itemID then
        Print(item.link .. " moved in your bags, removed from the list")
        RemoveItem(item)
        return
    end

    local quantity = C_AuctionHouse.GetAvailablePostCount(item.location)
    if item.isCommodity then
        -- true means blizzard wants a confirmation, its sell frame shows one from the cached post
        if C_AuctionHouse.PostCommodity(item.location, DURATION, quantity, item.price) then
            AuctionHouseFrame.CommoditiesSellFrame:CachePendingPost(item.location, DURATION, quantity, item.price)
        end
    else
        if C_AuctionHouse.PostItem(item.location, DURATION, quantity, nil, item.price) then
            AuctionHouseFrame.ItemSellFrame:CachePendingPost(item.location, DURATION, quantity, nil, item.price)
        end
    end

    Print(string.format("Posted %s x%d at %s", item.link, quantity, C_CurrencyInfo.GetCoinTextureString(item.price)))
    RemoveItem(item)
end

clearButton:SetCallback(function()
    wipe(items)
    searching = nil
    UpdateList()
end)

local function OnBagItemClick(self, button)
    if button ~= "RightButton" or IsModifiedClick() or not frame:IsVisible() then
        return
    end
    local bag = self.GetBagID and self:GetBagID() or self:GetParent():GetID()
    AddItem(ItemLocation:CreateFromBagAndSlot(bag, self:GetID()))
end

hooksecurefunc("ContainerFrameItemButton_OnClick", OnBagItemClick)

frame:SetScript("OnUpdate", function(_, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate >= updateInterval then
        ProcessQueue()
        UpdatePostButton()
        timeSinceLastUpdate = 0
    end
end)

frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
frame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "AUCTION_HOUSE_SHOW" then
        if frame:GetParent() ~= AuctionHouseFrame then
            frame:SetParent(AuctionHouseFrame)
            frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 2, 0)
            frame:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 2, 0)
        end
        frame:Show()
        UpdateList()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        wipe(items)
        searching = nil
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local itemID = ...
        if not searching or not searching.isCommodity or searching.itemKey.itemID ~= itemID then
            return
        end
        if C_AuctionHouse.GetNumCommoditySearchResults(itemID) > 0 then
            local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
            if result then
                SetPrice(searching, result.unitPrice, result.containsOwnerItem)
            end
        elseif C_AuctionHouse.HasFullCommoditySearchResults(itemID) then
            SetPrice(searching, nil)
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemKey = ...
        if not searching or searching.isCommodity or searching.itemKey.itemID ~= itemKey.itemID then
            return
        end
        for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
            local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
            local levelMatches = result and (not searching.isEquipment or result.itemKey.itemLevel == searching.itemKey.itemLevel)
            if result and result.buyoutAmount and levelMatches then
                SetPrice(searching, result.buyoutAmount, result.containsOwnerItem)
                return
            end
        end
        if C_AuctionHouse.HasFullItemSearchResults(itemKey) then
            SetPrice(searching, nil)
        end
    end
end)
