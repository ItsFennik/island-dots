# Notifications

Island is the notification daemon (`org.freedesktop.Notifications`). Toasts grow from the bar and every notification stays in Notification Centre.

- Config: `services/Notifs.qml`, `popouts/Notifications.qml`
- Settings: Notifications > Banner duration, Focus > Do Not Disturb
- IPC: `qs -c island ipc call notifs <toggle|dnd|clear|dismiss>`

Click a toast or a row for its default action. Critical notifications stay until dismissed and ignore Do Not Disturb. The centre shows the unread count on the bell in the bar.

Only one process can own `org.freedesktop.Notifications`. Stop any other daemon (dunst, mako, swaync) before starting Island. Test with:

```sh
notify-send -a Island "Island" "Notifications work"
```

Notification state is in memory only.
