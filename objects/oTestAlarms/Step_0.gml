if (keyboard_check_pressed(ord("1")))
{
    alarm1.Cancel();
    alarm1 = oController.clock.AddAlarm(300, function() { show_debug_message("alarm1"); });
}

if (keyboard_check_pressed(ord("2")))
{
    alarm2.Cancel();
    alarm2 = oController.clock.AddAlarm(450, function() { show_debug_message("alarm2"); });
}