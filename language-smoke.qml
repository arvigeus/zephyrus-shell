import QtQuick
import Quickshell
import Quickshell.Io
import "core"
import "shell"

ShellRoot {
    FloatingWindow {
        id: window
        implicitWidth: 360; implicitHeight: 250; color: Theme.background
        LanguageButton { id: button; x: 280; y: 12; barWindow: window }
        Process {
            id: external
            property string language: "bg"
            command: ["language-fixture", language]
            onExited: {
                InputLanguage.handleLayoutEvent("activelayout", "laptop," + (language === "bg" ? "Bulgarian (phonetic)" : "English (US)"));
            }
        }
        Connections {
            target: button
            function onRestoringInputFocusChanged() {
                if (button.restoringInputFocus) Qt.callLater(() => {
                    if (smoke.phase !== 2) return;
                    smoke.require(!button.menuVisible, "Focus handoff reopened the menu");
                    smoke.require(smoke.find(button, "languageLoading").running, "Spinner stopped during focus handoff");
                    smoke.capturedHandoff = true;
                });
            }
        }
        Timer {
            id: smoke
            interval: 100; running: true; repeat: true
            property int ticks: 0
            property int phase: 0
            property bool capturedLoading: false
            property bool capturedHandoff: false
            readonly property bool standalone: Quickshell.env("ZEPHYRUS_LANGUAGE_STANDALONE") === "1"
            function find(item, name) {
                if (item.objectName === name) return item;
                for (const child of item.children || []) {
                    const found = find(child, name); if (found) return found;
                }
                return null;
            }
            function require(value, message) {
                if (!value) { console.error("LANGUAGE FAIL", message); Qt.exit(1); }
            }
            onTriggered: {
                if (++ticks > 80) { console.error("LANGUAGE FAIL timeout", phase); Qt.exit(1); return; }
                if (InputLanguage.busy || button.restoringInputFocus) {
                    if (phase === 2 && InputLanguage.selecting) {
                        require(!button.menuVisible, "Selection left the menu open during startup");
                        const spinner = find(button, "languageLoading");
                        require(spinner && spinner.visible && spinner.running, "Loading spinner missing");
                        require(InputLanguage.flag === "🇻🇳", "Loading indicator is not over the Vietnamese flag");
                        if (!capturedLoading) {
                            capturedLoading = true;
                            button.grabToImage(result => result.saveToFile(Paths.file("tests/artifacts/language-loading.png")));
                        }
                    }
                    if (phase === 2 && button.restoringInputFocus) {
                        require(!button.menuVisible, "Focus handoff reopened the menu");
                        require(find(button, "languageLoading").running, "Spinner stopped before focus handoff finished");
                        capturedHandoff = true;
                    }
                    return;
                }
                if (phase === 2 && !standalone) require(capturedHandoff, "Vietnamese selection skipped the focus handoff");
                if (phase === 0) {
                    InputLanguage.refresh();
                    InputLanguage.select("bg"); phase = 10;
                } else if (phase === 10) {
                    require(InputLanguage.language === "bg", "Selection during a status query was lost");
                    InputLanguage.select("en"); phase = 11;
                } else if (phase === 11) {
                    require(InputLanguage.language === "en", "English selection did not update indicator");
                    button.clicked(); phase = 1;
                } else if (phase === 1) {
                    require(button.menuVisible, "Dropdown did not open");
                    const vietnamese = find(button.menuWindow.contentItem, "language-vi");
                    if (!standalone && !vietnamese) return;
                    const english = find(button.menuWindow.contentItem, "language-en");
                    const bulgarian = find(button.menuWindow.contentItem, "language-bg");
                    const englishIcon = find(button.menuWindow.contentItem, "language-icon-en");
                    require(english && english.text === "English", "English label missing");
                    require(bulgarian && bulgarian.text === "Български", "Native Bulgarian label missing");
                    require(standalone ? !vietnamese : vietnamese.text === "Tiếng Việt", "Native Vietnamese label or visibility is incorrect");
                    require(!InputLanguage.description.includes("Install"), "Missing prerequisites leaked into the tooltip");
                    require(englishIcon && englishIcon.visible && englishIcon.name === "globe", "English does not use a neutral globe");
                    require(InputLanguage.flag === "", "English still uses flag artwork");
                    require(find(button.menuWindow.contentItem, "language-secondary-bg").visible, "Default Bulgarian secondary is not checked");
                    require(!find(button.menuWindow.contentItem, "language-secondary-en").visible, "English should never be a secondary language");
                    find(button.menuWindow.contentItem, "languageMenuPanel").grabToImage(result => {
                        if (!result.saveToFile(Paths.file("tests/artifacts/language-menu" + (standalone ? "-unavailable" : "") + ".png"))) { Qt.exit(1); return; }
                        if (standalone) {
                            require(!vietnamese && bulgarian.enabled && english.enabled, "Missing prerequisites did not hide Vietnamese");
                            bulgarian.clicked(); phase = 4;
                        } else {
                            vietnamese.clicked();
                            require(!button.menuVisible, "Vietnamese selection did not close the menu immediately");
                            phase = 2;
                        }
                    }); phase = -1;
                } else if (phase === 2) {
                    require(!button.menuVisible, "Dropdown did not close");
                    require(InputLanguage.secondary === "vi" && InputLanguage.language === "vi", "Vietnamese selection failed");
                    InputLanguage.select("en"); phase = 3;
                } else if (phase === 3) {
                    require(InputLanguage.secondary === "vi" && InputLanguage.language === "en", "English discarded Vietnamese pair");
                    button.clicked(); phase = 31;
                } else if (phase === 31) {
                    const checkedVietnamese = find(button.menuWindow.contentItem, "language-secondary-vi");
                    if (!checkedVietnamese) return;
                    require(checkedVietnamese.visible, "Vietnamese secondary is not checked while English is active");
                    require(!find(button.menuWindow.contentItem, "language-secondary-bg").visible, "Both secondary languages are checked");
                    require(!find(button.menuWindow.contentItem, "language-secondary-en").visible, "Active English was marked as secondary");
                    find(button.menuWindow.contentItem, "languageMenuPanel").grabToImage(result => {
                        if (!result.saveToFile(Paths.file("tests/artifacts/language-menu-vietnamese.png"))) { Qt.exit(1); return; }
                        button.clicked(); InputLanguage.select("bg"); phase = 4;
                    }); phase = -1;
                } else if (phase === 4) {
                    require(InputLanguage.secondary === "bg" && InputLanguage.language === "bg", "Bulgarian pair was not restored");
                    InputLanguage.select("en"); phase = 5;
                } else if (phase === 5) {
                    require(InputLanguage.language === "en", "English selection did not update indicator");
                    // An event during a delayed status read needs a fresh query.
                    InputLanguage.refresh();
                    external.language = "bg"; external.running = true; phase = 6;
                } else if (phase === 6) {
                    if (external.running) return;
                    require(InputLanguage.language === "bg", "Layout event during a query was lost, or wrong keyboard was read");
                    external.language = "en"; external.running = true; phase = 7;
                } else if (phase === 7) {
                    if (external.running || InputLanguage.language !== "en") return;
                    InputLanguage.select("bg"); phase = 8;
                } else if (phase === 8) {
                    require(InputLanguage.language === "bg", "Bulgarian menu selection did not update indicator");
                    button.grabToImage(result => {
                        if (!result.saveToFile(Paths.file("tests/artifacts/language-button.png"))) { Qt.exit(1); return; }
                        console.log("LANGUAGE PASS: labeled dropdown, neutral English globe, EN/VI selection, EN/BG restoration, queued selection, layout events during queries, secondary keyboard");
                        Qt.quit();
                    }); phase = -1;
                }
            }
        }
    }
}
