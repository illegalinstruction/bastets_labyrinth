extends Node2D

#------------------------------------------------------------------------------

var paused : bool = false;

#------------------------------------------------------------------------------

func _ready():
    paused = false;
    set_process(true);
    return;

#------------------------------------------------------------------------------

func _process(_ignore):
    return;

#------------------------------------------------------------------------------

func handle_input():
    if (GLOBAL._button_start == GLOBAL.BUTTON_STATE.PRESSED):
        paused = not paused;
