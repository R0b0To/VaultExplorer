#!/usr/bin/env python3
"""Builds assets/geo/cities.bin, the offline city list behind the gallery's
"Places" filter (nearest city to a photo's GPS position).

Data: GeoNames (https://www.geonames.org), CC BY 4.0 - keep the attribution in
assets/geo/README.md.

Usage with the official GeoNames dumps (https://download.geonames.org/export/dump/):

    python3 scripts/build_gazetteer.py --geonames cities5000.txt \
        --countries countryInfo.txt --min-population 5000

Alternative input: a JSON array of {cityId, name, country, adminCode,
population, loc:{coordinates:[lon,lat]}} (the `all-the-cities` npm package, same
GeoNames data) with country names from a {CC: {name}} JSON (geonamescache):

    python3 scripts/build_gazetteer.py --cities-json cities.json \
        --countries countries.json --min-population 5000

File format (little endian), read by lib/features/browser/gallery/filter/gallery_places.dart:

    "VXGC" u8 version(=1) u16 countryCount u32 cityCount
    countries: 2 ASCII bytes code, u8 nameLength, UTF-8 name        (x countryCount)
    cities:    i32 lat*1e4, i32 lon*1e4, u32 geonameId, u32 nameOffset, u8 countryIndex
                                                                     (x cityCount, 17 bytes each)
    names:     u8 length, UTF-8 bytes (offsets are from the start of this blob)
"""
import argparse
import json
import struct
import sys

VERSION = 1
# Admin codes are only readable as state abbreviations for these.
ADMIN_COUNTRIES = {"US"}


def load_geonames(path, min_pop):
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 15:
                continue
            pop = int(p[14] or 0)
            if pop < min_pop:
                continue
            out.append(dict(id=int(p[0]), name=p[1], lat=float(p[4]), lon=float(p[5]),
                            cc=p[8], admin=p[10], pop=pop))
    return out


def load_cities_json(path, min_pop):
    out = []
    for c in json.load(open(path, encoding="utf-8")):
        if c["population"] < min_pop:
            continue
        lon, lat = c["loc"]["coordinates"]
        out.append(dict(id=c["cityId"], name=c["name"], lat=lat, lon=lon,
                        cc=c["country"], admin=c.get("adminCode", ""), pop=c["population"]))
    return out


def load_countries(path):
    names = {}
    if path.endswith(".json"):
        for cc, v in json.load(open(path, encoding="utf-8")).items():
            names[cc] = v["name"]
    else:  # GeoNames countryInfo.txt
        for line in open(path, encoding="utf-8"):
            if line.startswith("#"):
                continue
            p = line.rstrip("\n").split("\t")
            if len(p) > 4:
                names[p[0]] = p[4]
    return names


def pack(cities, country_names):
    codes = sorted({c["cc"] for c in cities if len(c["cc"]) == 2})
    if len(codes) > 255:
        sys.exit("too many countries for a u8 index")
    index = {cc: i for i, cc in enumerate(codes)}
    head = bytearray()
    for cc in codes:
        name = country_names.get(cc, cc).encode("utf-8")[:255]
        head += cc.encode("ascii") + bytes([len(name)]) + name

    cities = sorted((c for c in cities if c["cc"] in index), key=lambda c: (c["lat"] // 1, c["lon"] // 1, c["id"]))
    names = bytearray()
    recs = bytearray()
    cache = {}
    for c in cities:
        label = c["name"]
        if c["cc"] in ADMIN_COUNTRIES and c["admin"]:
            label = f'{label}, {c["admin"]}'
        raw = label.encode("utf-8")[:255]
        off = cache.get(raw)
        if off is None:
            off = cache[raw] = len(names)
            names += bytes([len(raw)]) + raw
        recs += struct.pack("<iiIIB", round(c["lat"] * 1e4), round(c["lon"] * 1e4), c["id"], off, index[c["cc"]])
    return b"VXGC" + struct.pack("<BHI", VERSION, len(codes), len(cities)) + bytes(head) + bytes(recs) + bytes(names)


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--geonames")
    g.add_argument("--cities-json")
    ap.add_argument("--countries", required=True)
    ap.add_argument("--min-population", type=int, default=5000)
    ap.add_argument("--out", default="assets/geo/cities.bin")
    a = ap.parse_args()
    cities = load_geonames(a.geonames, a.min_population) if a.geonames else load_cities_json(a.cities_json, a.min_population)
    blob = pack(cities, load_countries(a.countries))
    with open(a.out, "wb") as f:
        f.write(blob)
    print(f"{len(cities)} cities, {len(blob)} bytes -> {a.out}")


if __name__ == "__main__":
    main()
