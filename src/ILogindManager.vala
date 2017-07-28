namespace BrightnessControl {
    const string LOGIND_BUS_NAME = "org.freedesktop.login1";
    const string LOGIND_BUS_PATH = "/org/freedesktop/login1";

    [DBus (name = "org.freedesktop.login1.Manager")]
    interface ILogindManager : DBusProxy {
        public abstract signal void prepare_for_sleep (bool start);
    }
}
