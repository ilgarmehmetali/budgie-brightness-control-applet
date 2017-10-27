/*
 * This file is part of budgie-brightness-control-applet
 * 
 * Copyright © 2015-2017 Ikey Doherty <ikey@solus-project.com>
 * Copyright © 2017 Mehmet Ali İLGAR <mehmet.ali@milgar.net>
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
    private Gtk.Scale brightness_scale;

    private int step_size = 1;

    /** Track the scale value_changed to prevent cross-noise */
    private ulong scale_id;

    private int max_brightness;

    /* Use this to register popovers with the panel system */
    private unowned Budgie.PopoverManager? manager = null;

    private ILogindManager? logind_manager;

    public Applet()
    {
        this.max_brightness = this.get_max_brightness();

        widget = new Gtk.Image.from_icon_name("display-brightness-symbolic", Gtk.IconSize.MENU);
        ebox = new Gtk.EventBox();
        ebox.add(widget);
        ebox.margin = 0;
        ebox.border_width = 0;
        add(ebox);

        /* Sort out our popover */
        this.create_brightness_popover();

        /* Catch scroll wheel events */
        ebox.add_events(Gdk.EventMask.SCROLL_MASK);
        ebox.scroll_event.connect(on_scroll_event);

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
                brightness_scale.set_value(this.get_brightness());
                this.manager.show_popover(ebox);
            }
            return Gdk.EVENT_STOP;
        });

        show_all();

        try {
            logind_manager = Bus.get_proxy_sync (BusType.SYSTEM, LOGIND_BUS_NAME, LOGIND_BUS_PATH);
            if(logind_manager != null){
                logind_manager.prepare_for_sleep.connect((start) => {
                    if(!start){
                        new Thread<int>("", () => {
                            Thread.usleep(5000000);
                            this.set_brightness(this.get_brightness());
                            return 0;
                        });
                    }
                });
            }
        } catch (IOError e) {
            print(e.message);
        }
    }

    /**
     * Create the GtkPopover to display on primary click action, with an adjustable
     * scale
     */
    private void create_brightness_popover()
    {
        popover = new Budgie.Popover(ebox);
        Gtk.Box? popover_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        popover.add(popover_box);
        Gtk.Button? sub_button = new Gtk.Button.from_icon_name("list-remove-symbolic", Gtk.IconSize.BUTTON);
        Gtk.Button? plus_button = new Gtk.Button.from_icon_name("list-add-symbolic", Gtk.IconSize.BUTTON);

        /* + button */
        popover_box.pack_start(plus_button, false, false, 1);
        plus_button.clicked.connect(()=> {
            adjust_brightness_increment(+step_size);
        });

        brightness_scale = new Gtk.Scale.with_range(Gtk.Orientation.VERTICAL, 0, this.max_brightness, 1);
        popover_box.pack_start(brightness_scale, false, false, 0);
        brightness_scale.set_value(this.get_brightness());

        /* Hook up the value_changed event */
        scale_id = brightness_scale.value_changed.connect(on_scale_changed);

        /* - button */
        popover_box.pack_start(sub_button, false, false, 1);
        sub_button.clicked.connect(()=> {
            adjust_brightness_increment(-step_size);
        });

        /* Refine visual appearance of the scale.. */
        brightness_scale.set_draw_value(false);
        brightness_scale.set_size_request(-1, 100);

        /* Flat buttons only pls :) */
        sub_button.get_style_context().add_class("flat");
        sub_button.get_style_context().add_class("image-button");
        plus_button.get_style_context().add_class("flat");
        plus_button.get_style_context().add_class("image-button");

        /* Focus ring is ugly and unnecessary */
        sub_button.set_can_focus(false);
        plus_button.set_can_focus(false);
        brightness_scale.set_can_focus(false);
        brightness_scale.set_inverted(true);

        popover.get_child().show_all();
    }

    /**
     * Update from scroll events. turn brightness up + down.
     */
    protected bool on_scroll_event(Gdk.EventScroll event)
    {

        uint32 brightness = this.get_brightness();
        var orig_brightness = brightness;

        switch (event.direction) {
            case Gdk.ScrollDirection.UP:
                brightness += (uint32)step_size;
                break;
            case Gdk.ScrollDirection.DOWN:
                brightness -= (uint32)step_size;
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
        if (brightness > max_brightness) {
            brightness = (uint32)max_brightness;
        }

        SignalHandler.block(brightness_scale, scale_id);
        this.set_brightness((int)brightness);
        SignalHandler.unblock(brightness_scale, scale_id);

        return true;
    }

    /**
     * The scale changed value - update brightness
     */
    private void on_scale_changed()
    {
        int brightness_value = (int) brightness_scale.get_value();

        /* Avoid recursion ! */
        SignalHandler.block(brightness_scale, scale_id);
        this.set_brightness(brightness_value);
        SignalHandler.unblock(brightness_scale, scale_id);
    }

    /**
     * Adjust the brightness by a given +/- increment and bounds limit it
     */
    private void adjust_brightness_increment(int increment)
    {
        int32 brightness = this.get_brightness();
        brightness += (int32)increment;

        if (brightness < 0) {
            brightness = 0;
        } else if (brightness > max_brightness) {
            brightness = (int32) max_brightness;
        }

        SignalHandler.block(brightness_scale, scale_id);
        this.set_brightness(brightness);
        this.brightness_scale.set_value(brightness);
        SignalHandler.unblock(brightness_scale, scale_id);
    }

    /**
     * Gets max brightness from gnome-settings-daemon
     */
    private int get_max_brightness() {
        try {
            string[] spawn_args = {"pkexec", "/usr/lib/gnome-settings-daemon/gsd-backlight-helper",
                "--get-max-brightness"};
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
        return 15;
    }

    /**
     * Gets max brightness from gnome-settings-daemon
     */
    private int get_brightness() {
        try {
            string[] spawn_args = {"pkexec", "/usr/lib/gnome-settings-daemon/gsd-backlight-helper",
                "--get-brightness"};
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
        return 0;
    }

    /**
     * Gets max brightness from gnome-settings-daemon
     */
    private void set_brightness(int brightness) {
        try {
            string[] spawn_args = {"pkexec", "/usr/lib/gnome-settings-daemon/gsd-backlight-helper",
                "--set-brightness", brightness.to_string()};
            string[] spawn_env = Environ.get ();
            string ls_stdout;
            string ls_stderr;
            int ls_status;
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
