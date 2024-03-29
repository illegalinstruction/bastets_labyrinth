# 
#       .                                                   *
#  _               _       _   _  *                   .                     
# | |__   __ _ ___| |_ ___| |_( )___                  ,:.            +
# | '_ \ / _` / __| __/ _ \ __|// __|                 ,xo.               
# | |_) | (_| \__ \ ||  __/ |_  \__ \                 ,kKc      
# |_.__/ \__,_|___/\__\___|\__| |___/                .c0Wo      
#   __ _  __ _ _ __ __| | ___ _ __                  .;xXNc      
#  / _` |/ _` | '__/ _` |/ _ \ '_ \                .:dKNx.     * 
# | (_| | (_| | | | (_| |  __/ | | |             .;dOKNO'       
#  \__, |\__,_|_|  \__,_|\___|_| |_|         ..,lx0XNOc.        
#  |___/                                .';coxOKKX0xc.                .        
#           +                             .':ccc;..      .               
#                     .
# 
#
#   A bullet-hell roguelike rom-com no one asked for.
#   Copyright (C) 2024  illegal_instruction
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version. 
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#

extends Node2D

const MAX_VOLUME : int = 8;
const RES_SCALE_MIN : float = .5;
const RES_SCALE_MAX : float = 1.0;
const DEBUG_MODE : bool = true;
const ANALOGUE_DEAD_ZONE : float = 0.25;
const FADE_STEPS : int = 40;

#---- MAIN MENU and DATA VARS --------------------------------------------------
const game_data_base : String = "user://bastet";
const options_path 		= game_data_base + "-options";
const achievements_path = game_data_base + "-trophies";

const GAME_SUPPORTS_SAVING 			: bool = true;
const GAME_SUPPORTS_HIGH_SCORES		: bool = false;
const GAME_SUPPORTS_TROPHIES		: bool = true;

var sfx_vol 		: int 	= 3;
var music_vol 		: int 	= 3;

#-------------------------------------------------------------------------------

func get_music_vol_in_db():
    if (music_fadeout_clock < SCREENWIPE_MAX_TICKS):
        return linear2db((music_vol / float(MAX_VOLUME)) * pow(BGM_FADE_PER_TICK,music_fadeout_clock));
    if (curr_bgm != next_bgm):
        return linear2db(0);
    return linear2db(music_vol / float(MAX_VOLUME));

#-------------------------------------------------------------------------------

func get_sfx_vol_in_db():
    return linear2db(sfx_vol / float(MAX_VOLUME));

#-------------------------------------------------------------------------------

func save_options_data():
    var fout : File = File.new();

    var error = fout.open(options_path, fout.WRITE);
    if (error > 0):
        print_debug("could not open options file for writing! error code: " + str(error));
        return; # the show must go on...?
        
    sfx_vol = int(clamp(sfx_vol,0, MAX_VOLUME));
    fout.store_8(sfx_vol);
    music_vol = int(clamp(music_vol, 0, MAX_VOLUME));
    fout.store_8(music_vol);
    fout.store_8(use_joystick);
    fout.store_8(fullscreen);
    fout.close();
    
    return;
    
#-------------------------------------------------------------------------------

func load_options_data():
    var fin : File = File.new();
        
    if (fin.file_exists(options_path)):
        var error = fin.open(options_path, fin.READ);
        if (error > 0):
            print_debug("could not open options file for reading! error code: " + str(error));
            return; 
            
        sfx_vol = fin.get_8();
        music_vol = fin.get_8();
        use_joystick = fin.get_8();
        fullscreen = fin.get_8();
        fin.close();
        OS.window_fullscreen = fullscreen;
    else:
        save_options_data();
    return;

#---- POTATO PERFORMANCE VARS  -------------------------------------------------
var shadow_atlas_size 		:	int 	= 10;  		# between 1 & 10, gets multiplied by 256
var nearest_or_trilinear	:	bool	= false;	# true to reduce texture filter quality
var fullscreen				:	bool	= false;

#---- SCREEN TRANSITION VARS  --------------------------------------------------
# these are here as a workaround for gdscript not having static vars

const SCREENWIPE_MAX_TICKS	: int = 85;

var screenwipe_anim_clock	: int;
var screenwipe_direction	: bool; # true for out, false for in
var screenwipe_active		: bool;
var screenwipe_next_scene;

#---- GAMEPLAY VARS ------------------------------------------------------------

#---- JOYSTICK VARS ------------------------------------------------------------

var is_joystick_connected : bool = false;
var use_joystick : bool = true;

enum BUTTON_STATE {
    IDLE,
    PRESSED,
    HELD
};

var _left_stick_angle 		: float;
var _left_stick_distance 	: float;
var _left_stick_x			: float;
var _left_stick_y			: float;
var _right_stick_x 			: float;
var _right_stick_y 			: float;
var _right_stick_angle 		: float;
var _right_stick_distance 	: float;

var _menu_up : int = BUTTON_STATE.IDLE;
var _menu_down : int = BUTTON_STATE.IDLE;
var _menu_accept : int = BUTTON_STATE.IDLE;
var _menu_cancel : int = BUTTON_STATE.IDLE;
var _menu_other : int = BUTTON_STATE.IDLE;

var _button_start : int = BUTTON_STATE.IDLE;
var _button_select : int = BUTTON_STATE.IDLE;
var _button_a : int = BUTTON_STATE.IDLE;
var _button_b : int = BUTTON_STATE.IDLE;
var _button_x : int = BUTTON_STATE.IDLE;
var _button_y : int = BUTTON_STATE.IDLE;
var _button_L2 : int = BUTTON_STATE.IDLE;
var _button_R2 : int = BUTTON_STATE.IDLE;

#-----------------------------------------------------------------------

func handle_joystick_connect():
    if (Input.get_connected_joypads().size() < 1):
      is_joystick_connected = false;
    else:
      is_joystick_connected = true;
    pass;

#-----------------------------------------------------------------------

func poll_joystick():
    if (screenwipe_active):
        _button_start  = BUTTON_STATE.IDLE;
        _button_select = BUTTON_STATE.IDLE;
        _button_a  = BUTTON_STATE.IDLE;
        _button_b  = BUTTON_STATE.IDLE;
        _button_x  = BUTTON_STATE.IDLE;
        _button_y  = BUTTON_STATE.IDLE;
        _menu_up  = BUTTON_STATE.IDLE;
        _menu_down  = BUTTON_STATE.IDLE;
        _menu_accept = BUTTON_STATE.IDLE;
        _menu_other = BUTTON_STATE.IDLE;
        _menu_cancel = BUTTON_STATE.IDLE;
        return;
    
    #===============================================================================================
    # menu controls
    if ((Input.get_joy_axis(0,JOY_ANALOG_LY) < -0.7) or (Input.is_joy_button_pressed(0, JOY_DPAD_UP)) or (Input.is_key_pressed(KEY_UP))):
        _menu_up = _menu_up + 1;
    else:
        _menu_up = BUTTON_STATE.IDLE;
    
    if ((Input.get_joy_axis(0,JOY_ANALOG_LY) > 0.7) or (Input.is_joy_button_pressed(0, JOY_DPAD_DOWN)) or (Input.is_key_pressed(KEY_DOWN))):
        _menu_down = _menu_down + 1;
    else:
        _menu_down = BUTTON_STATE.IDLE;
  
    if (Input.is_joy_button_pressed(0, JOY_XBOX_A) or (Input.is_joy_button_pressed(0, JOY_START)) or (Input.is_key_pressed(KEY_SPACE)) or (Input.is_key_pressed(KEY_ENTER))):
        _menu_accept = _menu_accept + 1;
        _menu_accept = int(clamp(_menu_accept,0,2.0));
    else:
        _menu_accept = BUTTON_STATE.IDLE;	

    if (Input.is_joy_button_pressed(0, JOY_XBOX_B) or (Input.is_key_pressed(KEY_BACKSLASH)) or (Input.is_key_pressed(KEY_MINUS))):
        _menu_other = _menu_other + 1;
        _menu_other = int(clamp(_menu_other,0,2.0));
    else:
        _menu_other = BUTTON_STATE.IDLE;	

    if (Input.is_joy_button_pressed(0, JOY_SELECT) or (Input.is_key_pressed(KEY_ESCAPE)) ):
        _menu_cancel = _menu_cancel + 1;
        _menu_cancel = int(clamp(_menu_cancel,0,2.0));
    else:
        _menu_cancel = BUTTON_STATE.IDLE;	
    
    #===============================================================================================
    # ingame controls
    if (use_joystick):
      
        #--- ANALOGUE STICKS --------------------------
        var left_tmp : Vector2 = Vector2(Input.get_joy_axis(0,JOY_ANALOG_LX), Input.get_joy_axis(0,JOY_ANALOG_LY));
        
        _left_stick_x = left_tmp.x;
        _left_stick_y = left_tmp.y;
        
        _left_stick_distance = left_tmp.length();
        _left_stick_angle = (PI/2.0) - left_tmp.angle();
        
        var right_tmp : Vector2 = Vector2(Input.get_joy_axis(0,JOY_ANALOG_RX), Input.get_joy_axis(0,JOY_ANALOG_RY));
        
        _right_stick_x = Input.get_joy_axis(0,JOY_ANALOG_RX);
        _right_stick_y = Input.get_joy_axis(0,JOY_ANALOG_RY);

        _right_stick_distance = right_tmp.length();
        _right_stick_angle = (PI/2.0) - right_tmp.angle();

    
        #--- BUTTONS ----------------------------------
        #----------
        
        if (Input.is_joy_button_pressed(0, JOY_XBOX_A)):
            _button_a = _button_a + 1;
            _button_a = int(clamp(_button_a,0,2.0));
        else:
            _button_a = BUTTON_STATE.IDLE;
        
        #----------
        
        if (Input.is_joy_button_pressed(0, JOY_XBOX_B)):
            _button_b = _button_b + 1;
            _button_b = int(clamp(_button_b,0,2.0));
        else:
            _button_b = BUTTON_STATE.IDLE;
        
        #----------
        
        if (Input.is_joy_button_pressed(0, JOY_XBOX_X)):
            _button_x = _button_x + 1;
            _button_x = int(clamp(_button_x,0,2.0));
        else:
            _button_x = BUTTON_STATE.IDLE;
        
        #----------
        
        if (Input.is_joy_button_pressed(0, JOY_XBOX_Y)):
            _button_y = _button_y + 1;
            _button_y = int(clamp(_button_y,0,2.0));
        else:
            _button_y = BUTTON_STATE.IDLE;
        
        #----------
        
        if (Input.is_joy_button_pressed(0, JOY_L2)):
            _button_L2 += 1;
            _button_L2 = int(clamp(_button_L2,0,2));
        else:
            _button_L2 = BUTTON_STATE.IDLE;
        
        #----------
        
        if (Input.is_joy_button_pressed(0, JOY_R2)):
            _button_R2 += 1;
            _button_R2 = int(clamp(_button_R2,0,2));
        else:
            _button_R2 = BUTTON_STATE.IDLE;
        
        #----------

        if (Input.is_joy_button_pressed(0, JOY_START)):
            _button_start += 1;
            _button_start = int(clamp(_button_start,0,2));
        else:
            _button_start = BUTTON_STATE.IDLE;
        
        #----------
        
        if (Input.is_joy_button_pressed(0, JOY_SELECT)):
            _button_start += 1;
            _button_start = int(clamp(_button_select,0,2));
        else:
            _button_start = BUTTON_STATE.IDLE;
        

        return;
    else: # keyboard;
        #--- ANALOGUE STICKS --------------------------
        var left_tmp : Vector2;
        
        # todo: make these remappable after 1.0
        if ((Input.is_key_pressed(KEY_A)) or (Input.is_key_pressed(KEY_LEFT))):
            left_tmp.x = -1.0;
        if ((Input.is_key_pressed(KEY_D)) or (Input.is_key_pressed(KEY_RIGHT))):
            left_tmp.x = 1.0;
        if ((Input.is_key_pressed(KEY_W)) or (Input.is_key_pressed(KEY_UP))):
            left_tmp.y = -1.0;
        if ((Input.is_key_pressed(KEY_S)) or (Input.is_key_pressed(KEY_DOWN))):
            left_tmp.y = 1.0;
        
        _left_stick_x = left_tmp.x;
        _left_stick_y = left_tmp.y;
        
        _left_stick_distance = left_tmp.normalized().length();
        _left_stick_angle    = (PI/2.0) - left_tmp.angle();
        
        #--- BUTTONS ----------------------------------
        #----------
        
        if (Input.is_key_pressed(KEY_H)):
            _button_a = _button_a + 1;
            _button_a = int(clamp(_button_a,0,2.0));
        else:
            _button_a = BUTTON_STATE.IDLE;
        
        #----------
        
        if (Input.is_key_pressed(KEY_J)):
            _button_b = _button_b + 1;
            _button_b = int(clamp(_button_b,0,2.0));
        else:
            _button_b = BUTTON_STATE.IDLE;
        
        #----------
        
        if (Input.is_key_pressed(KEY_K)):
            _button_x = _button_x + 1;
            _button_x = int(clamp(_button_x,0,2.0));
        else:
            _button_x = BUTTON_STATE.IDLE;
        
        #----------
        
        if (Input.is_key_pressed(KEY_L)):
            _button_y = _button_y + 1;
            _button_y = int(clamp(_button_y,0,2.0));
        else:
            _button_y = BUTTON_STATE.IDLE;
        
        #----------
        # use both [enter] and [esc] as XBOX_START equivalents
        
        if (Input.is_key_pressed(KEY_ESCAPE) or Input.is_key_pressed(KEY_ENTER)):
            _button_start = _button_start + 1;
            _button_start = int(clamp(_button_start,0,2.0));
        else:
            _button_start = BUTTON_STATE.IDLE;
        
        #----------

        _right_stick_x = Input.get_joy_axis(0,JOY_ANALOG_RX);
        _right_stick_y = Input.get_joy_axis(0,JOY_ANALOG_RY);
    return;

#==============================================================================
# UI FONT
#==============================================================================
var ui_font : DynamicFont = null;

func ui_font_window_resize_handler():
    ui_font.size = 42;#int(get_viewport().size.y / 24.0);
    if (ui_font.size < 8):
        ui_font.size = 8;		
    return;

#-------------------------------------------------------------------------------

func _ready():
    
    # ready screen transition mechanism
    # for use
    screenwipe_direction 	= true;
    screenwipe_anim_clock	= 0;
    
    # automagically adjust font to match screen size.
    # this makes it a little big at high resolutions,
    # but easily readable on a handheld or a tv across the room...	
    ui_font = DynamicFont.new();
    ui_font.font_data = preload("res://font/HannariMincho-Regular.otf");
    ui_font.outline_color = Color.black;
    ui_font.outline_size = 1;
    stream_player   = AudioStreamPlayer.new();
    
    var _ignored = get_tree().get_root().connect("size_changed", self, "ui_font_window_resize_handler");
    ui_font_window_resize_handler();
    
    Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN);
    
    set_process(true);
    return;

#-------------------------------------------------------------------------------

func _process(_ignored):
    # --- adjust bgm volume
    handle_bgm_fading();
    stream_player.volume_db = get_music_vol_in_db();

    # --- gather input
    poll_joystick();
    
    # --- manage screenwipe if needed
    if (screenwipe_active):
        if (screenwipe_direction):
            screenwipe_anim_clock += 1;
    
            if (screenwipe_anim_clock >= SCREENWIPE_MAX_TICKS):
                screenwipe_active = false;
                screenwipe_direction = false;
                if (screenwipe_next_scene == null):
                    get_tree().quit();
                else:
                    var _unused = get_tree().change_scene_to(screenwipe_next_scene);
        else:
            screenwipe_anim_clock -= 1;
    
            if (screenwipe_anim_clock < 1):
                screenwipe_active = false;
    
    # hotkey to get out 
    if (DEBUG_MODE):
        if (Input.is_key_pressed(KEY_ESCAPE) and Input.is_key_pressed(KEY_Q)):
            get_tree().quit();
    return;

#-------------------------------------------------------------------------------

func change_scene_to(in_scene):
    if (screenwipe_active):
        return;

    screenwipe_direction 	= true;
    screenwipe_active		= true;
    screenwipe_next_scene	= in_scene;
    screenwipe_anim_clock	= 0;
    
#-------------------------------------------------------------------------------

func new_scene_screenwipe_start():
    if (screenwipe_active):
        return;

    screenwipe_active		= true;
    screenwipe_direction 	= false;
    screenwipe_anim_clock	= SCREENWIPE_MAX_TICKS;
    
#==============================================================================
# BACKGROUND MUSIC MANAGEMENT
#==============================================================================

# Background Music Management Variables
const BGM_FADE_PER_TICK = 0.95;

var curr_bgm        = 0;     # start with nothing playing
var next_bgm        = 0;
var music_fadeout_clock : int = 0;

# the fount from which all music floweth forth...
var stream_player   = AudioStreamPlayer.new(); 

##############################################################################
# bgm_switch_helper_priv()
#   a helper method that factors out the starting of a new song (and reduces
#   duplicated code).  Not intended to be called from child nodes...
#
func bgm_switch_helper_priv():
    if (not stream_player.is_inside_tree()):
        add_child(stream_player);

    var tmp = load("res://bgm/%03d.ogg" % curr_bgm);
   
    if ((tmp != null) && (music_fadeout_clock >= SCREENWIPE_MAX_TICKS)) :
        stream_player.volume_db = get_music_vol_in_db();
        stream_player.set_stream(tmp);
        stream_player.play();
    
    return;

##############################################################################
# set_bgm(song_index, should_fade = false)
#   tries to load new background music, starting it straightaway if none is
#   already playing, or, if there _is_ music playing, giving the option to 
#   fade out whatever's playing.  this only -sets- what plays - the actual  
#   fade out logic happens elsewhere.
#
#   by convention, song_index should be an integer; this corresponds to file
#   names in res://bgm/, which, again, by convention, will be a three-digit
#   number, followed by the extension '.ogg'
#
func set_bgm(song_index, should_fade = true):
    if ((song_index == curr_bgm) and (not is_bgm_done())):
        return; # it's already playing, nothing to do here
    
    if ((not should_fade) or (is_bgm_done()) or (self.curr_bgm == 0)):
        # no fade needed - stop old music immediately.
        self.curr_bgm = song_index;
        self.next_bgm = song_index;
        music_fadeout_clock = SCREENWIPE_MAX_TICKS + 1;
        stream_player.stop();
    else:
        # we need to fade out, so the music change is deferred
        # the actual fade logic is handled elsewhere in a func
        # called from process()
        next_bgm = song_index;
        music_fadeout_clock = 0;

    # are we asked to go silent?
    if (song_index == 0):
        # yep, we're done here
        return;
        
    # if we got down here, we need to start the req'd song
    bgm_switch_helper_priv();

    return;

##############################################################################

func is_bgm_done():
    return (not(stream_player.playing));

##############################################################################
# handle_bgm_fading()
#   if there's an active music fadeout going, handle it here by reducing the
#   bgm volume slightly until it reaches 0, then, switch BGM at that time.
#   needs to be called from process() and run each 'tick' - returns 
#   immediately if it has nothing to do.
#
func handle_bgm_fading():
    if (music_fadeout_clock > SCREENWIPE_MAX_TICKS):
        return;
    
    # is there NO music playing at the moment? 
    if (curr_bgm == 0):
        # start the next song straightaway
        music_fadeout_clock = SCREENWIPE_MAX_TICKS + 1;
        curr_bgm = next_bgm;
        
        # is the next song _also_ silence?
        if (next_bgm == 0):
            # nothing else to do here
            return;
    
        bgm_switch_helper_priv();

    else:
        # no, there's active music still.
        # done fading yet?
        if (music_fadeout_clock < SCREENWIPE_MAX_TICKS):
            # no - subtract a 'smidgen' from current volume
            music_fadeout_clock += 1;
            return;
        else:
            # yes - start next track
            curr_bgm = next_bgm;
            music_fadeout_clock = SCREENWIPE_MAX_TICKS + 1;

        if (next_bgm == 0):
            stream_player.stop();
            return;

        bgm_switch_helper_priv();
    return;
