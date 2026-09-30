import QtQuick
import QtTest
import "../../attention" as Attention

TestCase {
    name: "WeatherPanel"
    width: 600; height: 900; visible: true
    when: windowShown

    Attention.WeatherPanel { id: panel; width: 382; height: implicitHeight }

    function init() {
        panel.width = 382;
        panel.forecast = {
            location: "Ha Long", observed_at: "2026-09-30T11:30",
            current: {temperature: 32.6, feels_like: 39.1, humidity: 64, wind: 11.9,
                      icon: "sun", description: "Mainly clear"},
            days: Array.from({length: 7}, (_, i) => ({date: i === 0 ? "2026-09-30" : "2026-10-0" + i,
                high: 33, low: 27, icon: "cloud-drizzle", description: "Drizzle"})),
            hours: Array.from({length: 24}, (_, i) => ({time: "2026-09-30T" + (12 + i % 12) + ":00",
                temperature: 31, icon: "cloud-rain", description: "Rain", precipitation_probability: i === 0 ? null : 65}))
        };
    }
    function test_hourly_list_fits_beside_current_conditions() {
        compare(panel.hours.length, 6);
        compare(panel.current.icon, "sun");
        compare(panel.days[0].icon, "cloud-drizzle");
        const current = findChild(panel, "weatherCurrent");
        const hours = findChild(panel, "weatherHours");
        const metrics = findChild(panel, "weatherMetrics");
        compare(metrics.parent, current);
        const description = findChild(panel, "weatherDescription");
        tryVerify(() => metrics.y <= description.y + description.height + 13);
        tryVerify(() => hours.mapToItem(panel, 0, 0).x >= current.width);
        const rows = hours.children.filter(item => item.objectName === "weatherHour");
        compare(rows.length, 6);
        for (const row of rows) {
            const bottomRight = row.mapToItem(panel, row.width, row.height);
            verify(bottomRight.x <= panel.width + 1);
            verify(bottomRight.y <= panel.height + 1);
        }
    }
    function test_narrow_panel_stacks_without_losing_hours() {
        panel.width = 280;
        const current = findChild(panel, "weatherCurrent");
        const hours = findChild(panel, "weatherHours");
        tryVerify(() => hours.mapToItem(panel, 0, 0).y >= current.mapToItem(panel, 0, current.height).y);
        compare(panel.hours.length, 6);
        verify(hours.mapToItem(panel, hours.width, 0).x <= panel.width + 1);
    }
    function test_older_saved_forecast_remains_usable_without_hours() {
        const saved = Object.assign({}, panel.forecast);
        delete saved.hours;
        saved.stale = true;
        panel.forecast = saved;
        compare(panel.hours.length, 0);
        compare(panel.ready, true);
        compare(panel.days.length, 7);
    }
}
