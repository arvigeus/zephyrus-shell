import QtQuick
import "../services"

Item {
    id: root
    visible: false
    property bool observing: false
    property var profiles: []
    property bool available: false
    property bool loaded: false
    property bool refreshing: false
    property string pendingProfile: ""
    property string pendingAction: ""
    property string errorProfile: ""
    property string error: ""
    property string statusError: ""
    readonly property bool busy: pendingProfile !== ""

    function apply(result) {
        profiles = result.profiles || [];
        available = !!result.available;
        statusError = result.error || "";
        loaded = true;
    }
    function refresh() {
        if (refreshing || busy) return;
        refreshing = true;
        worker.request("status", {}, (result, failure) => {
            refreshing = false;
            if (failure) { statusError = failure; loaded = true; }
            else apply(result);
        });
    }
    function toggle(profile) {
        if (busy || refreshing || profile.transitioning) return;
        pendingProfile = profile.id;
        pendingAction = profile.active ? "disconnect" : "connect";
        error = "";
        errorProfile = "";
        worker.request(pendingAction, {profile: profile.id}, (result, failure) => {
            pendingProfile = "";
            pendingAction = "";
            if (failure) { errorProfile = profile.id; error = failure; refresh(); }
            else apply(result);
        });
    }
    onObservingChanged: if (observing) refresh()
    Component.onCompleted: if (observing) refresh()
    Worker { id: worker; backend: "settings/vpn.py"; serviceName: "WireGuard"; startOnDemand: true }
    Timer { interval: 5000; repeat: true; running: root.observing; onTriggered: root.refresh() }
}
