
custom_target('plugin-file-workspaces',
    input : 'BudgieBrightnessControlApplet.plugin.in',
    output : 'BudgieBrightnessControlApplet.plugin',
    command : ['cp', '@INPUT@', '@OUTPUT@'],
    install : true,
    install_dir: LIB_INSTALL_DIR,
)

ValaArgs = []

if DEPENDENCY_GNOME_SETTINGS_DAEMON.version().version_compare('>=3.36.0')
    ValaArgs += ['-D', 'GNOME_SETTINGS_DAEMON_3_36_0']
endif

if DEPENDENCY_GNOME_SETTINGS_DAEMON.version().version_compare('>=3.32.0')
    ValaArgs += ['-D', 'GNOME_SETTINGS_DAEMON_3_32_0']
endif

if DEPENDENCY_GNOME_SETTINGS_DAEMON.version().version_compare('<3.32.0')
    ValaArgs += ['-D', 'GNOME_SETTINGS_DAEMON_OLDER_THAN_3_32_0']
endif

applet_budgie_brightness_control_sources = [
    'BudgieBrightnessControlApplet.vala',
    'ILogindManager.vala',
]

applet_budgie_brightness_control_deps = [
    dep_gtk3,
    dep_glib,
    dep_peas,
    dep_budgie,
]

shared_library(
    'budgiebrigtnesscontrolapplet',
    applet_budgie_brightness_control_sources,
    dependencies: applet_budgie_brightness_control_deps,
    vala_args: ValaArgs,
    c_args: [
        '-DWNCK_I_KNOW_THIS_IS_UNSTABLE',
    ],
    install: true,
    install_dir: LIB_INSTALL_DIR,
)
