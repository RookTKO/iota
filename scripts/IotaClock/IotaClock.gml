/// Constructor that instantiates an iota clock
/// 
/// @param [identifier]   Unique name for this clock. IOTA_CURRENT_CLOCK will be set to this value when the clock's .Tick() method is called. Defaults to <undefined>
/// 
/// 
/// 
/// iota clocks have the following public methods:
/// 
///   .Tick()
///     Updates the clock and executes methods
///     A clock will execute enough cycles to match its realtime update frequency
///     This means a clock may execute zero cycles per tick, or sometimes multiple cycles per tick
///   
///   
///   
///   .AddCycleMethod(method)
///     Adds a method to be executed for each cycle
///     The scope of the method passed into this function will persist
///     Only one cycle method can be defined per instance/struct
///   
///   .AddBeginMethod(method)
///     Adds a method to be executed at the start of a tick, before any cycle methods
///     The scope of the method passed into this function will persist
///     Only one begin method can be defined per instance/struct
///     Begin methods will *not* be executed if the clock doesn't need to execute any cycles at all
///   
///   .AddEndMethod(method)
///     Adds a method to be executed at the end of a tick, after all cycle methods
///     The scope of the method passed into this function will persist
///     Only one end method can be defined per instance/struct
///     End methods will *not* be executed if the clock doesn't need to execute any cycles at all
///   
///   
///   
///   .VariableMomentary(variableName, resetValue, [scope])
///     Adds a variable to be automatically reset at the end of the first cycle per tick
///     A momentary variable will only be reset if the clock needs to execute one or more cycles
///     The variable's scope is typically determined by who calls .VariableMomentary(), though for structs you may need to specify the optional [scope] argument
///   
///   .VariableInterpolate(inputVariableName, outputVariableName, [scope])
///     Adds a variable to be smoothly interpolated between iota ticks. The interpolated value is passed to the given output variable name
///     Interpolated variables are always updated every time .Tick() is called, even if the clock does not need to execute any cycles
///     The variables' scope is typically determined by who calls .VariableInterpolate(), though for structs you may need to specify the optional [scope] argument
///       N.B. Interpolated variables will always be (at most) a frame behind the actual value of the input variable
///            Most of this time this makes no difference but it's not ideal if you're looking for frame-perfect gameplay
///   
///   .VariableInterpolateAngle(inputVariableName, outputVariableName, [scope])
///     As above, but the value is interpolated as an angle measured in degrees. The output value will be an angle from -360 to +360.
///   
///   
///   
///   .AddAlarm(milliseconds, method)
///     Adds a method to be executed after the given number of milliseconds have passed for this clock
///     The scope of the method is maintained. If the instance/struct attached to the method is removed, the method will not execute
///     iota alarms respect time dilation and pausing - N.B. Changing a clock's update frequency will cause alarms to desynchronise
///   
///   .AddAlarmCycles(cycles, method)
///     Adds a method to be executed after the given number of cycles have passed for this clock
///     The scope of the method is maintained. If the instance/struct attached to the method is removed, the method will not execute
///     iota alarms respect time dilation and pausing - N.B. Changing a clock's update frequency will cause alarms to desynchronise
///   
///   
///   
///   .SetPause(state)
///     Sets whether the clock is paused
///     A paused clock will execute no methods nor modify any variables
///     
///   .GetPause(state)
///     Returns whether the clock is paused
///     
///   .SetUpdateFrequency(frequency)
///     Sets the update frequency for the clock. This value should generally not be changed once you've set it
///     This value will default to matching your game's target framerate at the time that the clock was instantiated
///     
///   .GetUpdateFrequency()
///     Returns the update frequency for the clock
///   
///   .SetTimeDilation(multiplier)
///     Sets the time dilation multiplier. A value of 1 is no time dilation, 0.5 is half speed, 2.0 is double speed
///     Time dilation values cannot be set lower than 0
///     
///   .GetTimeDilation(state)
///     Returns the time dilation multiplier
///     
///   .GetRemainder()
///     Returns the remainder on the accumulator



function IotaClock() constructor
{
    var _identifier = (argument_count > 0)? argument[0] : undefined;
    
    __identifier        = _identifier
    __updateFrequency   = game_get_speed(gamespeed_fps);
    __paused            = false;
    __dilation          = 1.0;
    __seconds_per_cycle = 1 / (__dilation*__updateFrequency);
    __accumulator       = 0;
    
    __childrenStruct      = {};
    __beginMethodArray    = [];
    __cycleMethodArray    = [];
    __endMethodArray      = [];
    __varMomentaryArray   = [];
    __varInterpolateArray = [];
    __alarmArray          = [];
    
    #region Tick
    
    static Tick = function()
    {
        IOTA_CURRENT_CLOCK = __identifier;
        global.__iota_current_clock = self;
        
        //Get the clamped delta time value for this GameMaker frame
        //We clamp the bottom end to ensure that games still chug along even if the device is really grinding
        var _delta = min(1/IOTA_MINIMUM_FRAMERATE, delta_time/1000000);
        
        //Start off assuming this clock isn't going to want to process any cycles whatsoever
        IOTA_CYCLES_FOR_CLOCK = 0;
        
        //If we're not paused, figure out how many full cycles this clock requires based the accumulator and the clock's framerate
        if (!__paused && (__dilation > 0))
        {
            __accumulator += _delta;
            IOTA_CYCLES_FOR_CLOCK = floor(__accumulator/__seconds_per_cycle);
            __accumulator -= IOTA_CYCLES_FOR_CLOCK*__seconds_per_cycle;
        }
        
        if (IOTA_CYCLES_FOR_CLOCK > 0)
        {
            IOTA_SECONDS_PER_CYCLE = __seconds_per_cycle;
            IOTA_CYCLE_INDEX = -1;
            __execute_methods(__IOTA_CHILD.BEGIN_METHOD);
            
            //Execute cycles one at a time
            //Note that we're processing all methods for a cycle, then move onto the next cycle
            //This ensures instances doesn't get out of step with each other
            IOTA_CYCLE_INDEX = 0;
            repeat(IOTA_CYCLES_FOR_CLOCK)
            {
                //Capture interpolated variable state before the final cycle
                if (IOTA_CYCLE_INDEX == IOTA_CYCLES_FOR_CLOCK-1) __VariablesInterpolateRefresh();
                
                var _i = 0;
                repeat(array_length(__alarmArray))
                {
                    if (__alarmArray[_i].__Tick())
                    {
                        array_delete(__alarmArray, _i, 1);
                    }
                    else
                    {
                        ++_i;
                    }
                }
                
                __execute_methods(__IOTA_CHILD.CYCLE_METHOD);
                
                //Reset momentary variables after the first cycle
                if (IOTA_CYCLE_INDEX == 0) __VariablesMomentaryReset();
                
                IOTA_CYCLE_INDEX++;
            }
            
            IOTA_CYCLE_INDEX = IOTA_CYCLES_FOR_CLOCK;
            __execute_methods(__IOTA_CHILD.END_METHOD);
        }
        
        //Update our output interpolated variables
        if (!__paused && (__dilation > 0)) __VariablesInterpolateUpdate();
    
        //Make sure to reset these macros so they can't be accessed outside of iota methods
        IOTA_CURRENT_CLOCK     = undefined;
        IOTA_CYCLES_FOR_CLOCK  = undefined;
        IOTA_CYCLE_INDEX       = undefined;
        IOTA_SECONDS_PER_CYCLE = undefined;
        
        global.__iota_current_clock = undefined;
    }
    
    #endregion
    
    #region Methods Adders
    
    static AddBeginMethod = function(_method)
    {
        return __AddMethodGeneric(_method, __IOTA_CHILD.BEGIN_METHOD);
    }
    
    static AddCycleMethod = function(_method)
    {
        return __AddMethodGeneric(_method, __IOTA_CHILD.CYCLE_METHOD);
    }
    
    static AddEndMethod = function(_method)
    {
        return __AddMethodGeneric(_method, __IOTA_CHILD.END_METHOD);
    }
    
    #endregion
    
    #region Variables
    
    static VariableMomentary = function()
    {
        var _name  = argument[0];
        var _reset = argument[1];
        var _scope = ((argument_count > 2) && (argument[2] != undefined))? argument[2] : other;
        
        var _child_data = __GetChildData(_scope);
        
        //Catch weird errors due to scoping
        if (!is_array(_child_data))
        {
            __IotaError("Scope could not be determined (data type=", typeof(_scope), ")");
        }
        
        var _array = _child_data[__IOTA_CHILD.VARIABLES_MOMENTARY];
        
        if (_array == undefined)
        {
            _array = [];
            _child_data[@ __IOTA_CHILD.VARIABLES_MOMENTARY] = _array;
            array_push(__varMomentaryArray, _child_data);
        }
        
        var _i = 0;
        repeat(array_length(_array) div __IOTA_MOMENTARY_VARIABLE.__SIZE)
        {
            if (_array[_i] == _name)
            {
                //This variable already exists
                return undefined;
            }
            
            _i += __IOTA_MOMENTARY_VARIABLE.__SIZE;
        }
        
        array_push(_array, _name, _reset);
    }
    
    static VariableInterpolate = function()
    {
        var _in_name  = argument[0];
        var _out_name = argument[1];
        var _scope    = ((argument_count > 2) && (argument[2] != undefined))? argument[2] : other;
        
        return __VariableInterpolateCommon(_in_name, _out_name, _scope, false);
    }
    
    static VariableInterpolateAngle = function()
    {
        var _in_name  = argument[0];
        var _out_name = argument[1];
        var _scope    = ((argument_count > 2) && (argument[2] != undefined))? argument[2] : other;
        
        return __VariableInterpolateCommon(_in_name, _out_name, _scope, true);
    }
    
    static __VariableInterpolateCommon = function(_in_name, _out_name, _scope, _is_angle)
    {
        var _child_data = __GetChildData(_scope);
        
        //Catch weird errors due to scoping
        if (!is_array(_child_data))
        {
            __IotaError("Scope could not be determined (data type=", typeof(_scope), ")");
        }
        
        var _array = _child_data[__IOTA_CHILD.VARIABLES_INTERPOLATE];
        
        if (_array == undefined)
        {
            _array = [];
            _child_data[@ __IOTA_CHILD.VARIABLES_INTERPOLATE] = _array;
            array_push(__varInterpolateArray, _child_data);
        }
        
        var _i = 0;
        repeat(array_length(_array) div __IOTA_INTERPOLATED_VARIABLE.__SIZE)
        {
            if (_array[_i] == _in_name)
            {
                //This variable already exists
                return undefined;
            }
            
            _i += __IOTA_INTERPOLATED_VARIABLE.__SIZE;
        }
        
        array_push(_array, _in_name, _out_name, variable_instance_get(_scope, _in_name), _is_angle);
        variable_instance_set(_scope, _out_name, variable_instance_get(_scope, _in_name));
    }
    
    static __VariableSkipInterpolation = function(_out_name, _scope)
    {
        var _child_data = __GetChildData(_scope);
        
        var _variables = _child_data[__IOTA_CHILD.VARIABLES_INTERPOLATE];
        var _j = 0;
        repeat(array_length(_variables) div __IOTA_INTERPOLATED_VARIABLE.__SIZE)
        {
            if (_variables[@ _j + __IOTA_INTERPOLATED_VARIABLE.OUT_NAME] == _out_name)
            {
                _variables[@ _j + __IOTA_INTERPOLATED_VARIABLE.PREV_VALUE] = variable_instance_get(_scope, _variables[_j + __IOTA_INTERPOLATED_VARIABLE.IN_NAME]);
            }
            
            _j += __IOTA_INTERPOLATED_VARIABLE.__SIZE;
        }
    }
    
    #endregion
    
    #region Alarms
    
    static AddAlarm = function(_time, _method)
    {
        return new __IotaClassAlarm(self, (_time / 1000) * GetUpdateFrequency(), _method);
    }
    
    static AddAlarmCycles = function(_cycles, _method)
    {
        return new __IotaClassAlarm(self, _cycles, _method);
    }
    
    #endregion
    
    #region Pause / Target Framerate / Time Dilation
    
    static SetPause = function(_state)
    {
        __paused = _state;
    }
    
    static GetPause = function()
    {
        return __paused;
    }
    
    static SetUpdateFrequency = function(_frequency)
    {
        __updateFrequency = _frequency;
        __seconds_per_cycle = 1 / (__dilation*__updateFrequency);
    }
    
    static GetUpdateFrequency = function()
    {
        return __updateFrequency;
    }
    
    static SetTimeDilation = function(_multiplier)
    {
        __dilation = max(0, _multiplier);
        __seconds_per_cycle = 1 / (__dilation*__updateFrequency);
    }
    
    static GetTimeDilation = function()
    {
        return __dilation;
    }
    
    static GetRemainder = function()
    {
        return __dilation*__updateFrequency*__accumulator;
    }
    
    #endregion
    
    #region (Private Methods)
    
    static __execute_methods = function(_method_type)
    {
        switch(_method_type)
        {
            case __IOTA_CHILD.BEGIN_METHOD: var _array = __beginMethodArray; break;
            case __IOTA_CHILD.CYCLE_METHOD: var _array = __cycleMethodArray; break;
            case __IOTA_CHILD.END_METHOD:   var _array = __endMethodArray;   break;
        }
        
        var _i = 0;
        repeat(array_length(_array))
        {
            var _child_data = _array[_i];
            
            //If another process found that this child no longer exists, remove it from this array too
            if (_child_data[__IOTA_CHILD.DEAD])
            {
                array_delete(_array, _i, 1);
                continue;
            }
            
            var _scope = _child_data[__IOTA_CHILD.SCOPE];
            switch(__IotaScopeExists(_scope))
            {
                case 1: //Alive instance
                    with(_scope) _child_data[_method_type]();
                break;
                
                case 2: //Alive struct
                    with(_scope.ref) _child_data[_method_type]();
                break;
                
                case -1: //Dead instance
                case -2: //Dead struct
                    array_delete(_array, _i, 1);
                    __MarkChildAsDead(_child_data);
                    continue;
                break;
                
                case 0: //Deactivated instance
                break;
            }
            
            ++_i;
        }
    }
    
    static __MarkChildAsDead = function(_child_data)
    {
        variable_struct_remove(__childrenStruct, _child_data[__IOTA_CHILD.IOTA_ID]);
        _child_data[@ __IOTA_CHILD.DEAD] = true;
    }
    
    static __AddMethodGeneric = function(_method, _method_type)
    {
        if (is_numeric(_method))
        {
            //Might be a script index
            if (script_exists(_method))
            {
                _method = method(other, _method);
            }
            else
            {
                __IotaError("Could not find script index ", _method);
            }
        }
        else if (!is_method(_method))
        {
            __IotaError("Method was an incorrect data type (", typeof(_method), ")");
        }
        
        var _scope = method_get_self(_method);
        
        switch(_method_type)
        {
            case __IOTA_CHILD.BEGIN_METHOD: var _array = __beginMethodArray; break;
            case __IOTA_CHILD.CYCLE_METHOD: var _array = __cycleMethodArray; break;
            case __IOTA_CHILD.END_METHOD:   var _array = __endMethodArray;   break;
        }
        
        var _child_data = __GetChildData(_scope);
        
        //Catch weird errors due to scoping
        if (!is_array(_child_data))
        {
            __IotaError("iota:\nScope could not be determined (data type=", typeof(_scope), ")");
        }
        
        //If we haven't seen this method type before for this child, add the child to the relevant array
        if (_child_data[_method_type] == undefined) array_push(_array, _child_data);
        
        //Set the relevant element in the data packet
        //We strip the scope off the method so we don't accidentally keep structs alive
        _child_data[@ _method_type] = method(undefined, _method);
    }
    
    static __GetChildData = function(_scope)
    {
        var _is_instance = false;
        var _is_struct   = false;
        var _id          = undefined;
        
        if (is_numeric(_scope))
        {
            if (_scope < 100000)
            {
                __IotaError("Method scope must be an instance or a struct, object indexes are not permitted");
            }
        }
        else if (!is_struct(_scope) && !instance_exists(_scope))
        {
            __IotaError("Method scope must be an instance or a struct, found scope's data type was ", typeof(_scope));
        }
        
        var _child_id = variable_instance_get(_scope, IOTA_ID_VARIABLE_NAME);
        
        //Fetch the data packet from the clock's data struct
        var _child_data = (_child_id == undefined)? undefined : __childrenStruct[$ _child_id];
        
        //If this scope didn't have an ID, assign it one
        if (_child_id == undefined)
        {
            global.__iota_unique_id++;
            _child_id = global.__iota_unique_id;
        }
        
        //If this scope didn't have any data for this clock, create some
        if (_child_data == undefined)
        {
            //If the scope is a real number then presume it's an instance ID
            if (is_numeric(_scope))
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
                if (is_numeric(_id) && !is_struct(_scope))
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
            
            //Give this scope a unique iota ID
            //This'll save us some pain later if we need to add a different sort of method
            variable_instance_set(_scope, IOTA_ID_VARIABLE_NAME, _child_id);
            
            //Create a new data packet and set it up
            var _child_data = array_create(__IOTA_CHILD.__SIZE, undefined);
            _child_data[@ __IOTA_CHILD.IOTA_ID] = _child_id;
            _child_data[@ __IOTA_CHILD.SCOPE  ] = (_is_instance? _id : weak_ref_create(_scope));
            _child_data[@ __IOTA_CHILD.DEAD   ] = false;
        
            //Then slot this data packet into the clock's data struct + array
            __childrenStruct[$ _child_id] = _child_data;
        }
        
        return _child_data;
    }
    
    static __VariablesMomentaryReset = function()
    {
        var _array = __varMomentaryArray;
        
        var _i = 0;
        repeat(array_length(_array))
        {
            var _child_data = _array[_i];
            
            //If another process found that this child no longer exists, remove it from this array too
            if (_child_data[__IOTA_CHILD.DEAD])
            {
                array_delete(_array, _i, 1);
                continue;
            }
            
            var _scope = _child_data[__IOTA_CHILD.SCOPE];
            switch(__IotaScopeExists(_scope))
            {
                case 1: //Alive instance
                case 2: //Alive struct
                    //If our scope isn't a real then it's a struct, so jump into the struct itself
                    if (!is_numeric(_scope)) _scope = _scope.ref;
                    
                    var _variables = _child_data[__IOTA_CHILD.VARIABLES_MOMENTARY];
                    var _j = 0;
                    repeat(array_length(_variables) div __IOTA_MOMENTARY_VARIABLE.__SIZE)
                    {
                        variable_instance_set(_scope, _variables[_j + __IOTA_MOMENTARY_VARIABLE.NAME], _variables[_j + __IOTA_MOMENTARY_VARIABLE.DEFAULT_VALUE]);
                        _j += __IOTA_MOMENTARY_VARIABLE.__SIZE;
                    }
                break;
                
                case -1: //Dead instance
                case -2: //Dead struct
                    array_delete(_array, _i, 1);
                    __MarkChildAsDead(_child_data);
                    continue;
                break;
                
                case 0: //Deactivated instance
                break;
            }
            
            ++_i;
        }
    }
    
    static __VariablesInterpolateRefresh = function()
    {
        var _array = __varInterpolateArray;
        
        var _i = 0;
        repeat(array_length(_array))
        {
            var _child_data = _array[_i];
            
            //If another process found that this child no longer exists, remove it from this array too
            if (_child_data[__IOTA_CHILD.DEAD])
            {
                array_delete(_array, _i, 1);
                continue;
            }
            
            var _scope = _child_data[__IOTA_CHILD.SCOPE];
            switch(__IotaScopeExists(_scope))
            {
                case 1: //Alive instance
                case 2: //Alive struct
                    //If our scope isn't a real then it's a struct, so jump into the struct itself
                    if (!is_numeric(_scope)) _scope = _scope.ref;
                    
                    var _variables = _child_data[__IOTA_CHILD.VARIABLES_INTERPOLATE];
                    var _j = 0;
                    repeat(array_length(_variables) div __IOTA_INTERPOLATED_VARIABLE.__SIZE)
                    {
                        _variables[@ _j + __IOTA_INTERPOLATED_VARIABLE.PREV_VALUE] = variable_instance_get(_scope, _variables[_j + __IOTA_INTERPOLATED_VARIABLE.IN_NAME]);
                        _j += __IOTA_INTERPOLATED_VARIABLE.__SIZE;
                    }
                break;
                
                case -1: //Dead instance
                case -2: //Dead struct
                    array_delete(_array, _i, 1);
                    __MarkChildAsDead(_child_data);
                    continue;
                break;
                
                case 0: //Deactivated instance
                break;
            }
            
            ++_i;
        }
    }
    
    static __VariablesInterpolateUpdate = function()
    {
        var _remainder = GetRemainder();
        var _array = __varInterpolateArray;
        
        var _i = 0;
        repeat(array_length(_array))
        {
            var _child_data = _array[_i];
            
            //If another process found that this child no longer exists, remove it from this array too
            if (_child_data[__IOTA_CHILD.DEAD])
            {
                array_delete(_array, _i, 1);
                continue;
            }
            
            var _scope = _child_data[__IOTA_CHILD.SCOPE];
            switch(__IotaScopeExists(_scope))
            {
                case 1: //Alive instance
                case 2: //Alive struct
                    //If our scope isn't a real then it's a struct, so jump into the struct itself
                    if (!is_numeric(_scope)) _scope = _scope.ref;
                    
                    var _variables = _child_data[__IOTA_CHILD.VARIABLES_INTERPOLATE];
                    var _j = 0;
                    repeat(array_length(_variables) div __IOTA_INTERPOLATED_VARIABLE.__SIZE)
                    {
                        if (_variables[_j + __IOTA_INTERPOLATED_VARIABLE.IS_ANGLE])
                        {
                            var _old_value = _variables[_j + __IOTA_INTERPOLATED_VARIABLE.PREV_VALUE];
                            var _new_value = _old_value + _remainder*angle_difference(variable_instance_get(_scope, _variables[_j + __IOTA_INTERPOLATED_VARIABLE.IN_NAME]), _old_value);
                        }
                        else
                        {
                            var _new_value = lerp(_variables[_j + __IOTA_INTERPOLATED_VARIABLE.PREV_VALUE], variable_instance_get(_scope, _variables[_j + __IOTA_INTERPOLATED_VARIABLE.IN_NAME]), _remainder);
                        }
                        
                        variable_instance_set(_scope, _variables[_j + __IOTA_INTERPOLATED_VARIABLE.OUT_NAME], _new_value);
                        
                        _j += __IOTA_INTERPOLATED_VARIABLE.__SIZE;
                    }
                break;
                
                case -1: //Dead instance
                case -2: //Dead struct
                    array_delete(_array, _i, 1);
                    __MarkChildAsDead(_child_data);
                    continue;
                break;
                
                case 0: //Deactivated instance
                break;
            }
            
            ++_i;
        }
    }
    
    #endregion
}





#region (System)

#macro __IOTA_VERSION  "2.4.0"
#macro __IOTA_DATE     "2022-04-01"

__IotaTrace("Welcome to iota by @jujuadams! This is version " + __IOTA_VERSION + ", " + __IOTA_DATE);

global.__iota_unique_id = 0;
global.__iota_current_clock = undefined;

#macro IOTA_CURRENT_CLOCK       global.__iota_current_identifier
#macro IOTA_CYCLES_FOR_CLOCK    global.__iota_total_cycles
#macro IOTA_CYCLE_INDEX         global.__iota_cycle_index
#macro IOTA_SECONDS_PER_CYCLE   global.__iota_seconds_per_cycle  

IOTA_CURRENT_CLOCK     = undefined;
IOTA_CYCLES_FOR_CLOCK  = undefined;
IOTA_CYCLE_INDEX       = undefined;
IOTA_SECONDS_PER_CYCLE = undefined;

enum __IOTA_CHILD
{
    IOTA_ID,
    SCOPE,
    BEGIN_METHOD,
    CYCLE_METHOD,
    END_METHOD,
    DEAD,
    VARIABLES_MOMENTARY,
    VARIABLES_INTERPOLATE,
    __SIZE
}

enum __IOTA_MOMENTARY_VARIABLE
{
    NAME,
    DEFAULT_VALUE,
    __SIZE,
}


enum __IOTA_INTERPOLATED_VARIABLE
{
    IN_NAME,
    OUT_NAME,
    PREV_VALUE,
    IS_ANGLE,
    __SIZE,
}





function __IotaClassAlarm(_clock, _cycles, _method) constructor
{
    __clock     = undefined;
    __total     = undefined;
    __remaining = undefined;
    __func      = undefined;
    __scope     = undefined;
    
    var _scope = __IotaGetScope(method_get_self(_method));
    if (_scope != undefined)
    {
        __clock     = _clock;
        __total     = _cycles;
        __remaining = _cycles;
        __func      = method(undefined, _method);
        __scope     = _scope;
        
        array_push(__clock.__alarmArray, self);
    }
    else
    {
        __IotaTrace("Warning! Scope was <undefined>, alarm will never execute (stack = ", debug_get_callstack(), ")");
    }
    
    
    
    static Cancel = function()
    {
        __clock = undefined;
    }
    
    
    
    #region (Private Methods)
    
    static __Tick = function()
    {
        if (__clock == undefined) return true;
        
        __remaining--;
        if (__remaining <= 0)
        {
            if (__IotaScopeExists(__scope))
            {
                var _func = __func;
                with(__scope) _func();
            }
            else
            {
                __IotaTrace("Warning! Scope was for alarm no longer exists, alarm will never execute (stack = ", debug_get_callstack(), ")");
            }
            
            return true;
        }
        
        return false;
    }
    
    #endregion
}



function __IotaGetScope(_scope)
{
    var _is_instance = false;
    var _is_struct   = false;
    var _id          = undefined;
    
    //If the scope is a real number then presume it's an instance ID
    if (is_numeric(_scope))
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
        if (is_numeric(_id) && !is_struct(_scope))
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
    
    if (_is_instance || _is_struct)
    {
        return (_is_instance? _id : weak_ref_create(_scope));
    }
}



/// Returns:
///    -2 = Dead struct
///    -1 = Dead instance
///     0 = Deactivated instance
///     1 = Alive instance
///     2 = Alive struct
function __IotaScopeExists(_scope) //Does do deactivation check
{
    if (is_numeric(_scope))
    {
        //If this scope is a real number then it's an instance ID
        if (instance_exists(_scope)) return 1;
            
        if (IOTA_CHECK_FOR_DEACTIVATION)
        {
            //Bonus check for deactivation
            instance_activate_object(_scope);
            if (instance_exists(_scope))
            {
                instance_deactivate_object(_scope);
                return 0;
            }
        }
            
        return -1;
    }
    else
    {
        //If the scope wasn't a real number then presumably it's a weak reference to a struct
        if (weak_ref_alive(_scope)) return 2;
        return -2;
    }
}

function __IotaTrace()
{
    var _string = "iota: ";
    var _i = 0;
    repeat(argument_count)
    {
        _string += string(argument[_i]);
        ++_i;
    }
    
    show_debug_message(_string);
}

function __IotaError()
{
    var _string = "iota:\n";
    var _i = 0;
    repeat(argument_count)
    {
        _string += string(argument[_i]);
        ++_i;
    }
    
    show_error(_string + "\n ", true);
}

#endregion