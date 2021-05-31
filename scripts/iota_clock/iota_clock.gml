enum __IOTA_CHILD
{
    IOTA_ID,
    SCOPE,
    BEGIN_METHOD,
    METHOD,
    END_METHOD,
    DEAD,
    __SIZE
}

function iota_clock(_identifier) constructor
{
    __identifier       = _identifier
    __target_framerate = game_get_speed(gamespeed_fps);
    __paused           = false;
    __accumulator      = 0;
    
    __prev_child_id      = 0;
    __children_struct    = {};
    __begin_method_array = [];
    __method_array       = [];
    __end_method_array   = [];
    
    #region Tick
    
    static tick = function()
    {
        IOTA_CURRENT_TIMER = __identifier;
        
        //Get the clamped delta time value for this GameMaker frame
        //We clamp the bottom end to ensure that games still chug along even if the device is really grinding
        var _delta = min(1/IOTA_MINIMUM_FRAMERATE, delta_time/1000000);
        
        //Start off assuming this timer isn't going to want to process any cycles whatsoever
        IOTA_CYCLES_FOR_TIMER = 0;
        
        if (!__paused)
        {
            //Figure out how many full cycles this timer requires based the accumulator and the timer's framerate
            IOTA_CYCLES_FOR_TIMER = floor(__target_framerate*__accumulator);
            
            //Any leftover time that can't fit into a full cycle add back onto the accumulator
            __accumulator += _delta - (IOTA_CYCLES_FOR_TIMER / __target_framerate);
        }
        
        if (IOTA_CYCLES_FOR_TIMER > 0)
        {
            IOTA_CYCLE_INDEX = -1;
            __execute_methods(__IOTA_DATA.BEGIN_METHOD);
            
            //Execute cycles one at a time
            //Note that we're processing all methods for a cycle, then move onto the next cycle
            //This ensures instances doesn't get out of step with each other
            IOTA_CYCLE_INDEX = 0;
            repeat(IOTA_CYCLES_FOR_TIMER)
            {
                __execute_methods(__IOTA_DATA.METHOD);
                IOTA_CYCLE_INDEX++;
            }
            
            IOTA_CYCLE_INDEX = IOTA_CYCLES_FOR_TIMER;
            __execute_methods(__IOTA_DATA.END_METHOD);
        }
    
        //Make sure to reset these macros so they can't be accessed outside of iota methods
        IOTA_CURRENT_TIMER    = undefined;
        IOTA_CYCLES_FOR_TIMER = undefined;
        IOTA_CYCLE_INDEX      = undefined;
    }
    
    function __execute_methods(_method_type)
    {
        switch(_method_type)
        {
            case __IOTA_CHILD.BEGIN_METHOD: var _array = __begin_method_array; break;
            case __IOTA_CHILD.METHOD:       var _array = __method_array;       break;
            case __IOTA_CHILD.END_METHOD:   var _array = __end_method_array;   break;
        }
        
        var _i = 0;
        repeat(array_length(_array))
        {
            var _child = _array[_i];
            
            //If another process found that this child no longer exists, remove it from this array too
            if (_child[__IOTA_CHILD.DEAD])
            {
                array_delete(_array, _i, 1);
                continue;
            }
            
            var _scope = _child[__IOTA_CHILD.SCOPE];
            
            //If this scope is a real number then it's an instance ID
            if (is_real(_scope))
            {
                var _exists = instance_exists(_scope);
                var _deactivated = false;
                
                if (IOTA_CHECK_FOR_DEACTIVATION)
                {
                    //Bonus check for deactivation
                    if (!_exists)
                    {
                        instance_activate_object(_scope);
                        if (instance_exists(_scope))
                        {
                            instance_deactivate_object(_scope);
                            _exists = true;
                            _deactivated = true;
                        }
                    }
                }
            
                if (_exists)
                {
                    //If this instance exists and isn't deactivated, execute our method!
                    if (!_deactivated) with(_scope) _child[_method_type]();
                }
                else
                {
                    //If this instance doesn't exist then remove it from the timer's data array + struct
                    array_delete(_array, _i, 1);
                    variable_struct_remove(__children_struct, _child[__IOTA_CHILD.IOTA_ID]);
                    _child[@ __IOTA_CHILD.DEAD] = true;
                    continue;
                }
            }
            else
            {
                //If the scope wasn't a real number then presumably it's a weak reference to a struct
                if (weak_ref_alive(_scope))
                {
                    //If this struct exists, execute our method!
                    with(_scope.ref) _child[_method_type]();
                }
                else
                {
                    //If this struct has been garbage collected then remove it from both the method and scope lists
                    array_delete(_array, _i, 1);
                    variable_struct_remove(__children_struct, _child[__IOTA_CHILD.IOTA_ID]);
                    _child[@ __IOTA_CHILD.DEAD] = true;
                    continue;
                }
            }
        
            ++_i;
        }
    }
    
    #endregion
    
    #region Methods
    
    static add_begin_method = function(_function)
    {
        return __add_method_generic(other, _function, __IOTA_CHILD.BEGIN_METHOD);
    }
    
    static add_method = function(_function)
    {
        return __add_method_generic(other, _function, __IOTA_CHILD.METHOD);
    }
    
    static add_end_method = function(_function)
    {
        return __add_method_generic(other, _function, __IOTA_CHILD.END_METHOD);
    }
    
    static __add_method_generic = function(_scope, _function, _method_type)
    {
        var _is_instance = false;
        var _is_struct   = false;
        var _id          = undefined;
        
        switch(_method_type)
        {
            case __IOTA_CHILD.BEGIN_METHOD: var _array = __begin_method_array; break;
            case __IOTA_CHILD.METHOD:       var _array = __method_array;       break;
            case __IOTA_CHILD.END_METHOD:   var _array = __end_method_array;   break;
        }
        
        if (is_real(_scope))
        {
            if (_scope < 100000)
            {
                show_error("iota method scope must be an instance or a struct, object indexes are not permitted", true);
            }
        }
    
        var _child_id = variable_instance_get(_scope, IOTA_ID_VARIABLE_NAME);
        if (_child_id == undefined)
        {
            //If the scope is a real number then presume it's an instance ID
            if (is_real(_scope))
            {
                //We found a valid instance ID so let's set some variables based on that
                //Changing scope here works around some bugs in GameMaker that I don't think exist any more?
                with(_scope)
                {
                    _scope = self;
                    _is_instance = true;
                    _id = id;
                    break;
                }
            }
            else
            {
                //Sooooometimes we might get given a struct which is actually an instance
                //Despite being able to read struct variable, it doesn't report as a struct... which is weird
                //Anyway, this check works around that!
                var _id = variable_instance_get(_scope, "id");
                if (is_real(_id) && !is_struct(_scope))
                {
                    if (instance_exists(_id))
                    {
                        _is_instance = true;
                    }
                    else
                    {
                        //Do a deactivation check here too, why not
                        if (IOTA_CHECK_FOR_DEACTIVATION)
                        {
                            instance_activate_object(_id);
                            if (instance_exists(_id))
                            {
                                _is_instance = true;
                                instance_deactivate_object(_id);
                            }
                        }
                    }
                }
                else if (is_struct(_scope))
                {
                    _is_struct = true;
                }
            }
        
            if (!_is_instance && !_is_struct)
            {
                return undefined;
            }
        
            //Give this scope a unique iota ID
            //This'll save us some pain later if we need to add a different sort of method
            __prev_child_id++;
            variable_instance_set(_scope, IOTA_ID_VARIABLE_NAME, __prev_child_id);
        
            //Create a new data packet and set it up
            var _child = array_create(__IOTA_DATA.__SIZE, undefined);
            _child[@ __IOTA_CHILD.IOTA_ID] = __prev_child_id;
            _child[@ __IOTA_CHILD.SCOPE  ] = (_is_instance? _id : weak_ref_create(_scope));
            _child[@ __IOTA_CHILD.DEAD   ] = false;
        
            //Then slot this data packet into the timer's data struct + array
            __children_struct[$ __prev_child_id] = _child;
        }
        else
        {
            //Fetch the data packet from the timer's data struct
            _child = __children_struct[$ _child_id];
        }
        
        //If we haven't seen this method type before for this child, add the child to the relevant array
        if (_child[_method_type] == undefined) array_push(_array, _child);
        
        //Set the relevant element in the data packet
        //We strip the scope off the method so we don't accidentally keep structs alive
        _child[@ _method_type] = method(undefined, _function);
    }
    
    #endregion
    
    #region Pause / Target Framerate
    
    static set_pause = function(_state)
    {
        __paused = _state;
    }
    
    static get_pause = function()
    {
        return __paused;
    }
    
    static set_target_framerate = function(_framerate)
    {
        __target_framerate = _framerate;
    }
    
    static get_target_framerate = function()
    {
        return __target_framerate;
    }
    
    #endregion
}