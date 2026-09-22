#include "my_application.h"

int main(int argc, char** argv) {
  // Native Wayland only exposes the clipboard to the focused window and has no
  // global hotkeys, so default to XWayland. Users can override with
  // GDK_BACKEND=wayland in the environment.
  g_setenv("GDK_BACKEND", "x11", FALSE);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
