# Budgie Brightness Control Applet
This applet allows you to controll screen brightness.

---

## Dependencies
```
budgie-1.0 >= 2
gnome-desktop-3.0
gnome-settings-daemon
gtk+-3.0 >= 3.18
glib-2.0
libpeas-1.0 >= 1.8.0
vala
```

### Installing

**From source**  
```bash
mkdir build && cd build
meson --prefix /usr --buildtype=plain ..
ninja
sudo ninja install
```

### License
This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or at your option) any later version.

Status applet of Budgie Desktop is used as a templete for this project. Inspired from Erwin Rohde's indicator-brightness.
