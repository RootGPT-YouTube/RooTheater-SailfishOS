import QtQuick 2.6
import org.nemomobile.grilo 0.1

// Music library model backed by the system Tracker3 index, queried through
// the grl-tracker3 grilo source (the exact mechanism the stock Media app
// uses; needs the MediaIndexing sailjail permission). Set `query` to one of
// the MusicQueries.js builders; rows expose the `media` role (GriloMedia:
// title, author, album, url, duration, childCount, id, …).
GriloModel {
    id: griloModel

    property alias query: querySource.query
    property alias fetching: querySource.fetching

    signal finished()

    function refresh() {
        querySource.safeRefresh()
    }

    source: GriloQuery {
        id: querySource

        // Re-run shortly after the index changes (file added/removed/retagged)
        // so the library keeps itself current, like the native player does.
        property Timer delayedRefresh: Timer {
            interval: 3000
            onTriggered: querySource.safeRefresh()
        }

        source: "grl-tracker3-source"
        registry: GriloRegistry {
            Component.onCompleted: loadPluginById("grl-tracker3")
        }

        function safeRefresh() {
            if (query && query != "" && available)
                refresh()
        }

        onQueryChanged: safeRefresh()
        onAvailableChanged: safeRefresh()
        onContentUpdated: delayedRefresh.restart()
        Component.onCompleted: finished.connect(griloModel.finished)
    }
}
