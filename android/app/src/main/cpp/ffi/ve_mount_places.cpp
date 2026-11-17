// Adds a mounted vault to the file manager's sidebar (Linux).
//
// A FUSE mount does not appear in Dolphin's or Nautilus' sidebar by itself -- user-space mounts are not
// "devices" to them -- so the mount would sit in a hidden folder and look as if nothing happened. Like
// Cryptomator's integrations-linux, this edits the two bookmark files those file managers watch:
//
//   * KDE Dolphin     $XDG_DATA_HOME/user-places.xbel      (XBEL; tagged with our own metadata owner)
//   * GTK file managers (Nautilus, Thunar, Nemo, PCManFM, ...)  $XDG_CONFIG_HOME/gtk-3.0/bookmarks
//
// Only files that already exist are touched (a missing file means that file manager is not in use), they are
// replaced atomically, and everything we add is removed again on unmount. A small state file remembers what
// was added, so entries left behind by a crash are cleaned up the next time the app mounts something.
// Set VE_NO_PLACES=1 to disable all of it.

#include "ve_mount_places.h"

#include <sys/stat.h>
#include <unistd.h>
#include <pwd.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <mutex>
#include <random>
#include <sstream>
#include <string>
#include <vector>

namespace vemount {

namespace {

constexpr const char* kOwner = "https://vaultexplorer.app";
constexpr size_t kMaxFile = 1u << 20;  // refuse to rewrite anything bigger than 1 MiB (xbel is verbose)

std::mutex gMu;

std::string envOr(const char* name, const std::string& fallback) {
    const char* v = std::getenv(name);
    return (v && *v) ? std::string(v) : fallback;
}

std::string homeDir() {
    const char* h = std::getenv("HOME");
    if (h && *h) return h;
    if (const passwd* pw = getpwuid(getuid())) return pw->pw_dir ? pw->pw_dir : "";
    return "";
}

struct Paths {
    std::string dolphin;  // user-places.xbel
    std::string gtk;      // gtk-3.0/bookmarks
    std::string state;    // our own record of what we added
};

Paths paths() {
    const std::string home = homeDir();
    const std::string data = envOr("XDG_DATA_HOME", home + "/.local/share");
    const std::string conf = envOr("XDG_CONFIG_HOME", home + "/.config");
    const std::string state = envOr("XDG_STATE_HOME", home + "/.local/state");
    return {data + "/user-places.xbel", conf + "/gtk-3.0/bookmarks", state + "/VaultExplorer/mounts.txt"};
}

bool disabled() {
    const char* v = std::getenv("VE_NO_PLACES");
    return v && *v && std::strcmp(v, "0") != 0;
}

bool exists(const std::string& p) {
    struct stat st;
    return ::stat(p.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

bool readFile(const std::string& p, std::string& out) {
    struct stat st;
    if (::stat(p.c_str(), &st) != 0 || !S_ISREG(st.st_mode) || static_cast<size_t>(st.st_size) > kMaxFile) return false;
    std::ifstream f(p, std::ios::binary);
    if (!f) return false;
    std::ostringstream ss;
    ss << f.rdbuf();
    out = ss.str();
    return true;
}

// Replace `path` with `content` in one step (temp file in the same directory + rename), keeping its mode.
bool atomicWrite(const std::string& path, const std::string& content) {
    const size_t slash = path.rfind('/');
    const std::string dir = slash == std::string::npos ? "." : path.substr(0, slash);
    const std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
    const std::string tmp = dir + "/." + name + ".vaultexplorer.tmp";
    {
        std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
        if (!f) return false;
        f << content;
        f.flush();
        if (!f) { std::remove(tmp.c_str()); return false; }
    }
    struct stat st;
    if (::stat(path.c_str(), &st) == 0) ::chmod(tmp.c_str(), st.st_mode & 07777);
    if (std::rename(tmp.c_str(), path.c_str()) != 0) {
        std::remove(tmp.c_str());
        return false;
    }
    return true;
}

bool mkdirs(const std::string& dir) {
    std::string cur;
    for (size_t i = 0; i <= dir.size(); ++i) {
        if (i == dir.size() || dir[i] == '/') {
            cur = dir.substr(0, i);
            if (!cur.empty() && ::mkdir(cur.c_str(), 0700) != 0 && errno != EEXIST) return false;
        }
    }
    return true;
}

// file:///a/b%20c -- unreserved characters and '/' stay, everything else is %XX.
std::string fileUri(const std::string& path) {
    static const char* hex = "0123456789ABCDEF";
    std::string out = "file://";
    for (unsigned char c : path) {
        const bool plain = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '/' ||
                           c == '-' || c == '.' || c == '_' || c == '~';
        if (plain) {
            out.push_back(static_cast<char>(c));
        } else {
            out.push_back('%');
            out.push_back(hex[c >> 4]);
            out.push_back(hex[c & 15]);
        }
    }
    return out;
}

std::string xmlEscape(const std::string& s) {
    std::string out;
    for (char c : s) {
        switch (c) {
            case '&': out += "&amp;"; break;
            case '<': out += "&lt;"; break;
            case '>': out += "&gt;"; break;
            case '"': out += "&quot;"; break;
            case '\'': out += "&apos;"; break;
            default: out.push_back(c);
        }
    }
    return out;
}

std::string oneLine(std::string s) {
    for (char& c : s) {
        if (c == '\n' || c == '\r' || c == '\t') c = ' ';
    }
    return s;
}

std::string randomId() {
    std::random_device rd;
    std::ostringstream ss;
    ss << std::hex;
    for (int i = 0; i < 4; ++i) ss << rd();
    return ss.str();
}

// ── Dolphin (XBEL) ──────────────────────────────────────────────────────────────────────────────────

// Removes every <bookmark> block that carries our owner tag and (if `href` is non-empty) that href.
std::string dolphinRemove(std::string xml, const std::string& href) {
    const std::string ownerTag = std::string("owner=\"") + kOwner + "\"";
    size_t pos = 0;
    while (true) {
        const size_t open = xml.find("<bookmark ", pos);  // note the space: "<bookmark:icon" must not match
        if (open == std::string::npos) break;
        const size_t closeTag = xml.find("</bookmark>", open);
        if (closeTag == std::string::npos) break;
        const size_t end = closeTag + std::strlen("</bookmark>");
        const std::string block = xml.substr(open, end - open);
        const bool ours = block.find(ownerTag) != std::string::npos;
        const bool match = href.empty() || block.find("href=\"" + xmlEscape(href) + "\"") != std::string::npos;
        if (ours && match) {
            size_t from = open;
            while (from > 0 && (xml[from - 1] == ' ' || xml[from - 1] == '\t')) --from;  // its indentation
            size_t to = end;
            if (to < xml.size() && xml[to] == '\n') ++to;
            xml.erase(from, to - from);
            pos = from;
        } else {
            pos = end;
        }
    }
    return xml;
}

std::string dolphinAdd(std::string xml, const std::string& href, const std::string& title) {
    xml = dolphinRemove(std::move(xml), href);  // idempotent: never two entries for one mount point
    const size_t close = xml.rfind("</xbel>");
    if (close == std::string::npos) return std::string();  // not a places file we understand: leave it alone
    std::ostringstream e;
    e << " <bookmark href=\"" << xmlEscape(href) << "\">\n"
      << "  <title>" << xmlEscape(title) << "</title>\n"
      << "  <info>\n"
      << "   <metadata owner=\"http://freedesktop.org\">\n"
      << "    <bookmark:icon xmlns:bookmark=\"http://www.freedesktop.org/standards/desktop-bookmarks\" "
         "name=\"drive-harddisk-encrypted\"/>\n"
      << "   </metadata>\n"
      << "   <metadata owner=\"" << kOwner << "\">\n"
      << "    <id>" << randomId() << "</id>\n"
      << "   </metadata>\n"
      << "  </info>\n"
      << " </bookmark>\n";
    // Keep the closing tag on its own line.
    size_t at = close;
    if (at > 0 && xml[at - 1] != '\n') xml.insert(at++, "\n");
    xml.insert(at, e.str());
    return xml;
}

// ── GTK bookmarks ───────────────────────────────────────────────────────────────────────────────────

std::string gtkRemove(const std::string& text, const std::string& uri) {
    std::string out;
    std::istringstream in(text);
    std::string line;
    while (std::getline(in, line)) {
        const size_t sp = line.find(' ');
        const std::string first = sp == std::string::npos ? line : line.substr(0, sp);
        if (first == uri) continue;
        out += line;
        out.push_back('\n');
    }
    return out;
}

std::string gtkAdd(const std::string& text, const std::string& uri, const std::string& title) {
    std::string out = gtkRemove(text, uri);
    out += uri + " " + oneLine(title) + "\n";
    return out;
}

// ── our own record of what is currently listed ──────────────────────────────────────────────────────

std::vector<std::string> readState(const Paths& p) {
    std::vector<std::string> v;
    std::string s;
    if (!readFile(p.state, s)) return v;
    std::istringstream in(s);
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty()) v.push_back(line);
    }
    return v;
}

void writeState(const Paths& p, const std::vector<std::string>& v) {
    const size_t slash = p.state.rfind('/');
    if (slash != std::string::npos) mkdirs(p.state.substr(0, slash));
    std::string s;
    for (const auto& l : v) s += l + "\n";
    atomicWrite(p.state, s);
}

void removeEntries(const Paths& p, const std::string& mountPoint) {
    const std::string uri = fileUri(mountPoint);
    std::string text;
    if (exists(p.dolphin) && readFile(p.dolphin, text)) {
        const std::string changed = dolphinRemove(text, uri);
        if (changed != text) atomicWrite(p.dolphin, changed);
    }
    if (exists(p.gtk) && readFile(p.gtk, text)) {
        const std::string changed = gtkRemove(text, uri);
        if (changed != text) atomicWrite(p.gtk, changed);
    }
}

}  // namespace

void placesAdd(const std::string& mountPoint, const std::string& title) {
    if (disabled() || mountPoint.empty()) return;
    std::lock_guard<std::mutex> g(gMu);
    const Paths p = paths();
    const std::string uri = fileUri(mountPoint);
    bool listed = false;
    std::string text;
    if (exists(p.dolphin) && readFile(p.dolphin, text)) {
        const std::string changed = dolphinAdd(text, uri, title);
        if (!changed.empty() && atomicWrite(p.dolphin, changed)) listed = true;
    }
    if (exists(p.gtk) && readFile(p.gtk, text)) {
        if (atomicWrite(p.gtk, gtkAdd(text, uri, title))) listed = true;
    }
    if (listed) {
        auto state = readState(p);
        bool known = false;
        for (const auto& s : state) known = known || s == mountPoint;
        if (!known) {
            state.push_back(mountPoint);
            writeState(p, state);
        }
    }
}

void placesRemove(const std::string& mountPoint) {
    if (disabled() || mountPoint.empty()) return;
    std::lock_guard<std::mutex> g(gMu);
    const Paths p = paths();
    removeEntries(p, mountPoint);
    auto state = readState(p);
    std::vector<std::string> kept;
    for (const auto& s : state) {
        if (s != mountPoint) kept.push_back(s);
    }
    if (kept.size() != state.size()) writeState(p, kept);
}

void placesCleanStale() {
    if (disabled()) return;
    std::lock_guard<std::mutex> g(gMu);
    const Paths p = paths();
    const auto state = readState(p);
    if (state.empty()) return;
    // Called once per process before anything is mounted: whatever an earlier run listed is gone by now.
    for (const auto& mp : state) removeEntries(p, mp);
    writeState(p, {});
}

}  // namespace vemount
