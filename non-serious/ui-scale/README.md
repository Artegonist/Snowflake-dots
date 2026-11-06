# ui-scale

Auto and manual UI scaling for all Snowflake windows (Hub, audio, player, Wi-Fi, Bluetooth, battery,
system, clipboard, pet, macros, power menu, OSD).

Files mirror `~/.config/quickshell/snowflake/`. To try it:

    cp -a ~/.config/quickshell/snowflake ~/snowflake-backup
    cp -r ui-scale/* ~/.config/quickshell/snowflake/   # skip this README if you like

Scale = (min(width/1920, height/1080))^0.85, clamped to 0.65..2.0, never larger than fits the screen.
Manual settings: Hub -> Settings -> Interface. Stored in ~/.local/share/snowflake/hub/ui.json.
