local Utils = require("utils")
local Logger = require("logger")

local Ui = {}

local INFINITY = 2^15

local function red ()
    return 1, 0, 0, 1
end

local function gray ()
    return 0.5, 0.5, 0.5, 1.0
end

-- Parses the list of clothes from the user, converts the multiline string into a list of TweakDB paths
local function textToListOfClothes (clothes)
    clothes = Utils.split(clothes, "\r\n")
    local ret = {}
    for _, cloth in ipairs(clothes) do
        local tweakDBID = cloth:match("Items%.([_%w]+)") or cloth:match("[_%w]+")
        if tweakDBID then
            table.insert(ret, "Items."..tweakDBID)
        end
    end
    return ret
end

function Ui:init (wardrobeItemsAdder)
    self.isVisible = false

    local config = wardrobeItemsAdder.config
    if not config.rememberLastAddedItems or not config.lastAddedItems then
        config.lastAddedItems = ""
    end
    self.clothesText = config.lastAddedItems
    self.addNewBlacklistItemText = ""

    self.wardrobeItemsAdder = wardrobeItemsAdder

    self.winWidth = 355
    self.winContentWidth = self.winWidth - 32
    self.buffSize = 4 * 2^20

    return self
end

function Ui:onOverlayOpen ()
    self.isVisible = true
end

function Ui:onOverlayClose ()
    self.isVisible = false
end

function Ui:drawSeparatorWithSpacing()
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()
end

function Ui:updateWindowSize()
    self.winWidth, self.winHeight = ImGui.GetWindowSize()
    self.winContentWidth = self.winWidth - Ui:textWidth(4)
end

function Ui:textWidth(charCount)
    return ImGui.CalcTextSize(string.rep("X", charCount))
end

function Ui:setWindowSize()
    local defaultWidth = Ui:textWidth(45)
    local defaultHeight = ImGui.GetTextLineHeight() * 26
    ImGui.SetNextWindowSize(defaultWidth, defaultHeight, ImGuiCond_FirstUseEver)

    local minWidth = Ui:textWidth(35)
    local minHeight = ImGui.GetTextLineHeight() * 20
    ImGui.SetNextWindowSizeConstraints(minWidth, minHeight, INFINITY, INFINITY)
end

function Ui:onDraw ()
    if not self.isVisible then
        return
    end

    -- ImGui methods cannot be called from outside onDraw, like in Ui:init
    Ui:setWindowSize()

    if ImGui.Begin("Wardrobe Items Adder") then
        Ui:updateWindowSize()
        if ImGui.BeginTabBar("##tabBar") then
            if ImGui.BeginTabItem("Adder") then
                Ui:drawMainTab()
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem("Settings") then
                Ui:drawSettings()
                ImGui.EndTabItem()
            end
            if self.wardrobeItemsAdder.config.showAdvancedSettings then
                if ImGui.BeginTabItem("Blacklist") then
                    Ui:drawBlacklist()
                    ImGui.EndTabItem()
                end
            end
            ImGui.EndTabBar();
        end
    end
    ImGui.End()
end

function Ui:drawRemovalWarning ()
    ImGui.PushStyleColor(ImGuiCol.Text, red())
    ImGui.TextWrapped("Warning: items cannot be removed from wardrobe.")
    ImGui.PopStyleColor()
end

function Ui:drawMainTab ()
    Ui:drawRemovalWarning()
    if ImGui.Button("Add All Clothes", self.winContentWidth, 0) then
        self.wardrobeItemsAdder:addAllClothesToWardrobe()
        Logger:info("Added all clothes to wardrobe.")
    end

    Ui:drawSeparatorWithSpacing()

    Ui:drawSectionDescription("Add Specific Clothes",
"Each line should contain at most one item ID, "..
"with or without the \"Items.\" prefix. "..
"For convenience, Game.AddToInventory(...) "..
"commands can be copy-pasted as-is.")

    local _, availableHeight = ImGui.GetContentRegionAvail()
    local buttonSize = ImGui.GetTextLineHeight() * 2
    local clothesTextHeight = availableHeight - buttonSize
    self.clothesText =
        ImGui.InputTextMultiline(
            "##specificClothesInput",
            self.clothesText,
            self.buffSize,
            self.winContentWidth,
            clothesTextHeight)
    ImGui.Spacing()
    if ImGui.Button("Add Listed Items", self.winContentWidth, 0) then
        self.wardrobeItemsAdder:addClothesToWardrobe(textToListOfClothes(self.clothesText))
        local config = self.wardrobeItemsAdder.config
        if config.rememberLastAddedItems then
            config.lastAddedItems = self.clothesText
            self.wardrobeItemsAdder:saveConfig()
        end
    end
end

function Ui:drawConfigCheckbox (label, config, configKey, tooltip)
    local changed = false
    config[configKey], changed = ImGui.Checkbox(label, config[configKey])
    if changed then
        self.wardrobeItemsAdder:saveConfig()
    end
    if tooltip and ImGui.IsItemHovered() then
        ImGui.SetTooltip(tooltip)
    end
end

function Ui:drawSectionDescription (title, description)
    ImGui.Text(title)
    ImGui.PushStyleColor(ImGuiCol.Text, gray())
    ImGui.TextWrapped(description)
    ImGui.PopStyleColor()
    ImGui.Spacing()
end

function Ui:drawSettings ()
    local config = self.wardrobeItemsAdder.config

    Ui:drawRemovalWarning()

    Ui:drawConfigCheckbox("Add All Clothes On Spawn", config, "addAllClothesOnPlayerSpawn",
        "Automatically add all clothes to the wardrobe after the player spawns.")

    Ui:drawConfigCheckbox("Show Advanced Settings", config, "showAdvancedSettings")
    if config.showAdvancedSettings then
        Ui:drawAdvancedSettings()
    end

    if ImGui.Button("Reset Settings And Data", self.winContentWidth, 0) then
        self.wardrobeItemsAdder:loadDefaultConfig()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip([[
Load the mod's default configuration.
The mod's blacklist, last added items, and
other persistent data will also be reset.
]])
    end
end

function Ui:drawAdvancedSettings ()
    Ui:drawConfigCheckbox("Remember Last Added Items", self.wardrobeItemsAdder.config, "rememberLastAddedItems",
        "Remember between game sessions the last used text input in the \"Add Specific Clothes\" section.")
    Ui:drawLogLevelCombo()
    Ui:drawSeparatorWithSpacing()
    Ui:drawFiltersCheckboxes()
    Ui:drawSeparatorWithSpacing()
end

function Ui:drawLogLevelCombo ()
    local items = {"All", "Default", "Only Errors And Warnings", "Only Errors", "None"}
    local currentIndex = Logger.logLevel
    local preview = items[currentIndex]
    if ImGui.BeginCombo("Log Level", preview) then
        for index, _ in ipairs(items) do
            local isSelected = (currentIndex == index)
            if ImGui.Selectable(items[index], isSelected) then
                currentIndex = index
                self.wardrobeItemsAdder.config.logLevel = currentIndex
                self.wardrobeItemsAdder:updateLogLevel()
                self.wardrobeItemsAdder:saveConfig()
            end
            if isSelected then
                ImGui.SetItemDefaultFocus()
            end
        end
        ImGui.EndCombo()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip([[
Reduce or increase the amount of console logs from the mod.
]])
    end
end

function Ui:drawFiltersCheckboxes ()
    Ui:drawSectionDescription("Item Filters",
"The mod by default filters out items which "..
"appear to be broken or not intended to be "..
"in wardrobe. You can enable or disable "..
"filters below. However, the game's wardrobe "..
"system can still refuse to add an item.")

    local filters = self.wardrobeItemsAdder.config.isFilterEnabled
    Ui:drawConfigCheckbox("Exists In Database", filters,
        "mustExist", "The item's record must exist in the game's database.")
    Ui:drawConfigCheckbox("Has \"Clothing\" Category", filters,
        "mustHaveClothingCategory", "The item must have \"Clothing\" category.")
    Ui:drawConfigCheckbox("Has Display Name", filters,
        "mustHaveDisplayName", "The item must have valid \"displayName\" field.")
    Ui:drawConfigCheckbox("Has Appearance Name", filters,
        "mustHaveAppearanceName", "The item must have valid \"appearanceName\" field.")
    Ui:drawConfigCheckbox("Is Not Crafting Spec", filters,
        "mustNotBeCraftingSpec", [[
The item must not have "CraftingData" field,
or ID indicating it is/was a crafting spec in previous versions of the game, that is
ID must not end with _Crafting, _Legendary, _Epic, or _Crafted,
and must not start with VHard_, Hard_, Normal_, Story_, Weak_, Avg_, or Str_.
]])
    Ui:drawConfigCheckbox("Is Not Lifepath Item Duplicate", filters,
        "mustNotBeLifepathDuplicate", [[
The item ID must not start with a pattern similar to "Q301_Corpo_WA_",
as it's probably a duplicate of a normal item.
The reason is that it seems some lifepath-specific clothes have three versions:
the normal item, lifepath item for male V, and lifepath item for female V.
This filters out the lifepath versions, which have the same appearance as the normal item,
although they might differ in name/description.
]])
    Ui:drawConfigCheckbox("Is Not Blacklisted", filters,
        "mustNotBeOnBlacklist", [[
The item must not be blacklisted in the mod's configuration.
The mod's blacklist can be viewed and modified in the Blacklist tab.
]])
    Ui:drawConfigCheckbox("Is Not Blacklisted By Game", filters,
        "mustNotBeOnInternalBlacklist", [[
The item must not be on the wardrobe blacklist.
The blacklist can be found in the TweakDB Editor under record
gamedataItemList_Record.Items.WardrobeBlacklist.items
]])
end

function Ui:drawBlacklist ()
    Ui:drawSectionDescription("Item Blacklist",
"These items will not be added by the mod "..
"if the blacklist filter is enabled. "..
"This is NOT the in-game blacklist. "..
"If you find these items during gameplay, "..
"they will still be added to the wardrobe.")

    local blacklist = self.wardrobeItemsAdder.config.blacklist
    local editable = self.wardrobeItemsAdder.config.blacklistModifiedByUser
    local bufferSizePerItem = 200
    local addRemoveButtonsSize = Ui:textWidth(8)
    local spacingWidth = Ui:textWidth(1)

    local itemToRemoveIndex = nil
    for index, oldPath in ipairs(blacklist) do
        local labelExtension = "##blacklist"..tostring(index)
        if editable then
            if ImGui.Button("Remove"..labelExtension, addRemoveButtonsSize, 0) then
                itemToRemoveIndex = index
            end
            ImGui.SameLine()
        end
        ImGui.PushItemWidth(self.winContentWidth - (editable and (addRemoveButtonsSize + spacingWidth) or 0))
        blacklist[index] = ImGui.InputText(labelExtension, blacklist[index], bufferSizePerItem,
            editable and ImGuiInputTextFlags.None or ImGuiInputTextFlags.ReadOnly)
        ImGui.PopItemWidth()
        if blacklist[index] ~= oldPath then
            self.wardrobeItemsAdder:saveConfig()
            self.wardrobeItemsAdder:updateBlacklistSet()
        end
    end

    if itemToRemoveIndex then
        table.remove(blacklist, itemToRemoveIndex)
        self.wardrobeItemsAdder:saveConfig()
        self.wardrobeItemsAdder:updateBlacklistSet()
    end

    if editable then
        local addButtonPressed = ImGui.Button(" Add  ".."##blacklist", addRemoveButtonsSize, 0)
        ImGui.SameLine()
        ImGui.PushItemWidth(self.winContentWidth - addRemoveButtonsSize - spacingWidth)
        local entered = false
        self.addNewBlacklistItemText, entered =
            ImGui.InputText(
                "##blacklistNewItemTextInput",
                self.addNewBlacklistItemText,
                bufferSizePerItem,
                ImGuiInputTextFlags.EnterReturnsTrue)
        if self.focusAdd then
            ImGui.SetKeyboardFocusHere(-1)
            self.focusAdd = false
        end
        local newItem = Utils.trim(self.addNewBlacklistItemText)
        if (addButtonPressed or entered) and #newItem > 0 then
            table.insert(blacklist, newItem)
            self.focusAdd = true
            self.addNewBlacklistItemText = ""
            self.wardrobeItemsAdder:saveConfig()
            self.wardrobeItemsAdder:updateBlacklistSet()
        end
        ImGui.PopItemWidth()
    end

    if editable then
        if ImGui.Button("Restore Default Blacklist", self.winContentWidth, 0) then
            self.wardrobeItemsAdder:restoreDefaultBlacklist()
            self.wardrobeItemsAdder:saveConfig()
            self.wardrobeItemsAdder:updateBlacklistSet()
        end
    else
        if ImGui.Button("Edit Blacklist", self.winContentWidth, 0) then
            self.wardrobeItemsAdder.config.blacklistModifiedByUser = true
            self.wardrobeItemsAdder:saveConfig()
        end
    end
end

return Ui
