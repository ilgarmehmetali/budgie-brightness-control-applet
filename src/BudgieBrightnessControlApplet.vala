/*
 * This file is part of budgie-brightness-control-applet
 * 
 * Copyright © 2015-2017 Ikey Doherty <ikey@solus-project.com>
 * Copyright © 2017 Mehmet Ali İLGAR <mehmet.ali@milgar.net>
 * Copyright © 2021 Sarah Leibbrand <xavalia@gmail.com>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

namespace BrightnessControl {

public class Plugin : Budgie.Plugin, Peas.ExtensionBase
{
    public Budgie.Applet get_panel_widget(string uuid)
    {
        return new Applet();
    }
}

public class Applet : Budgie.Applet
{

    public Gtk.Image widget { protected set; public get; }

    /** EventBox for popover management */
    public Gtk.EventBox? ebox;

    /** GtkPopover in which to show a brightness control */
    public Budgie.Popover popover;

    /** Display scale for the brightness controls */

    /** Track the scale value_changed to prevent cross-noise */
    private ulong[] scale_id = {};

    /* Use this to register popovers with the panel system */
    private unowned Budgie.PopoverManager? manager = null;

	// turned off, should be managed by gnome if newer than 3_32_0, contact Sarah otherwise..
#if GNOME_SETTINGS_DAEMON_OLDER_THAN_3_32_0
    private ILogindManager? logind_manager;
#endif
    
    private string[] devices = {};
    private int[] max_brightness = {};
    private int[] step_size = {};
    private Gtk.Scale[] scales = {};
    
    // Gnome Daemon Settings Version so we know what we can use
    public bool gnomeSettingsDaemon336 = false;
    public bool gnomeSettingsDaemon332 = false;
    public bool gnomeSettingsDaemonOlderThan332 = false;

    public Applet()
    {
#if GNOME_SETTINGS_DAEMON_3_36_0
        gnomeSettingsDaemon336 = true;
#endif
#if GNOME_SETTINGS_DAEMON_3_32_0
        gnomeSettingsDaemon332 = true;
#endif
#if GNOME_SETTINGS_DAEMON_OLDER_THAN_3_32_0
        gnomeSettingsDaemonOlderThan332 = true;
#endif
        get_devices_and_settings();

        widget = new Gtk.Image.from_icon_name("display-brightness-symbolic", Gtk.IconSize.MENU);
        ebox = new Gtk.EventBox();
        ebox.add(widget);
        ebox.margin = 0;
        ebox.border_width = 0;
        add(ebox);

        /* Sort out our popover */
        this.create_brightness_popover();

        /* Catch scroll wheel events only when there is 1 device or old version of gnome-settings-daemon */
        if (gnomeSettingsDaemonOlderThan332 || devices.length == 1) {
		    ebox.add_events(Gdk.EventMask.SCROLL_MASK);
		    ebox.scroll_event.connect(on_scroll_event);
		}

        ebox.button_press_event.connect((e)=> {
            /* Not primary button? Good bye! */
            if (e.button != 1) {
                return Gdk.EVENT_PROPAGATE;
            }
            /* Hide if already showing */
            if (this.popover.get_visible()) {
                this.popover.hide();
            } else {
                /* Not showing, so show it.. */
                for (int i = 0; i < devices.length; i++) {
                	scales[i].set_value(this.get_brightness(false, i));
                }
                this.manager.show_popover(ebox);
            }
            return Gdk.EVENT_STOP;
        });

        show_all();

#if GNOME_SETTINGS_DAEMON_OLDER_THAN_3_32_0
        try {
            logind_manager = Bus.get_proxy_sync (BusType.SYSTEM, LOGIND_BUS_NAME, LOGIND_BUS_PATH);
            if(logind_manager != null){
                logind_manager.prepare_for_sleep.connect((start) => {
                    if(!start){
                        new Thread<int>("", () => {
                            Thread.usleep(5000000);
                            this.set_brightness(this.get_brightness(false));
                            return 0;
                        });
                    }
                });
            }
        } catch (IOError e) {
            print(e.message);
        }
#endif
    }

    /**
     * Create the GtkPopover to display on primary click action, with an adjustable
     * scale
     */
    private void create_brightness_popover()
    {
        popover = new Budgie.Popover(ebox);
        Gtk.Grid? popover_box = new Gtk.Grid();
        popover.add(popover_box);
        popover_box.margin = 6;
        scales = new Gtk.Scale[devices.length];
        
        for (int i = 0; i < devices.length; i++) {
        
		    Gtk.Button? sub_button = new Gtk.Button.from_icon_name("list-remove-symbolic", Gtk.IconSize.BUTTON);
		    Gtk.Button? plus_button = new Gtk.Button.from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON);
		    Gtk.Label? label = new Gtk.Label(devices[i].substring(21).concat("   "));
		    
		    /* device name label */
		    if (devices.length >= 1 && !gnomeSettingsDaemonOlderThan332) {
		    	popover_box.attach(label, 0, i, 1, 1);
		    }
		    
		    // Need to save the loop index or otherwise it will always be amount of devices and bug out
		    int loopIndex = i;

		    /* + button */
		    popover_box.attach(sub_button, 1, i, 1, 1);
		    sub_button.clicked.connect(()=> {
		        adjust_brightness_increment(-step_size[loopIndex], loopIndex);
		    });

			Gtk.Scale? brightness_scale = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, 0, this.max_brightness[i], 1);
			scales += brightness_scale;
		    popover_box.attach(brightness_scale, 2, i, 1, 1);
		    brightness_scale.set_value(this.get_brightness(false, i));

		    /* Hook up the value_changed event */
		    scale_id += brightness_scale.value_changed.connect(() => {
		    	on_scale_changed(loopIndex);
		    });

		    /* - button */
		    popover_box.attach(plus_button, 3, i, 1, 1);
		    plus_button.clicked.connect(()=> {
		        adjust_brightness_increment(+step_size[loopIndex], loopIndex);
		    });

		    /* Refine visual appearance of the scale.. */
		    brightness_scale.set_draw_value(false);
		    brightness_scale.set_size_request(140, -1);

		    /* Flat buttons only pls :) */
		    sub_button.get_style_context().add_class("flat");
		    sub_button.get_style_context().add_class("image-button");
		    plus_button.get_style_context().add_class("flat");
		    plus_button.get_style_context().add_class("image-button");

		    /* Focus ring is ugly and unnecessary */
		    sub_button.set_can_focus(false);
		    plus_button.set_can_focus(false);
		    brightness_scale.set_can_focus(false);
		    brightness_scale.set_inverted(false);
		
		}

        popover.get_child().show_all();
    }

    /**
     * Update from scroll events. turn brightness up + down.
     */
    protected bool on_scroll_event(Gdk.EventScroll event)
    {

        uint32 brightness = this.get_brightness(false, 0);
        var orig_brightness = brightness;

        switch (event.direction) {
            case Gdk.ScrollDirection.UP:
                brightness += (uint32)step_size[0];
                break;
            case Gdk.ScrollDirection.DOWN:
                brightness -= (uint32)step_size[0];
                // "uint. im lazy :p", thumbs up
                if (brightness > orig_brightness) {
                    brightness = 0;
                }
                break;
            default:
                // Go home, you're drunk.
                return false;
        }

        /* Ensure sanity + amp capability */
        if (brightness > max_brightness[0]) {
            brightness = (uint32)max_brightness[0];
        }

        SignalHandler.block(scales[0], scale_id[0]);
        this.set_brightness((int)brightness, 0);
        SignalHandler.unblock(scales[0], scale_id[0]);

        return true;
    }

    /**
     * The scale changed value - update brightness
     */
    private void on_scale_changed(int deviceIndex)
    {
        int brightness_value = (int) scales[deviceIndex].get_value();

        /* Avoid recursion ! */
        SignalHandler.block(scales[deviceIndex], scale_id[deviceIndex]);
        this.set_brightness(brightness_value, deviceIndex);
        SignalHandler.unblock(scales[deviceIndex], scale_id[deviceIndex]);
    }

    /**
     * Adjust the brightness by a given +/- increment and bounds limit it
     */
    private void adjust_brightness_increment(int increment, int deviceIndex)
    {
        int32 brightness = this.get_brightness(false, deviceIndex);
        brightness += (int32)increment;

        if (brightness < 0) {
            brightness = 0;
        } else if (brightness > max_brightness[deviceIndex]) {
            brightness = (int32) max_brightness[deviceIndex];
        }

        SignalHandler.block(scales[deviceIndex], scale_id[deviceIndex]);
        this.set_brightness(brightness, deviceIndex);
        this.scales[deviceIndex].set_value(brightness);
        SignalHandler.unblock(scales[deviceIndex], scale_id[deviceIndex]);
    }

    /**
     * Gets max brightness from gnome-settings-daemon
     */
    private void get_devices_and_settings() {
    	if (gnomeSettingsDaemonOlderThan332) {
    		this.devices += "";
    		this.step_size += this.calculate_step_size(0);
    		this.max_brightness += this.get_brightness(true, 0);
    	}
    
        try {
            string[] spawn_args = {"ls", "/sys/class/backlight/"};
            string[] spawn_env = Environ.get ();
            string ls_stdout;
            string ls_stderr;
            int ls_status;

            Process.spawn_sync ("/",
                spawn_args,
                spawn_env,
                SpawnFlags.SEARCH_PATH,
                null,
                out ls_stdout,
                out ls_stderr,
                out ls_status);
                
            string[] devicesFound = ls_stdout.split(" ");
            for (int i = 0; i < devicesFound.length; i++) {
            	this.devices += "/sys/class/backlight/".concat(devicesFound[i].strip());
		    	this.max_brightness += this.get_brightness(true, i);
		    	this.step_size += this.calculate_step_size(i);
            }
        } catch(SpawnError e){
            error(e.message);
        }
    }

    /**
     * Gets max brightness
     */
    private int get_brightness(bool max, int deviceIndex) {
        try {
        	string[] spawn_args = {};
        	
        	if (gnomeSettingsDaemonOlderThan332) {
        		spawn_args = {"pkexec", "/usr/lib/gsd-backlight-helper", "--get".concat(max ? "-max" : "").concat("-brightness")};
        	} else {
        		spawn_args = {"cat", devices[deviceIndex].concat(max ? "/max_" : "/", "brightness")};
        	}
        	
            string[] spawn_env = Environ.get ();
            string ls_stdout;
            string ls_stderr;
            int ls_status;

            Process.spawn_sync ("/",
                spawn_args,
                spawn_env,
                SpawnFlags.SEARCH_PATH,
                null,
                out ls_stdout,
                out ls_stderr,
                out ls_status);

            return int.parse(ls_stdout);
        } catch(SpawnError e){
            error(e.message);
        }
    }

    /**
     * Gets max brightness from gnome-settings-daemon
     */
    private void set_brightness(int brightness, int deviceIndex) {
        try {
        	string[] spawn_args = new string[4];
        	
        	if (gnomeSettingsDaemonOlderThan332) {
        		spawn_args = {"pkexec", "/usr/lib/gsd-backlight-helper", "--set-brightness", brightness.to_string()};
        	} else if (gnomeSettingsDaemon336) {
        		spawn_args = {"pkexec", "/usr/libexec/gsd-backlight-helper", devices[deviceIndex], brightness.to_string()};
        	} else {
        		spawn_args = {"pkexec", "/usr/lib/gnome-settings-daemon/gsd-backlight-helper", devices[deviceIndex], brightness.to_string()};
        	}
        	
            string[] spawn_env = Environ.get ();
            Pid child_pid;
            
            Process.spawn_async ("/",
                spawn_args,
                spawn_env,
                SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                null,
                out child_pid);

            ChildWatch.add (child_pid, (pid, status) => {
                Process.close_pid (pid);
            });
        } catch(SpawnError e){
            error(e.message);
        }
    }
    
    private int calculate_step_size(int deviceIndex) {
    	if (this.max_brightness[deviceIndex] <= 20) {
    		return 1;
    	}
    	
    	return (int) (this.max_brightness[deviceIndex] / 20);
    }

    public override void update_popovers(Budgie.PopoverManager? manager)
    {
        manager.register_popover(this.ebox, this.popover);
        this.manager = manager;
    }
}

}

[ModuleInit]
public void peas_register_types(TypeModule module)
{
    // boilerplate - all modules need this
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(BrightnessControl.Plugin));
}
