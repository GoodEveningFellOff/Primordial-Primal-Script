math.clamp=function(a,b,c)return(a<b)and b or(a>c)and c or a end;



--* FFI elements
local ffi = require("ffi")
ffi.cdef([[
	
	typedef struct {
        uint8_t r;
        uint8_t g;
        uint8_t b;
        uint8_t a;
    } color_t;

    typedef struct { 
        char __pad_0x0000[0x1cd];
        bool bHideViewModelZoomed; 
    } WeaponInfo_t;

	typedef void (__cdecl* ConsoleColorPrintf)(void*,const color_t&, const char*, ...);

	typedef void* (*get_interface_fn)();
	
    typedef struct {
        get_interface_fn get;
        char* name;
        void* next;
    } interface;	
]]);

-- Better Create Interface Functions
local GetModuleHandle = ffi.cast("void*(__stdcall*)(const char*)",ffi.cast("uint32_t**", ffi.cast("uint32_t", memory.find_pattern("engine.dll", " FF 15 ? ? ? ? 85 C0 74 0B")) + 2)[0][0])
local GetProcAddress = ffi.cast("void*(__stdcall*)(void*, const char*)",ffi.cast("uint32_t**", ffi.cast("uint32_t", memory.find_pattern("engine.dll", " FF 15 ? ? ? ? A3 ? ? ? ? EB 05")) + 2)[0][0])

local function BetterCreateInterface(module, interface_name)
    local ModuleInterface = ffi.cast("int", GetProcAddress(GetModuleHandle(module), "CreateInterface"))
    local interface = ffi.cast("interface***", ModuleInterface + ffi.cast("int*", ModuleInterface + 5)[0] + 15)[0][0];
    while interface~=ffi.NULL do 
		if ffi.string(interface.name):match(interface_name.."%d+") then return interface.get() end 
		interface = ffi.cast("interface*", interface.next) ;
	end
end

local VEngineClient = ffi.cast(ffi.typeof("void***"), BetterCreateInterface("engine.dll", "VEngineClient")) or error("VEngineClient Not Found!!!")
local VEngineCvar = ffi.cast(ffi.typeof("uintptr_t**"), BetterCreateInterface("vstdlib.dll", "VEngineCvar")) or error("VEngineCvar Not Found!!!")

local pLocal = nil;
local Alive =  false; 
local Prev_Now, Load_Time, Now = 0, globals.real_time(), 0;
local TickCount = 0;
local CurTime = 0;
local MenuOpen = false;
local ScreenSize = {
	full=render.get_screen_size();
}
ScreenSize.console = ScreenSize.full*vec2_t(0.5,0.75);
ScreenSize.warning = ScreenSize.full*vec2_t(0.5,0.05);

local wasInGame = false;
local m_bIsScoped, Velocity = 0, 0;
local FL_ONGROUND, FL_DUCKING = 0, 0;
local WeaponIsRevolver = false;
local LastPunchAngle = angle_t(0,0,0);
local LocalEyePos = vec3_t(0,0,0);

local PaintTick = 0;

local function getTime()return math.floor((globals.real_time()*1000)-Load_Time*1000)end

local HITGROUPS = {[0] = "generic"; "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", "generic", "gear"};


local FONTS = {
    [0] = render.create_font("Arial", 14, 650, e_font_flags.DROPSHADOW);
	[1] = render.create_font("Tahoma", 20, 700, e_font_flags.ANTIALIAS);
};



local MENU = {
    AIMBOT = {
		ENABLE=menu.find("aimbot", "general", "aimbot", "enable")[2];
		DOUBLETAP=menu.find("aimbot", "general", "exploits", "doubletap", "enable")[2];
		HIDESHOTS=menu.find("aimbot", "general", "exploits", "hideshots", "enable")[2];
    };

    ANTIAIM = {
		ENABLE = menu.find("antiaim", "main", "general", "enable")[2];
	
		MANUAL_DISABLE_JITTER = menu.find("antiaim", "main", "manual", "disable jitter");
		MANUAL_DISABLE_ROTATE = menu.find("antiaim", "main", "manual", "disable rotate");
		FREESTANDING_DISABLE_JITTER = menu.find("antiaim", "main", "auto direction", "disable jitter");
		FREESTANDING_DISABLE_ROTATE = menu.find("antiaim", "main", "auto direction", "disable rotate");
	
		INVERT_DESYNC = menu.find("antiaim", "main", "manual", "invert desync")[2];
		INVERT_BODY_LEAN = menu.find("antiaim", "main", "manual", "invert body lean")[2];
		AUTO_DIRECTION = menu.find("antiaim", "main", "auto direction", "enable")[2];
	
		PITCH = menu.find("antiaim", "main", "angles", "pitch");
		YAW = menu.find("antiaim", "main", "angles", "yaw base");
		YAW_ADD = menu.find("antiaim", "main", "angles", "yaw add");
		ROTATE = menu.find("antiaim", "main", "angles", "rotate");
		ROTATE_RANGE = menu.find("antiaim", "main", "angles", "rotate range");
		ROTATE_SPEED = menu.find("antiaim", "main", "angles", "rotate speed");
		JITTER_MODE = menu.find("antiaim", "main", "angles", "jitter mode");
		BODY_LEAN = menu.find("antiaim", "main", "angles", "body lean");
		BODY_LEAN_VALUE = menu.find("antiaim", "main", "angles", "body lean value");
		MOVING_BODY_LEAN = menu.find("antiaim", "main", "angles", "moving body lean");
	
		SIDE = menu.find("antiaim", "main", "desync", "side#stand");
		DEFAULT_SIDE = menu.find("antiaim", "main", "desync", "default side#stand");
		LEFT_AMOUNT = menu.find("antiaim", "main", "desync", "left amount#stand");
		RIGHT_AMOUNT = menu.find("antiaim", "main", "desync", "right amount#stand");
		ANTI_BRUTEFORCE = menu.find("antiaim", "main", "desync", "anti bruteforce");
		ON_SHOT = menu.find("antiaim", "main", "desync", "on shot");
	
		OVERRIDE_STAND_1 = menu.find("antiaim", "main", "desync", "override stand#move");
		OVERRIDE_STAND_2 = menu.find("antiaim", "main", "desync", "override stand#slow walk");
	
		FAKELAG = menu.find("antiaim", "main", "fakelag", "amount");
		BREAK_LC = menu.find("antiaim", "main", "fakelag", "break lag compensation");
    };

	VISUALS = {
		VISUAL_RECOIL = menu.find("visuals", "view", "removals", "visual recoil");
	};

    MISC = {
        ACCENT = menu.find("misc", "main", "personalization", "accent color")[2];
    };
};

local UI = {
	TABS = menu.add_selection(" Tabs", " ", {"Home", "AntiAim", "Visuals"});

	HOME = {
		RCS = menu.add_checkbox("Home -> SemiLegit", "\"Silent\" Rcs");
		BACKTRACK = menu.add_checkbox("Home -> SemiLegit", "Backtrack")
	};

    ANTIAIM = {
        ANTIAIM_SECTION = menu.add_selection("AntiAim -> Main", "Category", {"Global", "Standing", "Crouching", "Moving", "Jumping", "Freestand / Manual / On Use", "Antibrute 1", "Antibrute 2", "Antibrute 3", "Antibrute 4", "Antibrute 5", "Antibrute 6", "Antibrute 7", "Antibrute 8"});
        ANTIAIM_OVERRIDE = menu.add_multi_selection("AntiAim -> Main", "Override Global", {"Standing", "Crouching", "Moving", "Jumping", "Freestand / Manual / On Use"});
		PREVIEW = menu.add_checkbox("AntiAim -> Main", "Preview Group", false);

        SPACER = menu.add_text("AntiAim -> Main", " ");
		PITCH = menu.add_selection("AntiAim -> Main", "Pitch", {"None", "Down", "Up", "Zero", "Jitter"});
		YAW = menu.add_selection("AntiAim -> Main", "Yaw Base", {"None", "Viewangle", "At Target (Crosshair)", "At Target (Distance)", "Velocity"});
	    MISC = menu.add_multi_selection("AntiAim -> Main", "Misc Options", {"Enable Roll", "Defensive Flicking", "Zero Pitch on Freestand", "Edge Yaw"});
		ANTIBRUTE = menu.add_slider("AntiAim -> Main", "Antibrute Phases", 0, 8, 1, 0);
	    

		FAKELAG_KEY = nil;
		FAKELAG_LIM = menu.add_slider("AntiAim -> Fakelag", "Limit", 0, 14, 1, 0, "t");
		FAKELAG_VAR = menu.add_slider("AntiAim -> Fakelag", "Variance", 0, 100, 1, 0, "%");
		DISABLE_ON_REVOLVER = menu.add_checkbox("AntiAim -> Fakelag", "Disable with Revolver");
        BREAK_LC = menu.add_checkbox("AntiAim -> Fakelag", "Break Lag Compensation");

        [1]={};[2]={};[3]={};[4]={};[5]={};[6]={};[7]={};[8]={};[9]={};[10]={};[11]={};[12]={};[13]={};[14]={};
		
		set_visible=function(self, b)
			menu.set_group_visibility("AntiAim -> Main", b)
			menu.set_group_visibility("AntiAim -> Fakelag", b)

			if b then
				local a=self.ANTIAIM_SECTION:get();
				for i=1,14 do self[i].set_visible(a==i)end
				return
			end

			for i=1,14 do self[i].set_visible(false)end
		end;
    };

	VISUALS = {
        MISC = menu.add_multi_selection("Visuals -> Main", "Misc", {"Scoped Viewmodel", "Party Mode", "Zero Pitch when Landing"});
        SKIN = menu.add_selection("Visuals -> Main", "Skin", {"Black", "Mixed", "White", "Tanned", "Tattooed", "Brown"});
		spacer_m = menu.add_text("Visuals -> Main", " ");
		LAND_LEGS = menu.add_selection("Visuals -> Main", "Land Leg Movement", {"Normal", "Force Walk", "Force Slide"});
		AIR_LEGS = menu.add_selection("Visuals -> Main", "Air Leg Movement", {"Normal", "Force Land Anim", "Static Legs"});
		MOVE_YAW = menu.add_selection("Visuals -> Main", "Move Yaw Modification", {"Normal", "Reversed", "Static"});

        REMOVALS = menu.add_multi_selection("Visuals -> Performance", "Removals", {"Panorama Blur", "Shadows", "Crosshair", "Log Glow", "Custom Hitmarkers"});
		FARZ = menu.add_slider("Visuals -> Performance", "Far Z", 0, 2000, 1, 0, "u");

        LOG = menu.add_multi_selection("Visuals -> Indication", "Log", {"Aimbot Hit", "Aimbot Miss", "Extra Aimbot Info", "Enemy Purchases"});


        set_visible=function(self, b)
			menu.set_group_visibility("Visuals -> Main", b)
			menu.set_group_visibility("Visuals -> Performance", b)
			menu.set_group_visibility("Visuals -> Indication", b)
        end;
    };
};



-->> START EXTRA UI CREATION SECTION <<--



menu.add_text("Home -> Log", "Welcome " .. tostring(user.name))
menu.add_text("Home -> Log", "")
menu.add_text("Home -> Log", "- Use standalone backtrack with fake")
menu.add_text("Home -> Log", "	ping for longer backtrack history.")
menu.add_text("Home -> Log", "	*Wont work in legit mode*")
menu.add_text("Home -> Log", "")
menu.add_text("Home -> Log", "- Semirage rcs looks \"semi-legit\" and")
menu.add_text("Home -> Log", "	if Removals->Visual Recoil is")
menu.add_text("Home -> Log", "	enabled rcs wont be silent.")
menu.add_text("Home -> Log", "	*Wont work in legit mode*")



UI.ANTIAIM.FAKELAG_KEY = UI.ANTIAIM.FAKELAG_LIM:add_keybind("Enable Fakelag")

local function GenerateAntiAimGroup(name)
    -- Create a blank table to store our items
    local tbl = {};

    -- Create the yaw options for this group
    tbl.YAW_ADD = menu.add_slider("AntiAim -> "..name.." Yaw", "Yaw Add", -180, 180, 1, 0, "°");
    tbl.JITTER_OFFSET = menu.add_slider("AntiAim -> "..name.." Yaw", "Jitter Offset", -90, 90, 1, 0, "°");
    tbl.RANDOM_OFFSET = menu.add_slider("AntiAim -> "..name.." Yaw", "Random Offset", 0, 90, 1, 0, "°")
    SPACER = menu.add_text("AntiAim -> "..name.." Yaw", " ");
    tbl.ROTATE_RANGE = menu.add_slider("AntiAim -> "..name.." Yaw", "Rotate Range", 0, 360, 1, 0, "°");
    tbl.ROTATE_SPEED = menu.add_slider("AntiAim -> "..name.." Yaw", "Rotate Speed", 1, 100, 1, 0, "%")

    -- Create the fake options for this group
    tbl.FAKE_OPTIONS = menu.add_multi_selection("AntiAim -> "..name.." Fake", "Options", {"Peek Fake (priority)", "Peek Real", "Jitter", "Random Jitter"});
    tbl.DESYNC_LIM = menu.add_slider("AntiAim -> "..name.." Fake", "Desync Limit", 0, 100, 1, 0, "%");
    tbl.DESYNC_VAR = menu.add_slider("AntiAim -> "..name.." Fake", "Desync Variance", 0, 100, 1, 0, "%");
    tbl.ROLL_LIM = menu.add_slider("AntiAim -> "..name.." Fake", "Roll Limit", -100, 100, 1, 0, "%");
    tbl.ROLL_VAR = menu.add_slider("AntiAim -> "..name.." Fake", "Roll Variance", 0, 100, 1, 0, "%");

    tbl.set_visible = function(b)
        menu.set_group_visibility("AntiAim -> "..name.." Yaw", b)
        menu.set_group_visibility("AntiAim -> "..name.." Fake", b)
    end;

    return tbl
end;

for i, name in pairs({
    "Global",
    "Standing",
    "Crouching",
    "Moving",
    "Jumping",
    "Manual",
	"Antibrute 1",
	"Antibrute 2",
	"Antibrute 3",
	"Antibrute 4",
	"Antibrute 5",
	"Antibrute 6", 
	"Antibrute 7",
	"Antibrute 8"
}) do UI.ANTIAIM[i]=GenerateAntiAimGroup(name); end

GenerateAntiAimGroup=nil;
-->> STOP EXTRA UI CREATION SECTION <<--



local animator = {
	defined={};vars={};frametime=1;

	new = function(self, name, init_val, speed, stop_delta, max_lerp)
		stop_delta=stop_delta or 0.01; 
		max_lerp=math.clamp(max_lerp or 1, 0, 1)

		local vars=self.vars;
		vars[name]=init_val;

		self.defined[name]=function(goal)
			local cur=vars[name];
			local delta=goal-cur;

			local cur=(math.abs(delta)<stop_delta) and goal or (cur+delta * math.clamp(self.frametime*speed, 0, max_lerp));

			vars[name]=cur;

			return cur
		end;

		return self.defined[name]
	end;
};

animator:new("alive", 1, 15);



local cvarOverride={
	last = 0;
	in_scope_active = false;

	weapon_info_location = ffi.cast("void****", memory.find_pattern("client.dll", "8B 35 ?? ?? ?? ?? FF 10 0F B7 C0") + 2)[0];
	get_weapon_info = nil;
	

	set_in_scope_viewmodel = function(self, b)
		self.in_scope_active = b;

		local get, loc, b = self.get_weapon_info, self.weapon_info_location, not b
		get(loc, 9).bHideViewModelZoomed = b; -- Awp
		get(loc, 11).bHideViewModelZoomed = b; -- G3sg1
		get(loc, 38).bHideViewModelZoomed = b; -- Scar20
		get(loc, 40).bHideViewModelZoomed = b; -- SSG08
	end;

	constants = function()
		cvars.viewmodel_recoil:set_int(1)

		cvars.r_drawropes:set_int(0)

		cvars.cl_interp_ratio:set_float(0) 
		cvars.cl_updaterate:set_float(0) 
    	cvars.cl_interp:set_float(0)

		cvars.weapon_recoil_view_punch_extra:set_float(0)

		cvars.view_recoil_tracking:set_float(1)
	end;

	update = function(self, in_menu, force)
		if Now-self.last < (in_menu and 500 or 60000) and not force then return end
		
		self.last = Now;

		self.constants()

		local REMOVALS, MISC = UI.VISUALS.REMOVALS, UI.VISUALS.MISC;

		cvars["@panorama_disable_blur"]:set_int(REMOVALS:get(1) and 1 or 0)
    	
    	cvars.crosshair:set_int(REMOVALS:get(3) and 0 or 1)
    	cvars.cl_csm_shadows:set_int(REMOVALS:get(2) and 0 or 1)
		cvars.r_farz:set_int(UI.VISUALS.FARZ:get())
		cvars.sv_party_mode:set_int(MISC:get(2) and 1 or 0)
		cvars.r_skin:set_int(UI.VISUALS.SKIN:get())

		local in_scope = MISC:get(1);
		if in_menu and not force then
			if self.in_scope_active ~= in_scope then 
				self:set_in_scope_viewmodel(in_scope)
			end

			return
		end
		self:set_in_scope_viewmodel(in_scope)
	end;
};

cvarOverride.get_weapon_info = ffi.cast(ffi.typeof("WeaponInfo_t *(__thiscall*)(void*, unsigned int)"), (ffi.cast("void***", cvarOverride.weapon_info_location)[0])[2]);




local vguiConsole={
    printf_cast = ffi.cast("ConsoleColorPrintf", VEngineCvar[0][25]);

    get_is_open = ffi.cast("bool(__thiscall*)(void*)", VEngineClient[0][11]);
    was_open = false;

    materials = {
        materials.find("vgui_white"),
        materials.find("vgui/hud/800corner1"), 
        materials.find("vgui/hud/800corner2"),
        materials.find("vgui/hud/800corner3"),
        materials.find("vgui/hud/800corner4")
    };

    modulate = function(self)
        local is_open = self.get_is_open(VEngineClient);

        if is_open then
            local clr = MENU.MISC.ACCENT:get();
            local r, g, b = clr.r/255, clr.g/255, clr.b/255;

            for _,mat in pairs(self.materials) do
                mat:color_modulate(r, g, b)
                mat:alpha_modulate(0.66)
            end

        elseif self.was_open then
            for _,mat in pairs(self.materials) do
                mat:color_modulate(1, 1, 1)
                mat:alpha_modulate(1)
            end
        end

        self.was_open = is_open;
    end;

    print = function(self, ...)
        local printf, tbl = self.printf_cast, {...}
        
        for idx=1, math.floor(#tbl/2) do 
            local group_offset = (idx-1)*2

            local clr=tbl[group_offset+1];

            local cclr=ffi.new("color_t");
            cclr.r, cclr.g, cclr.b, cclr.a = clr.r, clr.g, clr.b, clr.a;

            printf(VEngineCvar, cclr, tostring(tbl[group_offset+2])) 
        end 

        local cclr = ffi.new("color_t");
        cclr.r, cclr.g, cclr.b, cclr.a = 0, 0, 0, 255;
        printf(VEngineCvar, cclr, "\n")
    end;
}; 



local devConsole = {
    queue = {};
    max_size = 8;

    push = function(self)
        local queue = self.queue;

        for i=1, self.max_size do
            if queue[i+1] then 
                queue[i], queue[i+1] = queue[i+1],nil; 
            end 
        end
    end;

    render = function(self)
        local queue, line, glow_enabled, screen_pos = self.queue, 0, not UI.VISUALS.REMOVALS:get(4), ScreenSize.console;
		
        for idx, this in pairs(queue) do 
            if this then 
                if this[1]+10000<Now then queue[idx]=nil; else

                    local fl = math.clamp((this[1]-Now+10000)/500,0,1); -- fade in / out value, between 0 and 1
                    this[2](screen_pos+vec2_t(0,line-96),fl, glow_enabled) line=line+24*fl; -- render the line and increment the linecount
                end 
            end 
        end

        if not queue[1] and line>0 then self:push() end
    end;

	create_new_line = (function(font,...)
		local data, curpos, tbl = {}, 0, {...};
		local tbl_len = math.floor(#tbl/2)
		
		-- Collect the data from the main section and return a filled data element, each data index will contain {X offset, color, string, original alpha}
		for idx=1, tbl_len do 
			local this = (idx-1)*2;
			local ts = render.get_text_size(font, tbl[this+2])
			data[idx], curpos = {curpos, tbl[this+1], tbl[this+2], tbl[this+1].a}, curpos+ts.x;
	
			if idx==1 then
				data[idx][5] = function(pos, clr)
					local clr_1, clr_2 = color_t(clr.r, clr.g, clr.b, math.floor(0.5*clr.a)), color_t(127, 127, 127, 0)
					render.rect_fade(pos-vec2_t(2, 3), vec2_t(ts.x+2, 3), clr_2, clr_1)
					render.rect_fade(pos+vec2_t(-2, ts.y+2), vec2_t(ts.x+2, 3), clr_1, clr_2)
					render.rect_fade(pos-vec2_t(4, 1), vec2_t(3, ts.y+4), clr_2, clr_1, true)
				end
			elseif idx==tbl_len then
				data[idx][5] = function(pos, clr)
					local clr_1, clr_2 = color_t(clr.r, clr.g, clr.b, math.floor(0.5*clr.a)), color_t(127, 127, 127, 0)
					render.rect_fade(pos-vec2_t(0, 3), vec2_t(ts.x+2, 3), clr_2, clr_1)
					render.rect_fade(pos+vec2_t(0, ts.y+2), vec2_t(ts.x+2, 3), clr_1, clr_2)
					render.rect_fade(pos+vec2_t(ts.x+1, -1), vec2_t(3, ts.y+4), clr_1, clr_2, true)
				end
			else
				data[idx][5] = function(pos, clr)
					local clr_1, clr_2 = color_t(clr.r, clr.g, clr.b, math.floor(0.5*clr.a)), color_t(127, 127, 127, 0)
					render.rect_fade(pos-vec2_t(0, 3), vec2_t(ts.x, 3), clr_2, clr_1)
					render.rect_fade(pos+vec2_t(0, ts.y+2), vec2_t(ts.x, 3), clr_1, clr_2)
				end
			end
		end
	
		local offset=vec2_t(curpos*0.5,0);
	
		--Final function, should have better preformance than just doing it manually
		return function(pos,alpha,glow)
			local pos = pos-offset;
			for idx,this in pairs(data)do 
				this[2].a=math.floor(this[4]*alpha);
				render.text(font,this[3],pos+vec2_t(this[1],0),this[2])

				if glow then this[5](pos+vec2_t(this[1], 0), this[2]) end
			end 
		end
	end);

	filter_name = function(name)
		local name = tostring(name or ""):gsub("\n", "");

		if name:len() > 24 then
			name = name:sub(1, 21) .. "...";
		end
		
		return name
	end;

    print = function(self, ...)
        local queue, print_csgo_console = self.queue, self.print_csgo_console;

        if #queue>=self.max_size then self:push() end

        queue[#queue+1] = {
            getTime(), 
            self.create_new_line(FONTS[0],...)
        };

        vguiConsole:print(...)
    end;
};



local hitmarkerOverride = {
	log = {};
	latest = "";
	latest_time = 0;
	damage_func = nil;

	offset_vectors = {
		{vec2_t(3,3),vec2_t(8,8)}, 
		{vec2_t(-3,-3),vec2_t(-8,-8)}, 
		{vec2_t(3,-3),vec2_t(8,-8)}, 
		{vec2_t(-3,3),vec2_t(-8,8)}
	};

	new = function(clr, str)
		return function(alpha, pos)
			clr.a=math.floor(255*alpha);
			render.text(FONTS[1], tostring(str), pos-vec2_t(0, 20), clr, true)
		end
	end;

	render = function(self, pos, str, alpha, dmg, headshot)
		local log=self.log;

		-- Alpha may roll back to a number that is higher than 0.003 for 1 frame
		if alpha<0.01 then log[str]=nil;return end
		if not log[str] then log[str],self.latest,self.latest_time,self.damage_func=true,str,CurTime,self.new(headshot and color_t(255,55,55) or color_t(255,255,255),tostring(dmg));end
		if self.latest==str then pcall(self.damage_func,(CurTime-self.latest_time<0.3) and 1 or alpha,pos)end

		-- Render the cross
		render.push_alpha_modifier(alpha)
		local clr1, clr3 = color_t(255,255,255), color_t(0,0,0);
		for _, this in pairs(self.offset_vectors) do
			local inner, outer = pos+this[1], pos+this[2];

			render.line(inner-vec2_t(1,0), outer-vec2_t(1,0), clr3)
			render.line(inner+vec2_t(1,0), outer+vec2_t(1,0), clr3)
			render.line(inner-vec2_t(0,1), outer+vec2_t(0,1), clr3)
			render.line(inner, outer, clr1)
		end
		render.pop_alpha_modifier()
	end;
};



local legitBacktrack = {
	history = {};

	get_fov = function(start, goal)
		local delta=start-goal;
		local angles = ViewAngles-m_aimPunchAngle
		local deg = 180/math.pi;
	
		local x = math.atan(delta.z/math.sqrt(delta.x^2+delta.y^2))*deg - angles.x;
		if(x<-180)then x=x+360;end if(x>180)then x=x-360;end 
	
		local y = (math.atan(delta.y/delta.x)*deg)+((delta.x>=0)and 180 or 0) - angles.y;
		if(y<-180)then y=y+360;end if(y>180)then y=y-360;end 
	
		return math.min(math.sqrt(math.clamp(x, -89, 89)^2 + y^2), 180) 
	end;

	-- Made it look like shit because i am in fact racist
	run = function(self, cmd, ep)
		local pList=entity_list.get_players(true);if not pList then return end
		local cp,cf,get_fov,history=nil,180,self.get_fov,self.history;
		for _,p in pairs(pList)do local i=p:get_index();if not history[i] then history[i]={};end if not p:is_alive()then history[i]={};else local h=history[i];for t=22,0,-1 do if h[t] then h[t+1]=h[t];end end local hp=p:get_hitbox_pos(e_hitboxes.HEAD);h[0]={hp, p:get_prop("m_flSimulationTime")};local a=get_fov(ep,hp);if a<cf then cp,cf=p,a;end end end
		if MENU.AIMBOT.ENABLE:get()or not menu.is_rage()then return end
		if not cp or not cmd:has_button(e_cmd_buttons.ATTACK)or cvars.cl_lagcompensation:get_int()==0 or not client.can_fire()then return end
		cf,br,h=180,nil,history[cp:get_index()];if not h then return end
		local dt,time_offset=math.floor(CurTime-cvars.sv_maxunlag:get_float()),0;

		for t=0,math.clamp(11+math.clamp(client.time_to_ticks(engine.get_latency(e_latency_flows.INCOMING)),0,11),0,22-client.time_to_ticks(engine.get_latency(e_latency_flows.OUTGOING))) do 
			local r=h[t];
			if r then 
				if t==0 then
					time_offset=TickCount-client.time_to_ticks(r[2])
				end

				if r[2]>dt then 
					local a=get_fov(ep,r[1]);
					if a<cf then 
						cf,br=a,r;
					end 
				end
			end 
		end

		if br then 
			--debug_overlay.add_sphere(br[1], 5, 20, 5, color_t(255, 255, 255), 4.0)
			cmd.tick_count=client.time_to_ticks(br[2]+globals.interpolation_amount())+time_offset;
		end 
	end;
};



local AntiAim = {
	ENABLED = false;
	INVERTER = false;
	FAKE_INVERTER = false;
	GROUP = 1;
	FLICK_TICK = 0;
	JUMP_COUNTER = 0;
	EDGE = false;

	groups = {
		"Global",
		"Standing",
		"Crouching",
		"Moving",
		"Jumping",
		"Manual",
		"Antibrute 1",
		"Antibrute 2",
		"Antibrute 3",
		"Antibrute 4",
		"Antibrute 5",
		"Antibrute 6", 
		"Antibrute 7",
		"Antibrute 8"
	};

	antibrute = {
		tick = 0;
		stage = 0;
	};

	override_animations = function(self, ctx)
		if (FL_ONGROUND < 0 and FL_ONGROUND >= -64) and UI.VISUALS.MISC:get(2) then ctx:set_render_pose(e_poses.BODY_PITCH, 0.45) end

		local LAND_LEGS, AIR_LEGS, MOVE_YAW = UI.VISUALS.LAND_LEGS:get(), UI.VISUALS.AIR_LEGS:get(), UI.VISUALS.MOVE_YAW:get();
		local move_yaw, move, strafechange = pLocal:get_prop("m_flPoseParameter", 7), pLocal:get_prop("m_flPoseParameter", 3), (LAND_LEGS==2) and 0 or (LAND_LEGS==3) and 1 or nil;
		
		if strafechange then strafechange=strafechange*move;end

		move_yaw = (MOVE_YAW==2) and move_yaw+0.5 or(MOVE_YAW==3)and 0 or move_yaw;
		if move_yaw>1 then move_yaw=move_yaw-1 end

		ctx:set_render_pose(e_poses.MOVE_YAW, move_yaw) 
		ctx:set_render_pose(e_poses.STRAFE_DIR, move_yaw)


		if FL_ONGROUND>=0 then
			if AIR_LEGS==2 then 
				ctx:set_render_animlayer(e_animlayers.MOVEMENT_MOVE, move, -1)
				ctx:set_render_animlayer(e_animlayers.MOVEMENT_STRAFECHANGE, strafechange, -1)
			elseif AIR_LEGS==3 then ctx:set_render_pose(e_poses.JUMP_FALL,(self.JUMP_COUNTER==3)and 1 or self.JUMP_COUNTER*0.25)end

			return
		end

		ctx:set_render_animlayer(e_animlayers.MOVEMENT_STRAFECHANGE, strafechange, -1)
	end;

	disable_defaults = function(self)
		local MENU = MENU.ANTIAIM;

		MENU.JITTER_MODE:set(1)
		MENU.ROTATE:set(true)
		MENU.MANUAL_DISABLE_JITTER:set(false)
		MENU.MANUAL_DISABLE_ROTATE:set(false)
		MENU.FREESTANDING_DISABLE_JITTER:set(false)
		MENU.FREESTANDING_DISABLE_ROTATE:set(false)
		MENU.ANTI_BRUTEFORCE:set(false)
		MENU.OVERRIDE_STAND_1:set(false)
		MENU.OVERRIDE_STAND_2:set(false)
	end;

	fakelag = function(self)
		local MENU, UI = MENU.ANTIAIM, UI.ANTIAIM;
		
		if (WeaponIsRevolver and UI.DISABLE_ON_REVOLVER:get()) or not UI.FAKELAG_KEY:get() then
			MENU.FAKELAG:set(MENU.ENABLE:get() and 1 or 0)
			MENU.BREAK_LC:set(false)
			return
		end

		if engine.get_choked_commands() ~= 0 then return end

		local lim = UI.FAKELAG_LIM:get();

		MENU.FAKELAG:set(lim-math.floor(math.random(0, UI.FAKELAG_VAR:get())*(lim-1)*0.01))
		MENU.BREAK_LC:set(UI.BREAK_LC:get())
	end;
	
	pitch = function(self, ctx)
		local UI = UI.ANTIAIM;
		local UI_PITCH = UI.PITCH:get()
		local MENU_PITCH = MENU.ANTIAIM.PITCH

		-- TODO, dont set to 4 if enemy is vis
		if Velocity>=10 and not antiaim.is_fakeducking() then
			if UI.MISC:get(3) and MENU.ANTIAIM.AUTO_DIRECTION:get() then
				MENU_PITCH:set(4)
				return
			end
			
			if UI.MISC:get(2) and (MENU.AIMBOT.DOUBLETAP:get() or MENU.AIMBOT.HIDESHOTS:get()) and exploits.get_charge()>0 and math.abs(self.FLICK_TICK - TickCount) >= 16 then
				MENU_PITCH:set(3)
				self.FLICK_TICK = TickCount - math.random(0, 7);
				return
			end
		end
		
		MENU_PITCH:set(UI_PITCH)
	end;

	yaw = function(self)
		local edge, yaw = false, UI.ANTIAIM.YAW:get();

		if UI.ANTIAIM.MISC:get(4) and FL_ONGROUND<0 and yaw~=1 and not (MENU.ANTIAIM.AUTO_DIRECTION:get() or antiaim.get_manual_override()~=0) then 
			local ang,len=nil,1;for i=0,15 do
				local line=trace.line(LocalEyePos, LocalEyePos+angle_t(0,i*22.5,0):to_vector()*vec3_t(23,23,0),pLocal);if line.fraction<len then ang,len=i*22.5,line.fraction;end
			end if ang then edge=ang;end
		end
		
		MENU.ANTIAIM.YAW:set((edge) and 2 or yaw)

		self.EDGE=(edge) and (edge-ViewAngles.y+180) or false;
	end;

	render_warning = ((function()
		local font, pos = FONTS[0], ScreenSize.warning
		local lerped_func = animator:new("antiaim_warning", 0, 15);

		return function(self)
			local alpha = lerped_func(UI.ANTIAIM.PREVIEW:get() and 1 or 0)*animator.vars["alive"];

			if alpha == 0 then return end

			local text = "AntiAim group forced to \""..self.groups[UI.ANTIAIM.ANTIAIM_SECTION:get()].."\" for configuration";
			local text_size = render.get_text_size(font, text);
			local pos_a, pos_b = pos-text_size*vec2_t(0.5,0.5)-vec2_t(5, 5), text_size+vec2_t(10, 10);

			if alpha < 1 then
				render.push_alpha_modifier(alpha)
			else
				render.push_alpha_modifier(math.sin(CurTime*6)*0.33 + 0.67)
			end

			render.rect_filled(pos_a, pos_b, color_t(11, 11, 11, 155), 2)
			render.rect(pos_a, pos_b, color_t(255, 255, 255, 255), 2)
			render.text(font, text, pos, color_t(255, 255, 255, 255), true)

			render.pop_alpha_modifier()
		end
	end)());

	set = function(self, ctx, cmd)
		if engine.get_choked_commands() ~= 0 then return end

		local MENU, UI, GROUP = MENU.ANTIAIM, UI.ANTIAIM, UI.ANTIAIM[self.GROUP];

		self:pitch(ctx)
		self:yaw()
		self:disable_defaults()

		self.INVERTER = not self.INVERTER

		if GROUP.FAKE_OPTIONS:get(3) then
			if GROUP.FAKE_OPTIONS:get(4) then
				self.FAKE_INVERTER = math.random(0,1)==1;
			else
				self.FAKE_INVERTER = self.INVERTER;
			end
		else self.FAKE_INVERTER = MENU.INVERT_DESYNC:get();end

		local roll_lim, desync_lim = GROUP.ROLL_LIM:get(), GROUP.DESYNC_LIM:get();
		local roll, desync = math.floor((roll_lim-math.random(0, GROUP.ROLL_VAR:get())*roll_lim*0.01)*0.5), math.floor((desync_lim-math.random(0, GROUP.DESYNC_VAR:get())*desync_lim*0.01))
		local peek_fake = GROUP.FAKE_OPTIONS:get(1);
		local fake_freestand = (peek_fake or GROUP.FAKE_OPTIONS:get(2))
		local yaw, random_offset= GROUP.YAW_ADD:get(), GROUP.RANDOM_OFFSET:get();

		if self.EDGE then yaw=yaw+self.EDGE;end

		yaw=yaw+math.random(-random_offset, random_offset)+GROUP.JITTER_OFFSET:get()*(self.INVERTER and -1 or 1);
		if yaw>180 then yaw=yaw-360; elseif yaw<-180 then yaw=yaw+360;end

		MENU.MOVING_BODY_LEAN:set(roll ~= 0)
		MENU.BODY_LEAN:set((UI.MISC:get(1) and roll ~= 0) and 2 or 1)
		MENU.BODY_LEAN_VALUE:set(((antiaim.get_desync_side()==2 == MENU.INVERT_BODY_LEAN:get()) and 1 or -1)*roll)

		if desync == 0 then MENU.SIDE:set(1) else
			if fake_freestand then 
				MENU.SIDE:set((peek_fake == MENU.INVERT_DESYNC:get()) and 6 or 5) 
				MENU.DEFAULT_SIDE:set((self.FAKE_INVERTER == MENU.INVERT_DESYNC:get()) and 1 or 2)
			else
				MENU.SIDE:set((self.FAKE_INVERTER == MENU.INVERT_DESYNC:get()) and 2 or 3)
			end
			
			MENU.LEFT_AMOUNT:set(desync)
			MENU.RIGHT_AMOUNT:set(desync)
		end

		MENU.YAW_ADD:set(yaw)
		MENU.ROTATE_RANGE:set(GROUP.ROTATE_RANGE:get())
		MENU.ROTATE_SPEED:set(GROUP.ROTATE_SPEED:get())
	end;
};



-->> START CALLBACK REGISTRATION <<--
callbacks.add(e_callbacks.ANTIAIM, function(ctx, cmd, dat)
	AntiAim:override_animations(ctx)
	
	AntiAim:fakelag()

	AntiAim:set(ctx, cmd)
end)



callbacks.add(e_callbacks.NET_UPDATE, function()
	if not pLocal then 
		Alive = false; 
		AntiAim.antibrute.stage = 0;
		AntiAim.antibrute.tick = 0;
		return 
	end

	Alive=pLocal:is_alive()

	if not Alive then
		AntiAim.antibrute.stage = 0;
		AntiAim.antibrute.tick = 0;
	end
end)



callbacks.add(e_callbacks.SETUP_COMMAND, function(cmd)
	pLocal = entity_list:get_local_player();

    if not pLocal then return end

    m_bIsScoped = pLocal:get_prop("m_bIsScoped") == 1;

	local vecVelocity = pLocal:get_prop("m_vecVelocity");
	Velocity = math.sqrt(vecVelocity.x^2 + vecVelocity.y^2);

	local aim_punch = pLocal:get_prop("m_aimPunchAngle");
	m_aimPunchAngle = angle_t(aim_punch.x*2, aim_punch.y*2, 0)
	ViewAngles = engine.get_view_angles()
	LocalEyePos = pLocal:get_eye_position();

    if not pLocal:has_player_flag(e_player_flags.ON_GROUND) then FL_ONGROUND=((FL_ONGROUND<2) and 2 or FL_ONGROUND+1); elseif FL_ONGROUND>-65 then FL_ONGROUND=(FL_ONGROUND>2) and 1 or FL_ONGROUND-1; end
    if pLocal:has_player_flag(e_player_flags.DUCKING) then FL_DUCKING=2; elseif FL_DUCKING>-1 then FL_DUCKING=FL_DUCKING-1; end
	if FL_ONGROUND>0 then if cmd:has_button(e_cmd_buttons.JUMP)  and AntiAim.JUMP_COUNTER<3 then AntiAim.JUMP_COUNTER=AntiAim.JUMP_COUNTER+1;end else AntiAim.JUMP_COUNTER=0;end

	if UI.HOME.BACKTRACK:get() then
		legitBacktrack:run(cmd, LocalEyePos)
	end

	if menu.is_rage() then
		if UI.HOME.RCS:get() and not MENU.AIMBOT.ENABLE:get() then
			engine.set_view_angles((LastPunchAngle - m_aimPunchAngle) + ViewAngles); 
			LastPunchAngle = m_aimPunchAngle;
			MENU.VISUALS.VISUAL_RECOIL:set(false)

		else
			if LastPunchAngle.x ~= 0 or LastPunchAngle.y ~= 0 then
				engine.set_view_angles(m_aimPunchAngle + ViewAngles); 
				LastPunchAngle = angle_t(0,0,0);
			end

			MENU.VISUALS.VISUAL_RECOIL:set(true)
		end
	end

	if not AntiAim.ENABLED or AntiAim.antibrute.tick<TickCount or UI.ANTIAIM.ANTIBRUTE:get()==0 then
		AntiAim.antibrute.stage = 0;
		AntiAim.antibrute.tick = 0;
	end

	local Weapon = pLocal:get_active_weapon();
	if not Weapon then return end

	local WeaponData = Weapon:get_weapon_data(); 
	if not WeaponData then return end

	WeaponIsRevolver = e_items[(WeaponData.console_name):upper()] == 64;

	AntiAim.ENABLED = menu.is_rage() and MENU.ANTIAIM.ENABLE:get();

	if UI.ANTIAIM.PREVIEW:get() then
		AntiAim.GROUP = UI.ANTIAIM.ANTIAIM_SECTION:get();
		return
	end

	if AntiAim.antibrute.stage ~= 0 then
		AntiAim.GROUP = 6+AntiAim.antibrute.stage;
		return
	end

	local antiaim_group = (MENU.ANTIAIM.AUTO_DIRECTION:get() or antiaim.get_manual_override()~=0 or cmd:has_button(e_cmd_buttons.USE) or AntiAim.EDGE) and 6 or (FL_ONGROUND>0) and 5 or (FL_DUCKING>0) and 3 or (Velocity>10) and 4 or 2 
	AntiAim.GROUP = UI.ANTIAIM.ANTIAIM_OVERRIDE:get(antiaim_group-1) and antiaim_group or 1
end)



callbacks.add(e_callbacks.PAINT, function()
    Now=getTime();if Prev_Now>Now then Load_Time=Load_Time-(Prev_Now/1000);end Prev_Now=Now;

    CurTime = globals.cur_time();
	TickCount = globals.tick_count();

	MenuOpen = menu.is_open();
	animator.frametime = globals.frame_time();

	animator.defined["alive"](((pLocal and Alive) or MenuOpen) and 1 or 0)

    if MenuOpen then
        local TAB= UI.TABS:get();
		
		menu.set_group_visibility("Home -> SemiLegit", TAB==1)
		menu.set_group_visibility("Home -> Log", TAB==1)
		UI.ANTIAIM:set_visible(TAB==2)
		UI.VISUALS:set_visible(TAB==3)
		cvarOverride:update(true, false)

	else

		cvarOverride:update(false, false)
    end

	if PaintTick<Now then
		vguiConsole:modulate()

		PaintTick = Now+16;
	end

    devConsole:render()


	if not pLocal then return end


	AntiAim:render_warning()


    local InGame = engine.is_in_game();
    if InGame~=wasInGame then
        if not InGame then 
            pLocal=nil;
			Alive=false;
			AntiAim.antibrute.stage = 0;
			AntiAim.antibrute.tick = 0;
        end

		cvarOverride:update(false, true)
		wasInGame=InGame;
    end
end)



callbacks.add(e_callbacks.WORLD_HITMARKER, function(pos, world_pos, alpha, dmg, _, headshot)
	if UI.VISUALS.REMOVALS:get(5) then return false end

	hitmarkerOverride:render(pos, tostring(world_pos), alpha, dmg, headshot)

    return true
end)



callbacks.add(e_callbacks.AIMBOT_HIT, function(ctx)
	if not UI.VISUALS.LOG:get(1) then return end

    local ent = ctx.player;

    pcall(function()
        local health, name, white, add_info = ent:get_prop("m_iHealth"), devConsole.filter_name(ent:get_name()), color_t(255, 255, 255, 255), {};
		local alt_clr = (health<=0) and color_t(200, 255, 55, 255) or color_t(255, 200, 55, 255);

		if UI.VISUALS.LOG:get(3) then
			add_info = {white, " (sp:", alt_clr, tostring(ctx.aim_safepoint), white, " hc:", alt_clr, tostring(ctx.aim_hitchance), white, " dmg:", alt_clr, tostring(ctx.aim_damage), white, " bt:", alt_clr, tostring(ctx.backtrack_ticks), white, ")"};
		end

        if health<=0 then
			devConsole:print(color_t(155, 155, 255, 255), "[shot]", white, " Killed ", alt_clr, name, white, " with a shot to the ", alt_clr, tostring(HITGROUPS[ctx.hitgroup]), white, " for ", alt_clr, tostring(ctx.damage), unpack(add_info))
        else
            devConsole:print(color_t(155, 155, 255, 255), "[shot]", white, " Hit ", alt_clr, name, white, "'s ", alt_clr, tostring(HITGROUPS[ctx.hitgroup]), white, " for ", alt_clr, tostring(ctx.damage), white, " with ", alt_clr, tostring(health), white, " remaining", unpack(add_info))
        end
    end)
end)



callbacks.add(e_callbacks.AIMBOT_MISS, function(ctx)
    if not UI.VISUALS.LOG:get(2) then return end

    local ent = ctx.player;

    pcall(function()
        local name, red, white, add_info = devConsole.filter_name(ent:get_name()), color_t(255, 55, 55, 255), color_t(255, 255, 255, 255), {};
		
		if UI.VISUALS.LOG:get(3) then 
			add_info = {white, " (sp:", red, tostring(ctx.aim_safepoint), white, " hc:", red, tostring(ctx.aim_hitchance), white, " dmg:", red, tostring(ctx.aim_damage), white, " bt:", red, tostring(ctx.backtrack_ticks), white, ")"};
		end
		
        devConsole:print(color_t(155, 155, 255, 255), "[shot]", white, " Missed ", red, name,  white, "'s ", red, tostring(HITGROUPS[ctx.aim_hitgroup]), white, " due to ", red, tostring(ctx.reason_string:gsub("jitter", "misprediction")), unpack(add_info))
    end)
end)



callbacks.add(e_callbacks.EVENT, function(ctx)
	if not UI.VISUALS.LOG:get(4) then return end

	pcall(function()
		local player = entity_list.get_player_from_userid(ctx.userid);
		if player:get_index() == pLocal:get_index() or not player:is_enemy() then return end

		local wep = tostring(ctx.weapon);
		for idx, this in pairs({
			{"weapon_", ""},
			{"item_", ""},
			{"_", " "},
			{"assaultsuit", "kevlar + helmet"},
			{" silencer", "-s"},
			{"mp5sd", "mp5-s"}
		}) do wep = wep:gsub(this[1], this[2]) end

		devConsole:print(color_t(155,155,255), "[event] ", color_t(200, 255, 155), devConsole.filter_name(player:get_name()), color_t(255,255,255), " purchased a ", color_t(200, 255, 155), wep)
	end)
end, "item_purchase")



callbacks.add(e_callbacks.EVENT, function(ctx)
	local stage_amount = UI.ANTIAIM.ANTIBRUTE:get();
	local antibrute = AntiAim.antibrute;

	if not AntiAim.ENABLED or stage_amount==0 then return end

	pcall(function()
		local player = entity_list.get_player_from_userid(ctx.userid);
		if player:get_index() == pLocal:get_index() or not player:is_enemy() or not Alive then return end
		local from, to = player:get_eye_position(), vec3_t(ctx.x, ctx.y, ctx.z);
		local Angle_between = from:calc_angle_to(LocalEyePos).y-from:calc_angle_to(to).y;

		if Angle_between>180 then Angle_between=Angle_between-360; end if Angle_between<-180 then Angle_between=Angle_between+360; end

		if Angle_between>-90 and Angle_between<90 and from:dist(LocalEyePos)<=from:dist(to) and math.abs(from:dist(to)*math.sin(math.rad(Angle_between))) <= 150 and antibrute.tick~=TickCount+256 then
			antibrute.stage, antibrute.tick = (antibrute.stage>=stage_amount) and 1 or antibrute.stage+1, TickCount + 256;
			
			--if not UI.VISUALS.LOG:get(6) then return end
			devConsole:print(color_t(155,155,255), "[event] ", color_t(255, 255, 255), "Anti-Bruteforce responded to a shot from ", color_t(200, 255, 155), player:get_name())
		end
	end)
end, "bullet_impact")
-->> STOP CALLBACK REGISTRATION <<--



-- vgui_white cannot be collected with materials.find so we just do this ;|
materials.for_each(function(a)if a:get_name():find("vgui_white")then vguiConsole.materials[1]=a;end end) 

engine.execute_cmd("clear")
client.delay_call(function()
    devConsole:print(color_t(255, 255, 255, 255), "Welcome to", color_t(155,155,255,255), " Primal", color_t(255, 255, 255, 255), ".lua", color_t(200,255,55,255), " [open source]", color_t(255,255,255,255), ", hope you enjoy it and have fun!")

	menu.set_group_column("TABS", 1)
	menu.set_group_column("Home -> SemiLegit", 1)
	menu.set_group_column("Home -> Log", 2)

	menu.set_group_column("AntiAim -> Main", 1)
	menu.set_group_column("AntiAim -> Fakelag", 3)
	for _, name in pairs({
		"Global",
		"Standing",
		"Crouching",
		"Moving",
		"Jumping",
		"Manual",
		"Antibrute 1",
		"Antibrute 2",
		"Antibrute 3",
		"Antibrute 4",
		"Antibrute 5",
		"Antibrute 6", 
		"Antibrute 7",
		"Antibrute 8"
	}) do 
		menu.set_group_column("AntiAim -> "..name.." Yaw", 2)
		menu.set_group_column("AntiAim -> "..name.." Fake", 3)
	end
	
	menu.set_group_column("Visuals -> Main", 1)
	menu.set_group_column("Visuals -> Performance", 2)
	menu.set_group_column("Visuals -> Indication", 2)

	cvarOverride:set_in_scope_viewmodel(UI.VISUALS.MISC:get(1))
end, 0.1)