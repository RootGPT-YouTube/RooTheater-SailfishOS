.pragma library

// SPARQL builders for the Tracker3-backed music library. Queries run through
// the grl-tracker3 grilo source and federate (SERVICE <dbus:…>) to
// org.freedesktop.Tracker3.Miner.Files — the public system audio index, the
// same one the stock Media app reads, so titles/artists/albums match it
// exactly, including for files our ffmpeg probe cannot interpret. Predicate
// names are the public Tracker3 audio ontology; the outer SELECT column names
// are the grl-tracker3 grilo contract.
//
// Column names in the outer SELECT are the ones grl-tracker3 understands
// (type, id, url, duration, author, title, album, albumArtist, childcount).
// Extra sort keys (?tracknumber, ?setnumber, ?modified, ?no*) are projected
// only by the inner SELECT: they stay in scope for ORDER BY but are never
// handed to grilo. The ?no* flags are 1 when the tag is missing/unusable so
// "unknowns after knowns" holds for every sort mode.

var MINER = "SERVICE <dbus:org.freedesktop.Tracker3.Miner.Files> "

function escapeSparql(s) {
    return String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
}

// file:// URL prefix for a storage root, percent-encoded the way tracker
// stores file URLs (g_filename_to_uri): UTF-8 %-escapes, "#"/"?" encoded.
function fileUrlPrefix(rootPath) {
    var p = encodeURI(rootPath).replace(/#/g, "%23").replace(/\?/g, "%3F")
    if (p.charAt(p.length - 1) !== "/")
        p += "/"
    return "file://" + p
}

// FILTER restricting file resource `v` to a storage root, optionally
// excluding a subtree (the internal storage excludes android_storage, which
// is its own storage entry).
function rootFilter(v, opts) {
    if (!opts.rootPath)
        return ""
    var f = "FILTER(STRSTARTS(STR(" + v + "), \"" + fileUrlPrefix(opts.rootPath) + "\")"
    if (opts.excludePath)
        f += " && !STRSTARTS(STR(" + v + "), \"" + fileUrlPrefix(opts.excludePath) + "\")"
    return f + ") "
}

function _dir(desc) { return desc ? "DESC" : "ASC" }

// Artist identity used across the artists list and the per-artist filter:
// album artist wins over track artist (mirrors the native Media app).
function _artistKey(song) {
    return "tracker:coalesce(nmm:artistName(nmm:albumArtist(nmm:musicAlbum(" + song + "))), "
         + "nmm:artistName(nmm:artist(" + song + ")), \"\")"
}

// opts: rootPath, excludePath, unknownArtist, unknownAlbum,
//       albumId ("" none, "0" unknown album, else album urn),
//       artistFilter (undefined none, "" unknown artist, else artist name),
//       sortBy ("album"|"track"|"artist"|"title"|"date"), sortDesc (bool)
function songsQuery(opts) {
    var inner = ""
    if (opts.albumId) {
        if (opts.albumId === "0")
            inner += "FILTER NOT EXISTS { ?song1 nmm:musicAlbum ?anyAlbum } "
        else
            inner += "?song1 nmm:musicAlbum \"" + escapeSparql(opts.albumId) + "\" . "
    }
    if (opts.artistFilter !== undefined && opts.artistFilter !== null)
        inner += "FILTER(" + _artistKey("?song1") + " = \""
               + escapeSparql(opts.artistFilter) + "\") "
    inner += rootFilter("?url1", opts)

    var d = _dir(opts.sortDesc)
    var order
    switch (opts.sortBy) {
    case "title":
        order = "ORDER BY ASC(?notitle) " + d + "(fn:lower-case(?title))"
        break
    case "track":
        order = "ORDER BY ASC(?notrack) " + d + "(?setnumber) " + d + "(?tracknumber) "
              + "ASC(fn:lower-case(?title))"
        break
    case "artist":
        order = "ORDER BY ASC(?noartist) " + d + "(fn:lower-case(?author)) "
              + "ASC(?noalbum) ASC(fn:lower-case(?album)) "
              + "ASC(?setnumber) ASC(?tracknumber) ASC(fn:lower-case(?title))"
        break
    case "date":
        order = "ORDER BY " + d + "(?modified) ASC(fn:lower-case(?title))"
        break
    default: // "album"
        order = "ORDER BY ASC(?noalbum) " + d + "(fn:lower-case(?album)) "
              + "ASC(?setnumber) ASC(?tracknumber) ASC(fn:lower-case(?title))"
        break
    }

    return "SELECT 1 AS ?type ?song AS ?id ?url ?duration ?author ?title ?album ?albumArtist "
         + "WHERE { " + MINER + "{ GRAPH tracker:Audio { "
         + "SELECT ?song1 AS ?song ?url1 AS ?url "
         + "  nfo:duration(?song1) AS ?duration "
         + "  tracker:coalesce(nmm:artistName(nmm:artist(?song1)), \""
         +      escapeSparql(opts.unknownArtist) + "\") AS ?author "
         + "  tracker:coalesce(nie:title(?song1), tracker:string-from-filename(?filename)) AS ?title "
         + "  tracker:coalesce(nie:title(nmm:musicAlbum(?song1)), \""
         +      escapeSparql(opts.unknownAlbum) + "\") AS ?album "
         + "  nmm:artistName(nmm:albumArtist(nmm:musicAlbum(?song1))) AS ?albumArtist "
         + "  nmm:setNumber(nmm:musicAlbumDisc(?song1)) AS ?setnumber "
         + "  nmm:trackNumber(?song1) AS ?tracknumber "
         + "  nfo:fileLastModified(?url1) AS ?modified "
         + "  IF(tracker:coalesce(nie:title(nmm:musicAlbum(?song1)), \"\") = \"\", 1, 0) AS ?noalbum "
         + "  IF(tracker:coalesce(nmm:artistName(nmm:artist(?song1)), \"\") = \"\", 1, 0) AS ?noartist "
         + "  IF(tracker:coalesce(nmm:trackNumber(?song1), 0) = 0, 1, 0) AS ?notrack "
         + "  IF(tracker:coalesce(nie:title(?song1), \"\") = \"\", 1, 0) AS ?notitle "
         + "WHERE { "
         + "  ?song1 a nmm:MusicPiece ; nie:isStoredAs ?url1 . "
         + "  ?url1 nfo:fileName ?filename . "
         + "  ?url1 nie:dataSource/tracker:available true . "
         + inner
         + "} } } } " + order
}

// opts: rootPath, excludePath, unknownArtist, unknownAlbum, multipleArtists,
//       artistFilter (as above), sortBy ("album"|"artist"), sortDesc
// ?url carries a sample track of the album so the list can show its embedded
// cover art via the rttrackcover image provider.
function albumsQuery(opts) {
    var inner = ""
    if (opts.artistFilter !== undefined && opts.artistFilter !== null)
        inner += "FILTER(" + _artistKey("?song") + " = \""
               + escapeSparql(opts.artistFilter) + "\") "
    inner += rootFilter("?file", opts)

    var d = _dir(opts.sortDesc)
    var order = (opts.sortBy === "artist")
        ? "ORDER BY " + d + "(fn:lower-case(?author)) ASC(?noalbum) ASC(fn:lower-case(?title))"
        : "ORDER BY ASC(?noalbum) " + d + "(fn:lower-case(?title))"

    return "SELECT 4 AS ?type ?album AS ?id ?title ?author ?childcount ?url "
         + "WHERE { " + MINER + "{ GRAPH tracker:Audio { "
         + "SELECT tracker:coalesce(nmm:musicAlbum(?song), 0) AS ?album "
         + "  tracker:coalesce(nie:title(nmm:musicAlbum(?song)), \""
         +      escapeSparql(opts.unknownAlbum) + "\") AS ?title "
         + "  IF(COUNT(DISTINCT(tracker:coalesce(nmm:albumArtist(nmm:musicAlbum(?song)), nmm:artist(?song), 0))) > 1, "
         + "     \"" + escapeSparql(opts.multipleArtists) + "\", "
         + "     tracker:coalesce(nmm:artistName(nmm:albumArtist(nmm:musicAlbum(?song))), "
         + "                      nmm:artistName(nmm:artist(?song)), \""
         +      escapeSparql(opts.unknownArtist) + "\")) AS ?author "
         + "  COUNT(DISTINCT(?song)) AS ?childcount "
         + "  SAMPLE(?file) AS ?url "
         + "  IF(tracker:coalesce(nie:title(nmm:musicAlbum(?song)), \"\") = \"\", 1, 0) AS ?noalbum "
         + "WHERE { "
         + "  ?song a nmm:MusicPiece ; nie:isStoredAs ?file . "
         + "  ?file nie:dataSource/tracker:available true . "
         + inner
         + "} GROUP BY ?album } } } " + order
}

// opts: rootPath, excludePath, unknownArtist, sortBy ("name"|"count"), sortDesc
function artistsQuery(opts) {
    var inner = rootFilter("?file", opts)
    var d = _dir(opts.sortDesc)
    var order = (opts.sortBy === "count")
        ? "ORDER BY " + d + "(?childcount) ASC(?noartist) ASC(fn:lower-case(?title))"
        : "ORDER BY ASC(?noartist) " + d + "(fn:lower-case(?title))"

    return "SELECT 4 AS ?type ?artistName AS ?id ?title ?childcount "
         + "WHERE { " + MINER + "{ GRAPH tracker:Audio { "
         + "SELECT " + _artistKey("?song") + " AS ?artistName "
         + "  tracker:coalesce(nmm:artistName(nmm:albumArtist(nmm:musicAlbum(?song))), "
         + "                   nmm:artistName(nmm:artist(?song)), \""
         +      escapeSparql(opts.unknownArtist) + "\") AS ?title "
         + "  COUNT(DISTINCT ?song) AS ?childcount "
         + "  IF(" + _artistKey("?song") + " = \"\", 1, 0) AS ?noartist "
         + "WHERE { "
         + "  ?song a nmm:MusicPiece ; nie:isStoredAs ?file . "
         + "  ?file nie:dataSource/tracker:available true . "
         + inner
         + "} GROUP BY ?artistName ?noartist } } } " + order
}

// Tiny count-only queries for the gallery category rows. Each returns one
// container row whose ?childcount holds the number.
function _countQuery(expr, opts) {
    return "SELECT 4 AS ?type \"rt-count\" AS ?id ?childcount "
         + "WHERE { " + MINER + "{ GRAPH tracker:Audio { "
         + "SELECT " + expr + " AS ?childcount "
         + "WHERE { "
         + "  ?song a nmm:MusicPiece ; nie:isStoredAs ?file . "
         + "  ?file nie:dataSource/tracker:available true . "
         + rootFilter("?file", opts)
         + "} } } }"
}

function songsCountQuery(opts) {
    return _countQuery("COUNT(DISTINCT ?song)", opts)
}

function albumsCountQuery(opts) {
    return _countQuery("COUNT(DISTINCT tracker:coalesce(nmm:musicAlbum(?song), 0))", opts)
}

function artistsCountQuery(opts) {
    return _countQuery("COUNT(DISTINCT " + _artistKey("?song") + ")", opts)
}

// media.url ("file:///a%20b/c.mp3") → local path ("/a b/c.mp3").
function urlToPath(u) {
    var s = String(u)
    if (s.indexOf("file://") === 0)
        s = s.substring(7)
    return decodeURIComponent(s)
}

// Seconds → "m:ss" (or "h:mm:ss").
function formatDuration(secs) {
    secs = Math.max(0, secs | 0)
    var h = Math.floor(secs / 3600)
    var m = Math.floor((secs % 3600) / 60)
    var s = secs % 60
    function two(n) { return n < 10 ? "0" + n : "" + n }
    return h > 0 ? h + ":" + two(m) + ":" + two(s) : m + ":" + two(s)
}
