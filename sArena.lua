sArenaMixin = {};
sArenaFrameMixin = {};

sArenaMixin.layouts = {};
sArenaMixin.portraitSpecIcon = true;

local auraList;
local interruptList;
local drList;
local severityColor = {
    [1] = { 0, 1, 0, 1},
    [2] = { 1, 1, 0, 1},
    [3] = { 1, 0, 0, 1},
};

local CombatLogGetCurrentEventInfo, UnitGUID, GetUnitName, GetSpellTexture, UnitHealthMax,
    UnitHealth, UnitPowerMax, UnitPower, UnitPowerType, GetTime, IsInInstance,
    GetNumArenaOpponentSpecs, GetArenaOpponentSpec, GetSpecializationInfoByID, select,
    SetPortraitToTexture, PowerBarColor, UnitAura, pairs = 
    CombatLogGetCurrentEventInfo, UnitGUID, GetUnitName, GetSpellTexture, UnitHealthMax,
    UnitHealth, UnitPowerMax, UnitPower, UnitPowerType, GetTime, IsInInstance,
    GetNumArenaOpponentSpecs, GetArenaOpponentSpec, GetSpecializationInfoByID, select,
    SetPortraitToTexture, PowerBarColor, UnitAura, pairs;

-- Parent Frame

function sArenaMixin:OnLoad()
    auraList = self.auraList;
    interruptList = self.interruptList;
    drList = self.drList;

    self:RegisterEvent("PLAYER_LOGIN");
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
end

function sArenaMixin:OnEvent(event)
    if ( event == "PLAYER_LOGIN" ) then
        self:Initialize();
        self:UnregisterEvent("PLAYER_LOGIN");
    elseif ( event == "PLAYER_ENTERING_WORLD" ) then
        local _, instanceType = IsInInstance();
        if ( instanceType == "arena" ) then
            self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
        else
            self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
        end
    elseif ( event == "COMBAT_LOG_EVENT_UNFILTERED" ) then
        local _, combatEvent, _, _, _, _, _, destGUID, _, _, _, spellID, _, _, auraType = CombatLogGetCurrentEventInfo();

        for i = 1, 3 do
            if destGUID == UnitGUID("arena"..i) then
                self["arena"..i]:FindInterrupt(combatEvent, spellID);
                if ( auraType == "DEBUFF" ) then
                    self["arena"..i]:FindDR(combatEvent, spellID);
                end
                return;
            end
        end
    end
end

function sArenaMixin:Initialize()
    -- TODO: Setup the Ace DB here
end

function sArenaMixin:SetLayout(layout)
    for i = 1, 3 do
        self["arena"..i]:SetLayout(layout);
    end
end

-- Arena Frames

function sArenaFrameMixin:OnLoad()
    local unit = "arena"..self:GetID();
    self.parent = self:GetParent();

    self:RegisterEvent("PLAYER_ENTERING_WORLD");
    self:RegisterEvent("UNIT_NAME_UPDATE");
    self:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS");
    self:RegisterEvent("ARENA_OPPONENT_UPDATE");
    self:RegisterEvent("ARENA_COOLDOWNS_UPDATE");
    self:RegisterEvent("ARENA_CROWD_CONTROL_SPELL_UPDATE");

    self:RegisterForClicks("AnyUp");
    self:SetAttribute("*type1", "target");
    self:SetAttribute("*type2", "focus");
    self:SetAttribute("unit", unit);
    self.unit = unit;
    self.unitChanging = true;

    CastingBarFrame_SetUnit(self.CastBar, unit, false, true);

    self.TrinketCooldown:SetAllPoints(self.TrinketIcon);
    self.AuraText:SetPoint("CENTER", self.SpecIcon, "CENTER");

    self.TexturePool = CreateTexturePool(self, "ARTWORK");

    self:SetLayout();

    self:SetMysteryPlayer();
end

function sArenaFrameMixin:OnEvent(event, eventUnit, arg1)
    local unit = self.unit;

    if ( eventUnit and eventUnit == unit ) then
        if ( event == "UNIT_NAME_UPDATE" ) then
            self.Name:SetText(GetUnitName(unit));
        elseif ( event == "ARENA_OPPONENT_UPDATE" ) then
            -- arg1 == unitEvent ("seen", "unseen", etc)
            self:UpdateVisible();
            self:UpdatePlayer(arg1);
        elseif ( event == "ARENA_COOLDOWNS_UPDATE" ) then
            self:UpdateTrinket();
        elseif ( event == "ARENA_CROWD_CONTROL_SPELL_UPDATE" ) then
            -- arg1 == spellID
            if (arg1 ~= self.TrinketIcon.spellID) then
                local _, spellTextureNoOverride = GetSpellTexture(arg1);
                self.TrinketIcon.spellID = arg1;
                self.TrinketIcon:SetTexture(spellTextureNoOverride);
            end
        elseif ( event == "UNIT_AURA" ) then
            self:FindAura();
        end
    elseif ( event == "PLAYER_ENTERING_WORLD" ) then
        self.Name:SetText("");
        self:UpdateVisible();
        self:UpdatePlayer();
        self:ResetTrinket();

        local _, instanceType = IsInInstance();
        if ( instanceType == "arena" ) then
            self:RegisterUnitEvent("UNIT_AURA", unit);
        else
            self:UnregisterEvent("UNIT_AURA");
        end
    elseif ( event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" ) then
        self:UpdateVisible();
        self:UpdatePlayer();
    end
end

function sArenaFrameMixin:OnUpdate()
    if ( self.hideStatusOnTooltip ) then return end

    local unit = self.unit;

    self:SetBarMaxValue(self.HealthBar, UnitHealthMax(unit));
    self:SetBarValue(self.HealthBar, UnitHealth(unit));
    
    self:SetBarMaxValue(self.PowerBar, UnitPowerMax(unit));
    self:SetBarValue(self.PowerBar, UnitPower(unit));

    self:SetPowerType(select(2, UnitPowerType(unit)));

    self.unitChanging = false;

    if ( self.currentAuraSpellID ) then
        local now = GetTime();
        local timeLeft = self.currentAuraExpirationTime - now;

        if ( timeLeft > 0 ) then
            self.AuraText:SetFormattedText("%.1f", timeLeft);
        end
    end
end

function sArenaFrameMixin:UpdateVisible()
    if ( InCombatLockdown() ) then return end

    local _, instanceType = IsInInstance();
    local id = self:GetID();
    if ( instanceType == "arena" and ( GetNumArenaOpponentSpecs() >= id or GetNumArenaOpponents() >= id ) ) then
        self:Show();
    else
        self:Hide();
    end
end

function sArenaFrameMixin:UpdatePlayer(unitEvent)
    local unit = self.unit;

    self:FindAura();

    if ( ( unitEvent and unitEvent ~= "seen" ) or not UnitExists(unit) ) then
            self:SetMysteryPlayer();
            return;
    end
    
    self.hideStatusOnTooltip = false;

    self.Name:SetText(GetUnitName(unit));

    local color = RAID_CLASS_COLORS[select(2, UnitClass(unit))];

    if color then
        self.HealthBar:SetStatusBarColor(color.r, color.g, color.b, 1.0);
    else
        self.HealthBar:SetStatusBarColor(0, 1.0, 0, 1.0);
    end
end

function sArenaFrameMixin:SetMysteryPlayer()
    self.hideStatusOnTooltip = true;
    self.unitChanging = true;

    local f = self.HealthBar;
    f:SetMinMaxValues(0,100);
    f:ResetSmoothedValue(100);
    f:SetStatusBarColor(0.5, 0.5, 0.5);

    f = self.PowerBar;
    f:SetMinMaxValues(0,100);
    f:ResetSmoothedValue(100);
    f:SetStatusBarColor(0.5, 0.5, 0.5);
end

function sArenaFrameMixin:UpdateSpecIcon()
    local _, instanceType = IsInInstance();

    if ( instanceType ~= "arena" ) then
        self.specTexture = nil;
    elseif ( not self.specTexture ) then
        local id = self:GetID();
        if ( GetNumArenaOpponentSpecs() >= id ) then
            local specID = GetArenaOpponentSpec(id);
            if ( specID > 0 ) then
                self.specTexture = select(4, GetSpecializationInfoByID(specID));
            end
        end
    end

    local texture = self.currentAuraSpellID and GetSpellTexture(self.currentAuraSpellID) or self.specTexture and self.specTexture or 134400;

    if ( self.currentSpecTexture == texture ) then return end

    self.currentSpecTexture = texture;

    if ( self.parent.portraitSpecIcon ) then
        if ( texture == 134400 ) then
            texture = "Interface\\CharacterFrame\\TempPortrait";
        end
        SetPortraitToTexture(self.SpecIcon, texture)
    else
        self.SpecIcon:SetTexture(texture);
    end
end

function sArenaFrameMixin:UpdateTrinket()
    local spellID, startTime, duration = C_PvP.GetArenaCrowdControlInfo(self.unit);
    if ( spellID ) then
        if ( spellID ~= self.TrinketIcon.spellID ) then
            local _, spellTextureNoOverride = GetSpellTexture(spellID);
            self.TrinketIcon.spellID = spellID;
            self.TrinketIcon:SetTexture(spellTextureNoOverride);
        end
        if ( startTime ~= 0 and duration ~= 0 ) then
            self.TrinketCooldown:SetCooldown(startTime/1000.0, duration/1000.0);
        else
            self.TrinketCooldown:Clear();
        end
    end
end

function sArenaFrameMixin:ResetTrinket()
    self.TrinketIcon.spellID = nil;
    self.TrinketIcon:SetTexture(134400);
    self.TrinketCooldown:Clear();
    self:UpdateTrinket();
end

function sArenaFrameMixin:SetLayout(layout)
    if ( InCombatLockdown() ) then return end

    if ( #sArenaMixin.layouts == 0 ) then
        return;
    end

    layout = sArenaMixin.layouts[layout] and layout or 1;

    self:ResetLayout();
    sArenaMixin.layouts[layout]:Initialize(self);

    self:UpdatePlayer();
end

local function ResetTexture(t)
    t:SetTexture(nil);
    t:SetColorTexture(0, 0, 0, 0);
    t:SetTexCoord(0, 1, 0, 1);
    t:ClearAllPoints();
    t:SetSize(0, 0);
    t:Hide();
end

local function ResetStatusBar(f)
    f:SetStatusBarTexture(nil);
    f:ClearAllPoints();
    f:SetSize(0, 0);
end

local function ResetFontString(f)
    f:SetDrawLayer("OVERLAY", 1);
    f:SetJustifyH("CENTER");
    f:SetJustifyV("MIDDLE");
    f:SetTextColor(1, 0.82, 0, 1);
    f:SetShadowColor(0, 0, 0, 1);
    f:SetShadowOffset(1, -1);
    f:ClearAllPoints();
    f:Hide();
end

function sArenaFrameMixin:ResetLayout()
    self.currentSpecTexture = nil;

    ResetTexture(self.SpecIcon);
    ResetStatusBar(self.HealthBar);
    ResetStatusBar(self.PowerBar);
    ResetStatusBar(self.CastBar);

    local f = self.TrinketIcon;
    f:ClearAllPoints();
    f:SetSize(0, 0);
    f:SetTexCoord(0, 1, 0, 1);

    f = self.Name;
    ResetFontString(f);
    f:SetDrawLayer("ARTWORK", 2);
    f:SetFont("Fonts\\FRIZQT__.TTF", 10, nil);

    f = self.AuraText;
    ResetFontString(f);
    f:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE");
    f:SetTextColor(1, 1, 1, 1);

    self.TexturePool:ReleaseAll();
end

function sArenaFrameMixin:SetBarValue(bar, value)
    if ( self.unitChanging ) then
        bar:ResetSmoothedValue(value);
    else
        bar:SetSmoothedValue(value);
    end
end

function sArenaFrameMixin:SetBarMaxValue(bar, value)
    bar:SetMinMaxSmoothedValue(0, value);
    if ( self.unitChanging ) then
        bar:ResetSmoothedValue();
    end
end

function sArenaFrameMixin:SetPowerType(powerType)
    local color = PowerBarColor[powerType];
    if color then
        self.PowerBar:SetStatusBarColor(color.r, color.g, color.b);
    end
end

function sArenaFrameMixin:FindAura()
    local unit = self.unit;
    local currentSpellID, currentExpirationTime = nil, 0;

    for i = 1, 2 do
        local filter = (i == 1 and "HELPFUL" or "HARMFUL");

        for i = 1, 30 do
            local _, _, _, _, _, expirationTime, _, _, _, spellID = UnitAura(unit, i, filter);

            if ( not spellID ) then break end

            if ( auraList[spellID] ) then
                if ( not currentSpellID or auraList[spellID] < auraList[currentSpellID] ) then
                    currentSpellID = spellID;
                    currentExpirationTime = expirationTime;
                end
            end
        end
    end

    self:SetAura(currentSpellID, currentExpirationTime);
end

function sArenaFrameMixin:SetAura(spellID, expirationTime)
    if ( self.currentInterruptSpellID ) then
        if ( spellID and auraList[spellID] < auraList[self.currentInterruptSpellID] ) then
            self.currentAuraSpellID = spellID;
            self.currentAuraExpirationTime = expirationTime;
        else
            self.currentAuraSpellID = self.currentInterruptSpellID;
            self.currentAuraExpirationTime = self.currentInterruptExpirationTime;
        end
    elseif ( spellID ) then
        self.currentAuraSpellID = spellID;
        self.currentAuraExpirationTime = expirationTime;
    else
        self.currentAuraSpellID = nil;
        self.currentAuraExpirationTime = 0;
    end

    if ( self.currentAuraExpirationTime == 0 ) then
        self.AuraText:SetText("");
    end

    self:UpdateSpecIcon();
end

function sArenaFrameMixin:FindInterrupt(event, spellID)
    local interruptDuration = interruptList[spellID];

    if ( not interruptDuration ) then return end
    if ( event ~= "SPELL_INTERRUPT" and event ~= "SPELL_CAST_SUCCESS" ) then return end

    local unit = self.unit;
    local _, _, _, _, _, _, notInterruptable = UnitChannelInfo(unit);

    if ( event == "SPELL_INTERRUPT" or notInterruptable == false ) then
        self.currentInterruptSpellID = spellID;
        self.currentInterruptExpirationTime = GetTime() + interruptDuration;
        self:FindAura();
        C_Timer.After(interruptDuration, function() self.currentInterruptSpellID = nil; self.currentInterruptExpirationTime = 0; self:FindAura(); end);
    end
end

do
    local drTime = 18.5;

    function sArenaFrameMixin:FindDR(combatEvent, spellID)
        local category = drList[spellID];
        if ( not category ) then return end

        local frame = self[category];
        local currTime = GetTime();

        if ( combatEvent == "SPELL_AURA_REMOVED" or combatEvent == "SPELL_AURA_BROKEN" ) then
            local startTime, startDuration = frame.Cooldown:GetCooldownTimes();
            startTime, startDuration = startTime/1000, startDuration/1000;

            local newDuration = drTime / (1 - ((currTime - startTime) / startDuration));
            local newStartTime = drTime + currTime - newDuration;

            frame.Cooldown:SetCooldown(newStartTime, newDuration);

            return;
        elseif ( combatEvent == "SPELL_AURA_APPLIED" or combatEvent == "SPELL_AURA_REFRESH" ) then
            local unit = self.unit;

            for i = 1, 30 do
                local _, _, _, _, duration, _, _, _, _, _spellID = UnitAura(unit, i, "HARMFUL");

                if ( not _spellID ) then break end

                if ( duration and spellID == _spellID ) then
                    frame.Cooldown:SetCooldown(currTime, duration + drTime);
                    break;
                end
            end
        end

        frame.Icon:SetTexture(GetSpellTexture(spellID));
        frame.Border:SetVertexColor(unpack(severityColor[frame.severity]));

        frame.severity = frame.severity + 1;
        if frame.severity > 3 then
            frame.severity = 3;
        end
    end
end

do
    local categories = {
        "Stun",
        "Incapacitate",
        "Disorient",
        "Silence",
        "Root",
    };

    function sArenaFrameMixin:UpdateDRPositions()
        local active = 0;
        local frame, prevFrame;

        for i = 1, #categories do
            frame = self[categories[i]];

            if ( frame:GetAlpha() == 1 ) then
                frame:ClearAllPoints();
                if ( active == 0 ) then
                    frame:SetPoint("RIGHT", self, "LEFT", 0, 10);
                else
                    frame:SetPoint("RIGHT", prevFrame, "LEFT", -2, 0);
                end
                active = active + 1;
                prevFrame = frame;
            end
        end
    end
end