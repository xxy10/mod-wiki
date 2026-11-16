-- Gold Film VFX - state-triggered custom weapon effects (REFramework / MH Wilds)
-- Purely ADDITIVE: spawns only its own GameObjects under the weapon transform;
-- hooks nothing, replaces no vanilla effect slot -> coexists with everything.
--
-- State machine (hcl_ryujin pattern) + custom-lifecycle LIGHT PILLAR:
--   sheathe: appear fast -> stretch to 2x -> hold while sheathed
--   draw:    big iai (Iai Spirit Slash, motions 252/263/264/265) -> hold 1s -> fade
--            small iai / normal draw -> removed immediately

local TITLE  = "Gold Film VFX"
local PREFIX = TITLE .. " - "
local ASSET  = "Art/Model/Item/it03/00/0005/"

-- ==========================================================================
-- 1. MOUNTS per state (film shell / star cross etc.)
-- ==========================================================================
local MOUNTS = {
    sheathed = {
        { name = "star_guard",  mesh = ASSET .. "star_cross.mesh",
          mdf2 = ASSET .. "star_cross.mdf2",
          part = "WpSub_Parent", joint = "Guard_Star" },
    },
    drawn = {
        { name = "film_blade",  mesh = ASSET .. "gold_film.mesh",
          mdf2 = ASSET .. "gold_film.mdf2",
          part = "Wp_Parent",   joint = "Base" },
        { name = "star_guard",  mesh = ASSET .. "star_cross.mesh",
          mdf2 = ASSET .. "star_cross.mdf2",
          part = "Wp_Parent",   joint = "Guard_Star" },
    },
}

-- ==========================================================================
-- 2. LIGHT PILLAR - custom lifecycle with draw-type detection
--    Big iai = Iai Spirit Slash (bank 20: 252/263/264/265, catalogued from
--    the hcl_ryujin analysis). Small iai ID not catalogued -> the else
--    branch handles it (and any normal draw) automatically.
-- ==========================================================================
local SPIRIT_MOTIONS = { ["252"] = true, ["263"] = true, ["264"] = true, ["265"] = true }

local PILLAR = {
    mesh = ASSET .. "light_pillar.mesh",    -- additive glow cylinder, origin at BASE
    mdf2 = ASSET .. "light_pillar.mdf2",
    part = "WpSub_Parent", joint = "Guard_Star",
    appear = 0.10,       -- 快速出现
    grow = 0.35,         -- 伸长到 2 倍
    grow_to = 2.0,
    pending = 0.25,      -- 拔刀方式判定窗口
    draw_hold = 1.00,    -- 大居合后保持
    fade = 0.30,         -- 淡出
}
local pillar = nil       -- { entry, phase, t0 }

-- ==========================================================================
-- 3. HELPERS (API patterns verified in blade_prop.lua / hcl_ryujin.lua /
--    VFX Unleashed.lua motion polling)
-- ==========================================================================
local function call(object, method, ...)
    if not object then return nil end
    local args = {...}
    local ok, value = pcall(function()
        return object:call(method, table.unpack(args))
    end)
    if ok then return value end
end

local function hunter_character()
    local ok, hunter = pcall(function()
        local manager = sdk.get_managed_singleton("app.PlayerManager")
        local list = manager and manager:get_field("_PlayerList")
        local player = list and list[0]
        local info = player and player:get_field("_PlayerInfo")
        return info and info:get_field("<Character>k__BackingField")
    end)
    if ok then return hunter end
end

local weapon_on_field = sdk.find_type_definition("app.HunterCharacter")
    and sdk.find_type_definition("app.HunterCharacter"):get_field("_IsWeaponOn")

local function weapon_is_drawn()
    local hunter = hunter_character()
    if not hunter or not weapon_on_field then return nil end
    local value = weapon_on_field:get_data(hunter)
    if value == nil then return nil end
    return value == true
end

local motion_component, motion_hunter = nil, nil
local function current_motion()
    local hunter = hunter_character()
    local object = hunter and call(hunter, "get_GameObject")
    if not object then return nil end
    local hid = tostring(object)
    if hid ~= motion_hunter then
        motion_component, motion_hunter = nil, hid
    end
    if not motion_component then
        motion_component = object:call("getComponent(System.Type)",
            sdk.typeof("via.motion.Motion"))
    end
    local layer = motion_component and motion_component:call("getLayer", 0)
    if not layer then return nil end
    return tostring(layer:call("get_MotionBankID")),
        tostring(layer:call("get_MotionID"))
end

local function find_weapon_part(part_name)
    local hunter = hunter_character()
    local object = hunter and call(hunter, "get_GameObject")
    local root = object and call(object, "get_Transform")
    if not root then return nil end
    local stack, visited = {root}, {}
    while #stack > 0 do
        local transform = table.remove(stack)
        local key = tostring(transform)
        if not visited[key] then
            visited[key] = true
            local child_object = call(transform, "get_GameObject")
            if tostring(call(child_object, "get_Name") or "") == part_name then
                return transform
            end
            local child = call(transform, "get_Child")
            while child do
                stack[#stack + 1] = child
                child = call(child, "get_Next")
            end
        end
    end
end

local resources = {}
local function holder(kind, holder_kind, path)
    if resources[path] then return resources[path] end
    local raw = sdk.create_resource(kind, path)
    if not raw then return nil end
    raw:add_ref()
    local value = raw:create_holder(holder_kind)
    if value then value:add_ref() end
    resources[path] = value
    return value
end

local function spawn_mount(mount, parent_transform)
    local game_object_type = sdk.find_type_definition("via.GameObject")
    local object = sdk.call_native_func(nil, game_object_type,
        "create(System.String)", PREFIX .. mount.name)
    if not object then return nil end
    local mesh = object:call("createComponent(System.Type)",
        sdk.typeof("via.render.Mesh"))
    local mesh_holder = holder("via.render.MeshResource",
        "via.render.MeshResourceHolder", mount.mesh)
    local material_holder = holder("via.render.MeshMaterialResource",
        "via.render.MeshMaterialResourceHolder", mount.mdf2)
    if not (mesh and mesh_holder and material_holder) then
        object:call("destroy", object)
        return nil
    end
    mesh:call("setMesh(via.render.MeshResourceHolder)", mesh_holder)
    mesh:call("set_Material(via.render.MeshMaterialResourceHolder)", material_holder)
    mesh:call("set_Enabled", true)
    local transform = object:call("get_Transform")
    transform:call("set_Parent(via.Transform)", parent_transform)
    if mount.joint then
        pcall(function()
            transform:call("set_ParentJoint(System.String)", mount.joint)
        end)
    end
    return { object = object, mesh = mesh }
end

-- ==========================================================================
-- 4. PILLAR LIFECYCLE
-- ==========================================================================
local function pillar_destroy()
    if pillar then
        pcall(function() pillar.entry.mesh:call("set_Enabled", false) end)
        pcall(function() pillar.entry.object:call("destroy", pillar.entry.object) end)
        pillar = nil
    end
end

local function pillar_set(sy, sxz)
    if not pillar then return end
    pillar.entry.object:call("get_Transform"):call("set_LocalScale(via.vec3)",
        Vector3f.new(sxz, sy, sxz))
end

local function pillar_phase(p)
    if pillar then pillar.phase, pillar.t0 = p, os.clock() end
end

local function pillar_spawn()
    pillar_destroy()
    local part = find_weapon_part(PILLAR.part)
    if not part then return end
    local entry = spawn_mount({ name = "light_pillar", mesh = PILLAR.mesh,
        mdf2 = PILLAR.mdf2, joint = PILLAR.joint }, part)
    if entry then pillar = { entry = entry, phase = "appear", t0 = os.clock() } end
end

local function pillar_update(now, drawn, sheathe_transition)
    if sheathe_transition then pillar_spawn() return end
    if not pillar then return end
    local dt = now - pillar.t0
    if pillar.phase == "appear" then                       -- 快速出现
        local k = math.min(dt / PILLAR.appear, 1)
        pillar_set(k, k)
        if k >= 1 then pillar_phase("grow") end
    elseif pillar.phase == "grow" then                     -- 伸长一倍
        local k = math.min(dt / PILLAR.grow, 1)
        local e = k * k * (3 - 2 * k)
        pillar_set(1 + (PILLAR.grow_to - 1) * e, 1)
        if k >= 1 then pillar_phase("hold") end
    elseif pillar.phase == "hold" then                     -- 纳刀期间保持
        pillar_set(PILLAR.grow_to, 1)
        if drawn then pillar_phase("draw_pending") end
    elseif pillar.phase == "draw_pending" then             -- 识别拔刀方式
        pillar_set(PILLAR.grow_to, 1)
        local bank, mid = current_motion()
        if bank == "20" and SPIRIT_MOTIONS[mid] then
            pillar_phase("draw_hold")                      -- 大居合: 保持 1s
        elseif dt >= PILLAR.pending or not drawn then
            pillar_destroy()                               -- 小居合/普通拔刀: 移除
        end
    elseif pillar.phase == "draw_hold" then                -- 大居合后保持 1s
        pillar_set(PILLAR.grow_to, 1)
        if dt >= PILLAR.draw_hold then pillar_phase("fade") end
    elseif pillar.phase == "fade" then                     -- 淡出销毁
        local k = 1 - math.min(dt / PILLAR.fade, 1)
        pillar_set(PILLAR.grow_to * k * k, k * k)
        if k <= 0 then pillar_destroy() end
    end
end

-- ==========================================================================
-- 5. STATE MACHINE + FRAME LOOP
-- ==========================================================================
local enabled = false
local state = nil          -- "sheathed" | "drawn" | nil
local live = {}
local hunter_id = nil
local POLL_SECONDS = 0     -- every frame: snappy transitions, cheap field read

local function despawn_all()
    for _, entry in pairs(live) do
        pcall(function() entry.mesh:call("set_Enabled", false) end)
        pcall(function() entry.object:call("destroy", entry.object) end)
    end
    live = {}
end

local function remove_stale()
    local hunter = hunter_character()
    local object = hunter and call(hunter, "get_GameObject")
    local root = object and call(object, "get_Transform")
    if not root then return end
    local stack, visited, stale = {root}, {}, {}
    while #stack > 0 do
        local transform = table.remove(stack)
        local key = tostring(transform)
        if not visited[key] then
            visited[key] = true
            local child_object = call(transform, "get_GameObject")
            local name = tostring(call(child_object, "get_Name") or "")
            if name:sub(1, #PREFIX) == PREFIX then
                stale[#stale + 1] = child_object
            end
            local child = call(transform, "get_Child")
            while child do
                stack[#stack + 1] = child
                child = call(child, "get_Next")
            end
        end
    end
    for _, stale_object in ipairs(stale) do
        pcall(function() stale_object:call("destroy", stale_object) end)
    end
end

local function apply_state(new_state)
    despawn_all()
    for _, mount in ipairs(MOUNTS[new_state] or {}) do
        local part = find_weapon_part(mount.part)
        if part then
            local entry = spawn_mount(mount, part)
            if entry then live[mount.name] = entry end
        end
    end
    state = new_state
end

re.on_frame(function()
    if not enabled then return end
    local now = os.clock()

    local hunter = hunter_character()
    if not hunter then return end
    local current_id = tostring(call(call(hunter, "get_GameObject"), "get_Address")
        or tostring(hunter))
    if current_id ~= hunter_id then       -- hunter rebuilt (zone change etc.)
        hunter_id = current_id
        state = nil
        pillar_destroy()
        remove_stale()
    end

    local drawn = weapon_is_drawn()
    if drawn == nil then return end
    local want = drawn and "drawn" or "sheathed"
    local sheathe_transition = (want == "sheathed" and state ~= nil
        and state ~= "sheathed")
    if want ~= state then apply_state(want) end
    pillar_update(now, drawn, sheathe_transition)
end)

-- ==========================================================================
-- 6. UI + lifecycle
-- ==========================================================================
re.on_script_reset(function()
    despawn_all()
    pillar_destroy()
end)

re.on_draw_ui(function()
    if imgui.tree_node(TITLE) then
        local changed, requested = imgui.checkbox(
            "Enable (attach to equipped weapon)", enabled)
        if changed then
            enabled = requested == true
            if not enabled then
                despawn_all()
                pillar_destroy()
                state = nil
                hunter_id = nil
            else
                remove_stale()   -- clear leftovers before (re)enabling
            end
        end
        imgui.text("State: " .. (state or
            (enabled and "waiting for local hunter..." or "disabled")))
        if pillar then
            imgui.text("Pillar: " .. pillar.phase)
        end
        imgui.tree_pop()
    end
end)

-- TODO before shipping (plan doc):
--  * per-weapon gating: validate equipped mesh path so only YOUR weapon
--    triggers (is_hcl_ryujin_path-style check from hcl_ryujin.lua);
--  * pillar spawn currently fires on ANY sheathe transition -> gate on
--    motion 249 (special sheathe) if it should be special-sheathe-only;
--  * UV scroll driver for gold_film (mdf2 flow params / script pulse);
--  * capture the small-iai motion ID in training if explicit handling is
--    needed (the else branch already covers it correctly).
