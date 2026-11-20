#include "fv_json.h"

#include <cstdio>
#include <cstdlib>

namespace fv::json {

const Value* Value::find(const std::string& key) const {
    for (auto& kv : obj_) if (kv.first == key) return &kv.second;
    return nullptr;
}

Value& Value::set(const std::string& key, Value v) {
    for (auto& kv : obj_) if (kv.first == key) { kv.second = std::move(v); return kv.second; }
    obj_.emplace_back(key, std::move(v));
    return obj_.back().second;
}

static void escapeTo(std::string& out, const std::string& s) {
    out.push_back('"');
    for (unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            default:
                if (c < 0x20) { char buf[8]; std::snprintf(buf, sizeof buf, "\\u%04x", c); out += buf; }
                else out.push_back((char)c);
        }
    }
    out.push_back('"');
}

void Value::dumpTo(std::string& out, int indent, int level) const {
    auto nl = [&](int lvl) {
        if (indent <= 0) return;
        out.push_back('\n');
        out.append((size_t)(indent * lvl), ' ');
    };
    switch (type_) {
        case Type::Null: out += "null"; break;
        case Type::Bool: out += b_ ? "true" : "false"; break;
        case Type::Int: out += std::to_string(i_); break;
        case Type::Double: { char buf[64]; std::snprintf(buf, sizeof buf, "%.17g", d_); out += buf; break; }
        case Type::String: escapeTo(out, s_); break;
        case Type::Array:
            if (arr_.empty()) { out += "[]"; break; }
            out.push_back('[');
            for (size_t i = 0; i < arr_.size(); i++) {
                if (i) out.push_back(',');
                nl(level + 1);
                arr_[i].dumpTo(out, indent, level + 1);
            }
            nl(level);
            out.push_back(']');
            break;
        case Type::Object:
            if (obj_.empty()) { out += "{}"; break; }
            out.push_back('{');
            for (size_t i = 0; i < obj_.size(); i++) {
                if (i) out.push_back(',');
                nl(level + 1);
                escapeTo(out, obj_[i].first);
                out += indent > 0 ? ": " : ":";
                obj_[i].second.dumpTo(out, indent, level + 1);
            }
            nl(level);
            out.push_back('}');
            break;
    }
}

std::string Value::dump(int indent) const {
    std::string s;
    dumpTo(s, indent, 0);
    return s;
}

// ------------------------------------------------------------------ parse --

namespace {
struct Parser {
    const std::string& t;
    size_t p = 0;
    int depth = 0;
    explicit Parser(const std::string& text) : t(text) {}

    [[noreturn]] void fail(const char* why) { throw Error(Err::InvalidVault, std::string("invalid JSON: ") + why); }
    void ws() { while (p < t.size() && (t[p] == ' ' || t[p] == '\t' || t[p] == '\n' || t[p] == '\r')) p++; }
    bool eat(char c) { ws(); if (p < t.size() && t[p] == c) { p++; return true; } return false; }

    static void utf8(std::string& out, uint32_t cp) {
        if (cp < 0x80) out.push_back((char)cp);
        else if (cp < 0x800) { out.push_back((char)(0xC0 | (cp >> 6))); out.push_back((char)(0x80 | (cp & 0x3F))); }
        else if (cp < 0x10000) { out.push_back((char)(0xE0 | (cp >> 12))); out.push_back((char)(0x80 | ((cp >> 6) & 0x3F))); out.push_back((char)(0x80 | (cp & 0x3F))); }
        else { out.push_back((char)(0xF0 | (cp >> 18))); out.push_back((char)(0x80 | ((cp >> 12) & 0x3F))); out.push_back((char)(0x80 | ((cp >> 6) & 0x3F))); out.push_back((char)(0x80 | (cp & 0x3F))); }
    }

    uint32_t hex4() {
        if (p + 4 > t.size()) fail("short \\u escape");
        uint32_t v = 0;
        for (int i = 0; i < 4; i++) {
            char c = t[p++];
            v <<= 4;
            if (c >= '0' && c <= '9') v |= (uint32_t)(c - '0');
            else if (c >= 'a' && c <= 'f') v |= (uint32_t)(c - 'a' + 10);
            else if (c >= 'A' && c <= 'F') v |= (uint32_t)(c - 'A' + 10);
            else fail("bad \\u escape");
        }
        return v;
    }

    std::string str() {
        if (p >= t.size() || t[p] != '"') fail("expected string");
        p++;
        std::string out;
        while (true) {
            if (p >= t.size()) fail("unterminated string");
            char c = t[p++];
            if (c == '"') break;
            if (c != '\\') { out.push_back(c); continue; }
            if (p >= t.size()) fail("bad escape");
            char e = t[p++];
            switch (e) {
                case '"': out.push_back('"'); break;
                case '\\': out.push_back('\\'); break;
                case '/': out.push_back('/'); break;
                case 'b': out.push_back('\b'); break;
                case 'f': out.push_back('\f'); break;
                case 'n': out.push_back('\n'); break;
                case 'r': out.push_back('\r'); break;
                case 't': out.push_back('\t'); break;
                case 'u': {
                    uint32_t cp = hex4();
                    if (cp >= 0xD800 && cp <= 0xDBFF && p + 1 < t.size() && t[p] == '\\' && t[p + 1] == 'u') {
                        p += 2;
                        uint32_t lo = hex4();
                        if (lo >= 0xDC00 && lo <= 0xDFFF) cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                    }
                    utf8(out, cp);
                    break;
                }
                default: fail("bad escape");
            }
        }
        return out;
    }

    Value val() {
        ws();
        if (p >= t.size()) fail("unexpected end");
        if (++depth > 64) fail("nesting too deep");
        struct D { int& d; ~D() { d--; } } dg{depth};
        char c = t[p];
        if (c == '{') {
            p++;
            Value o = Value::object();
            if (eat('}')) return o;
            while (true) {
                ws();
                std::string k = str();
                if (!eat(':')) fail("expected ':'");
                o.set(k, val());
                if (eat(',')) continue;
                if (eat('}')) break;
                fail("expected ',' or '}'");
            }
            return o;
        }
        if (c == '[') {
            p++;
            Value a = Value::array();
            if (eat(']')) return a;
            while (true) {
                a.push(val());
                if (eat(',')) continue;
                if (eat(']')) break;
                fail("expected ',' or ']'");
            }
            return a;
        }
        if (c == '"') return Value::string(str());
        if (t.compare(p, 4, "true") == 0) { p += 4; return Value::boolean(true); }
        if (t.compare(p, 5, "false") == 0) { p += 5; return Value::boolean(false); }
        if (t.compare(p, 4, "null") == 0) { p += 4; return Value::null(); }
        size_t s = p;
        if (p < t.size() && (t[p] == '-' || t[p] == '+')) p++;
        bool isInt = true;
        while (p < t.size() && ((t[p] >= '0' && t[p] <= '9') || t[p] == '.' || t[p] == 'e' || t[p] == 'E' || t[p] == '-' || t[p] == '+')) {
            if (t[p] == '.' || t[p] == 'e' || t[p] == 'E') isInt = false;
            p++;
        }
        if (p == s) fail("unexpected character");
        std::string num = t.substr(s, p - s);
        if (isInt) return Value::integer(std::strtoll(num.c_str(), nullptr, 10));
        return Value::integer((int64_t)std::strtod(num.c_str(), nullptr));
    }
};
}  // namespace

Value parse(const std::string& text) {
    Parser ps(text);
    Value v = ps.val();
    ps.ws();
    if (ps.p != text.size()) ps.fail("trailing characters");
    return v;
}

}  // namespace fv::json
