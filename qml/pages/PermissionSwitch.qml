import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0

// Soft-gate toggle for one app resource (dconf-backed, default granted).
// Sailjail grants every permission declared in the .desktop in one go at
// startup; this switch does NOT revoke the system permission (only the
// SailfishOS Settings can) — it is an app-side gate that RooTheater honours
// BEFORE touching the resource. Same model as RooTelegram's permission page.
TextSwitch {
    property string perm

    ConfigurationValue {
        id: cfg
        key: "/apps/harbour-rootheater/perm/" + perm
        defaultValue: true
    }

    width: parent.width
    automaticCheck: false
    checked: cfg.value !== false && cfg.value !== "false"
    onClicked: cfg.value = !checked
}
