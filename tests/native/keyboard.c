#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

// The virtual-keyboard protocol is used only against the test compositor.
static const struct wl_interface keyboard_interface;
static const struct wl_interface *create_types[] = {&wl_seat_interface, &keyboard_interface};
static const struct wl_message manager_requests[] = {{"create_virtual_keyboard", "on", create_types}};
static const struct wl_interface manager_interface = {"zwp_virtual_keyboard_manager_v1", 1, 1, manager_requests, 0, NULL};
static const struct wl_message keyboard_requests[] = {
    {"keymap", "uhu", NULL}, {"key", "uuu", NULL}, {"modifiers", "uuuu", NULL}, {"destroy", "", NULL}
};
static const struct wl_interface keyboard_interface = {"zwp_virtual_keyboard_v1", 1, 4, keyboard_requests, 0, NULL};
static struct wl_proxy *manager;
static struct wl_seat *seat;

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    (void)data; (void)version;
    if (!strcmp(interface, manager_interface.name))
        manager = wl_registry_bind(registry, name, &manager_interface, 1);
    else if (!strcmp(interface, "wl_seat") && !seat)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}
static const struct wl_registry_listener listener = {global, removed};

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 3;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !manager || !seat) return 4;
    struct wl_proxy *keyboard = wl_proxy_marshal_flags(manager, 0, &keyboard_interface, 1, 0, seat, NULL);
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = {.layout = "us"};
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (!keyboard || !keymap) return 5;
    char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    size_t size = strlen(text) + 1;
    int fd = memfd_create("zephyrus-test-keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, text, size) != (ssize_t)size) return 6;
    wl_proxy_marshal_flags(keyboard, 0, NULL, 1, 0, 1u, fd, (uint32_t)size);
    wl_proxy_marshal_flags(keyboard, 2, NULL, 1, 0, 0u, 0u, 0u, 0u);
    if (wl_display_roundtrip(display) < 0) return 7;
    uint32_t key = (uint32_t)strtoul(argv[1], NULL, 10);
    wl_proxy_marshal_flags(keyboard, 1, NULL, 1, 0, 1u, key, 1u);
    wl_proxy_marshal_flags(keyboard, 1, NULL, 1, 0, 2u, key, 0u);
    if (wl_display_roundtrip(display) < 0) return 8;
    // Let the focused client consume the events before destroying its keyboard.
    struct timespec delay = {.tv_nsec = 100000000};
    nanosleep(&delay, NULL);
    wl_proxy_marshal_flags(keyboard, 3, NULL, 1, WL_MARSHAL_FLAG_DESTROY);
    wl_display_roundtrip(display);
    close(fd); free(text);
    xkb_keymap_unref(keymap); xkb_context_unref(context);
    wl_display_disconnect(display);
    return 0;
}
