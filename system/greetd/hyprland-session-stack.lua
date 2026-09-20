hl.env("GTK_USE_PORTAL", "0")
hl.env("GDK_DEBUG", "no-portals")

hl.on("hyprland.start", function()
    -- Use ReGreet on failure; stop portals before closing Wayland to avoid crashes.
    hl.exec_cmd("/usr/local/lib/session-stack-greeter/launch-greeter || regreet; systemctl --user stop xdg-desktop-portal.service xdg-desktop-portal-hyprland.service >/dev/null 2>&1 || true; hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1")
end)

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "auto",
})

hl.config({
    input = {
        kb_layout = "us",
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        disable_hyprland_guiutils_check = true,
    },
})
