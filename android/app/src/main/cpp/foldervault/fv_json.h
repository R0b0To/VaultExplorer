// Minimal JSON reader/writer -- just enough for the vault config files
// (gocryptfs.conf, masterkey.cryptomator, the CryFS inner config, the CryFS
// integrity snapshot) so the core carries no third-party JSON dependency.
#pragma once

#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "fv_common.h"

namespace fv::json {

class Value {
public:
    enum class Type { Null, Bool, Int, Double, String, Array, Object };

    Value() = default;
    static Value null() { return Value(); }
    static Value boolean(bool b) { Value v; v.type_ = Type::Bool; v.b_ = b; return v; }
    static Value integer(int64_t i) { Value v; v.type_ = Type::Int; v.i_ = i; return v; }
    static Value string(std::string s) { Value v; v.type_ = Type::String; v.s_ = std::move(s); return v; }
    static Value array() { Value v; v.type_ = Type::Array; return v; }
    static Value object() { Value v; v.type_ = Type::Object; return v; }

    Type type() const { return type_; }
    bool isNull() const { return type_ == Type::Null; }
    bool isString() const { return type_ == Type::String; }
    bool isInt() const { return type_ == Type::Int; }
    bool isObject() const { return type_ == Type::Object; }
    bool isArray() const { return type_ == Type::Array; }

    bool asBool(bool dflt = false) const { return type_ == Type::Bool ? b_ : dflt; }
    int64_t asInt(int64_t dflt = 0) const { return type_ == Type::Int ? i_ : (type_ == Type::Double ? (int64_t)d_ : dflt); }
    const std::string& asString() const { return s_; }

    // Object access (insertion ordered).
    const Value* find(const std::string& key) const;
    bool has(const std::string& key) const { return find(key) != nullptr; }
    Value& set(const std::string& key, Value v);
    const std::vector<std::pair<std::string, Value>>& members() const { return obj_; }

    // Array access.
    const std::vector<Value>& items() const { return arr_; }
    Value& push(Value v) { arr_.push_back(std::move(v)); return arr_.back(); }

    // Pretty-prints with [indent] spaces per level (0 = compact).
    std::string dump(int indent = 0) const;

private:
    void dumpTo(std::string& out, int indent, int level) const;
    Type type_ = Type::Null;
    bool b_ = false;
    int64_t i_ = 0;
    double d_ = 0;
    std::string s_;
    std::vector<Value> arr_;
    std::vector<std::pair<std::string, Value>> obj_;
};

// Parses [text]; throws Error(InvalidVault) on malformed input.
Value parse(const std::string& text);

}  // namespace fv::json
