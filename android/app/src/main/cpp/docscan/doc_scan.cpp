#include "doc_scan.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <optional>

namespace docscan {
namespace {

// ───────────────────────────── basic types ─────────────────────────────

struct Pt {
    double x = 0;
    double y = 0;
};

inline double cross3(const Pt& o, const Pt& a, const Pt& b) {
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}
inline double dist(const Pt& a, const Pt& b) { return std::hypot(a.x - b.x, a.y - b.y); }

// > 0 for a polygon that runs clockwise on screen (y grows downwards).
double signedArea(const std::vector<Pt>& poly) {
    double s = 0;
    for (size_t i = 0, n = poly.size(); i < n; ++i) {
        const Pt& a = poly[i];
        const Pt& b = poly[(i + 1) % n];
        s += a.x * b.y - b.x * a.y;
    }
    return s * 0.5;
}
double polygonArea(const std::vector<Pt>& poly) { return std::fabs(signedArea(poly)); }
double perimeter(const std::vector<Pt>& poly) {
    double p = 0;
    for (size_t i = 0, n = poly.size(); i < n; ++i) p += dist(poly[i], poly[(i + 1) % n]);
    return p;
}

struct Plane {
    int w = 0;
    int h = 0;
    std::vector<uint8_t> px;
    Plane() = default;
    Plane(int w_, int h_, uint8_t v = 0) : w(w_), h(h_), px(static_cast<size_t>(w_) * h_, v) {}
    uint8_t& at(int x, int y) { return px[static_cast<size_t>(y) * w + x]; }
    uint8_t at(int x, int y) const { return px[static_cast<size_t>(y) * w + x]; }
};

// ───────────────────────────── resampling ─────────────────────────────

void fitSize(int sw, int sh, int maxSide, int* dw, int* dh) {
    const double scale = static_cast<double>(std::max(sw, sh)) / maxSide;
    if (scale <= 1.0) {
        *dw = sw;
        *dh = sh;
        return;
    }
    *dw = std::max(1, static_cast<int>(std::lround(sw / scale)));
    *dh = std::max(1, static_cast<int>(std::lround(sh / scale)));
}

// Box-average downscale of one channel of interleaved pixels (step bytes per
// pixel, off = channel offset).
Plane boxDownscale(const uint8_t* src, int sw, int sh, size_t rowBytes, int step, int off,
                   int dw, int dh) {
    Plane out(dw, dh);
    const double sx = static_cast<double>(sw) / dw;
    const double sy = static_cast<double>(sh) / dh;
    for (int y = 0; y < dh; ++y) {
        const int y0 = std::min(sh - 1, static_cast<int>(y * sy));
        const int y1 = std::min(sh, std::max(y0 + 1, static_cast<int>(std::ceil((y + 1) * sy))));
        for (int x = 0; x < dw; ++x) {
            const int x0 = std::min(sw - 1, static_cast<int>(x * sx));
            const int x1 = std::min(sw, std::max(x0 + 1, static_cast<int>(std::ceil((x + 1) * sx))));
            uint32_t sum = 0;
            for (int yy = y0; yy < y1; ++yy) {
                const uint8_t* p = src + yy * rowBytes + static_cast<size_t>(x0) * step + off;
                for (int xx = x0; xx < x1; ++xx, p += step) sum += *p;
            }
            out.at(x, y) = static_cast<uint8_t>(sum / static_cast<uint32_t>((y1 - y0) * (x1 - x0)));
        }
    }
    return out;
}

Plane lumaFromRgb(const Plane& r, const Plane& g, const Plane& b) {
    Plane l(r.w, r.h);
    for (size_t i = 0; i < l.px.size(); ++i)
        l.px[i] = static_cast<uint8_t>((77 * r.px[i] + 150 * g.px[i] + 29 * b.px[i]) >> 8);
    return l;
}

Plane gaussianBlur(const Plane& in, float sigma) {
    const int r = std::max(1, static_cast<int>(std::ceil(3 * sigma)));
    std::vector<float> k(2 * r + 1);
    float sum = 0;
    for (int i = -r; i <= r; ++i) sum += (k[i + r] = std::exp(-(i * i) / (2 * sigma * sigma)));
    for (float& v : k) v /= sum;

    std::vector<float> tmp(static_cast<size_t>(in.w) * in.h);
    for (int y = 0; y < in.h; ++y) {
        for (int x = 0; x < in.w; ++x) {
            float acc = 0;
            for (int i = -r; i <= r; ++i)
                acc += k[i + r] * in.at(std::clamp(x + i, 0, in.w - 1), y);
            tmp[static_cast<size_t>(y) * in.w + x] = acc;
        }
    }
    Plane out(in.w, in.h);
    for (int y = 0; y < in.h; ++y) {
        for (int x = 0; x < in.w; ++x) {
            float acc = 0;
            for (int i = -r; i <= r; ++i)
                acc += k[i + r] * tmp[static_cast<size_t>(std::clamp(y + i, 0, in.h - 1)) * in.w + x];
            out.at(x, y) = static_cast<uint8_t>(std::clamp(acc + 0.5f, 0.f, 255.f));
        }
    }
    return out;
}

// Median filter (square window, radius r) with a sliding histogram. Unlike a
// Gaussian it removes text and sensor noise without softening real edges.
Plane medianFilter(const Plane& in, int r) {
    Plane out(in.w, in.h);
    const int total = (2 * r + 1) * (2 * r + 1);
    std::array<int, 256> hist;
    for (int y = 0; y < in.h; ++y) {
        hist.fill(0);
        auto addCol = [&](int x, int sign) {
            const int cx = std::clamp(x, 0, in.w - 1);
            for (int j = -r; j <= r; ++j) hist[in.at(cx, std::clamp(y + j, 0, in.h - 1))] += sign;
        };
        for (int i = -r; i <= r; ++i) addCol(i, 1);
        int med = 0, below = 0;  // below = count of values < med
        for (int x = 0; x < in.w; ++x) {
            if (x > 0) {
                addCol(x - r - 1, -1);
                addCol(x + r, 1);
            }
            // Recompute median pointer from the previous one.
            int cnt = 0;
            int v = 0;
            if (x == 0) {
                for (; v < 256; ++v) {
                    if (cnt + hist[v] > total / 2) break;
                    cnt += hist[v];
                }
            } else {
                v = med;
                cnt = 0;
                for (int k = 0; k < v; ++k) cnt += hist[k];
                // Walk if the previous pointer is no longer right.
                while (v > 0 && cnt > total / 2) cnt -= hist[--v];
                while (v < 255 && cnt + hist[v] <= total / 2) cnt += hist[v++];
            }
            med = v;
            below = cnt;
            out.at(x, y) = static_cast<uint8_t>(med);
        }
        (void)below;
    }
    return out;
}

// Square max filter (radius r) via two 1-D passes.
Plane maxFilter(const Plane& in, int r) {
    Plane tmp(in.w, in.h);
    for (int y = 0; y < in.h; ++y)
        for (int x = 0; x < in.w; ++x) {
            uint8_t m = 0;
            for (int i = std::max(0, x - r); i <= std::min(in.w - 1, x + r); ++i)
                m = std::max(m, in.at(i, y));
            tmp.at(x, y) = m;
        }
    Plane out(in.w, in.h);
    for (int y = 0; y < in.h; ++y)
        for (int x = 0; x < in.w; ++x) {
            uint8_t m = 0;
            for (int j = std::max(0, y - r); j <= std::min(in.h - 1, y + r); ++j)
                m = std::max(m, tmp.at(x, j));
            out.at(x, y) = m;
        }
    return out;
}

Plane minFilter(const Plane& in, int r) {
    Plane inv(in.w, in.h);
    for (size_t i = 0; i < in.px.size(); ++i) inv.px[i] = static_cast<uint8_t>(255 - in.px[i]);
    Plane m = maxFilter(inv, r);
    for (uint8_t& v : m.px) v = static_cast<uint8_t>(255 - v);
    return m;
}

// ───────────────────────────── gradients & edges ─────────────────────────────

struct Grad {
    int w = 0;
    int h = 0;
    std::vector<float> gx, gy, mag;
};

Grad sobel(const Plane& p) {
    Grad g;
    g.w = p.w;
    g.h = p.h;
    const size_t n = static_cast<size_t>(p.w) * p.h;
    g.gx.assign(n, 0.f);
    g.gy.assign(n, 0.f);
    g.mag.assign(n, 0.f);
    for (int y = 1; y < p.h - 1; ++y) {
        for (int x = 1; x < p.w - 1; ++x) {
            const int a = p.at(x - 1, y - 1), b = p.at(x, y - 1), c = p.at(x + 1, y - 1);
            const int d = p.at(x - 1, y), f = p.at(x + 1, y);
            const int gg = p.at(x - 1, y + 1), h = p.at(x, y + 1), i = p.at(x + 1, y + 1);
            const float gx = ((c + 2 * f + i) - (a + 2 * d + gg)) * 0.25f;
            const float gy = ((gg + 2 * h + i) - (a + 2 * b + c)) * 0.25f;
            const size_t idx = static_cast<size_t>(y) * p.w + x;
            g.gx[idx] = gx;
            g.gy[idx] = gy;
            g.mag[idx] = std::sqrt(gx * gx + gy * gy);
        }
    }
    return g;
}

float magPercentile(const Grad& g, double pct) {
    std::array<int, 256> hist{};
    size_t total = 0;
    for (float m : g.mag) {
        hist[std::min(255, static_cast<int>(m))]++;
        ++total;
    }
    const size_t target = static_cast<size_t>(total * pct);
    size_t acc = 0;
    for (int i = 0; i < 256; ++i) {
        acc += hist[i];
        if (acc >= target) return static_cast<float>(i);
    }
    return 255.f;
}

// Canny: non-maximum suppression + hysteresis. Returns a 0/255 mask.
Plane cannyEdges(const Grad& g, float lo, float hi) {
    Plane state(g.w, g.h, 0);  // 0 none, 1 weak, 2 strong
    for (int y = 1; y < g.h - 1; ++y) {
        for (int x = 1; x < g.w - 1; ++x) {
            const size_t i = static_cast<size_t>(y) * g.w + x;
            const float m = g.mag[i];
            if (m < lo) continue;
            const float ax = std::fabs(g.gx[i]);
            const float ay = std::fabs(g.gy[i]);
            float m1, m2;
            if (ay <= 0.4142f * ax) {
                m1 = g.mag[i - 1];
                m2 = g.mag[i + 1];
            } else if (ay >= 2.4142f * ax) {
                m1 = g.mag[i - g.w];
                m2 = g.mag[i + g.w];
            } else if ((g.gx[i] > 0) == (g.gy[i] > 0)) {
                m1 = g.mag[i - g.w - 1];
                m2 = g.mag[i + g.w + 1];
            } else {
                m1 = g.mag[i - g.w + 1];
                m2 = g.mag[i + g.w - 1];
            }
            if (m >= m1 && m > m2) state.px[i] = m >= hi ? 2 : 1;
        }
    }
    std::vector<int> stack;
    for (size_t i = 0; i < state.px.size(); ++i)
        if (state.px[i] == 2) stack.push_back(static_cast<int>(i));
    while (!stack.empty()) {
        const int i = stack.back();
        stack.pop_back();
        const int x = i % g.w, y = i / g.w;
        for (int dy = -1; dy <= 1; ++dy)
            for (int dx = -1; dx <= 1; ++dx) {
                const int nx = x + dx, ny = y + dy;
                if (nx < 0 || ny < 0 || nx >= g.w || ny >= g.h) continue;
                const size_t j = static_cast<size_t>(ny) * g.w + nx;
                if (state.px[j] == 1) {
                    state.px[j] = 2;
                    stack.push_back(static_cast<int>(j));
                }
            }
    }
    Plane out(g.w, g.h, 0);
    for (size_t i = 0; i < out.px.size(); ++i) out.px[i] = state.px[i] == 2 ? 255 : 0;
    return out;
}

// ───────────────────────────── regions ─────────────────────────────

struct Component {
    int label = 0;
    int area = 0;
    int x0 = 0, y0 = 0, x1 = 0, y1 = 0;  // inclusive bbox
};

// 8-connected labelling of non-zero pixels. labels: 0 = background.
std::vector<Component> labelComponents(const Plane& mask, std::vector<int>* labels) {
    labels->assign(mask.px.size(), 0);
    std::vector<Component> comps;
    std::vector<int> stack;
    for (int sy = 0; sy < mask.h; ++sy) {
        for (int sx = 0; sx < mask.w; ++sx) {
            const size_t s = static_cast<size_t>(sy) * mask.w + sx;
            if (!mask.px[s] || (*labels)[s]) continue;
            Component c;
            c.label = static_cast<int>(comps.size()) + 1;
            c.x0 = c.x1 = sx;
            c.y0 = c.y1 = sy;
            (*labels)[s] = c.label;
            stack.push_back(static_cast<int>(s));
            while (!stack.empty()) {
                const int i = stack.back();
                stack.pop_back();
                const int x = i % mask.w, y = i / mask.w;
                ++c.area;
                c.x0 = std::min(c.x0, x);
                c.x1 = std::max(c.x1, x);
                c.y0 = std::min(c.y0, y);
                c.y1 = std::max(c.y1, y);
                for (int dy = -1; dy <= 1; ++dy)
                    for (int dx = -1; dx <= 1; ++dx) {
                        const int nx = x + dx, ny = y + dy;
                        if (nx < 0 || ny < 0 || nx >= mask.w || ny >= mask.h) continue;
                        const size_t j = static_cast<size_t>(ny) * mask.w + nx;
                        if (mask.px[j] && !(*labels)[j]) {
                            (*labels)[j] = c.label;
                            stack.push_back(static_cast<int>(j));
                        }
                    }
            }
            comps.push_back(c);
        }
    }
    return comps;
}

// Fills enclosed holes: everything not reachable from the frame border through
// zero pixels becomes foreground.
void fillHoles(Plane* mask) {
    std::vector<uint8_t> outside(mask->px.size(), 0);
    std::vector<int> stack;
    auto seed = [&](int x, int y) {
        const size_t i = static_cast<size_t>(y) * mask->w + x;
        if (!mask->px[i] && !outside[i]) {
            outside[i] = 1;
            stack.push_back(static_cast<int>(i));
        }
    };
    for (int x = 0; x < mask->w; ++x) {
        seed(x, 0);
        seed(x, mask->h - 1);
    }
    for (int y = 0; y < mask->h; ++y) {
        seed(0, y);
        seed(mask->w - 1, y);
    }
    while (!stack.empty()) {
        const int i = stack.back();
        stack.pop_back();
        const int x = i % mask->w, y = i / mask->w;
        const int nx[4] = {x - 1, x + 1, x, x};
        const int ny[4] = {y, y, y - 1, y + 1};
        for (int k = 0; k < 4; ++k) {
            if (nx[k] < 0 || ny[k] < 0 || nx[k] >= mask->w || ny[k] >= mask->h) continue;
            const size_t j = static_cast<size_t>(ny[k]) * mask->w + nx[k];
            if (!mask->px[j] && !outside[j]) {
                outside[j] = 1;
                stack.push_back(static_cast<int>(j));
            }
        }
    }
    for (size_t i = 0; i < mask->px.size(); ++i)
        if (!outside[i]) mask->px[i] = 255;
}

// ───────────────────────────── polygons ─────────────────────────────

// Convex hull of the pixel *areas* of a component (outer pixel corners), so the
// hull sits on the real boundary instead of half a pixel inside it. Returns a
// polygon that runs clockwise on screen.
std::vector<Pt> componentHull(const std::vector<int>& labels, int w, const Component& c) {
    const int rows = c.y1 - c.y0 + 1;
    std::vector<int> minX(rows, std::numeric_limits<int>::max()), maxX(rows, -1);
    for (int y = c.y0; y <= c.y1; ++y)
        for (int x = c.x0; x <= c.x1; ++x)
            if (labels[static_cast<size_t>(y) * w + x] == c.label) {
                minX[y - c.y0] = std::min(minX[y - c.y0], x);
                maxX[y - c.y0] = std::max(maxX[y - c.y0], x);
            }
    std::vector<Pt> pts;
    pts.reserve(rows * 4);
    for (int r = 0; r < rows; ++r) {
        if (maxX[r] < 0) continue;
        const double y = c.y0 + r;
        pts.push_back({static_cast<double>(minX[r]), y});
        pts.push_back({static_cast<double>(minX[r]), y + 1});
        pts.push_back({static_cast<double>(maxX[r] + 1), y});
        pts.push_back({static_cast<double>(maxX[r] + 1), y + 1});
    }
    std::sort(pts.begin(), pts.end(), [](const Pt& a, const Pt& b) {
        return a.x < b.x || (a.x == b.x && a.y < b.y);
    });
    pts.erase(std::unique(pts.begin(), pts.end(),
                          [](const Pt& a, const Pt& b) { return a.x == b.x && a.y == b.y; }),
              pts.end());
    if (pts.size() < 3) return {};
    std::vector<Pt> hull(2 * pts.size());
    size_t k = 0;
    for (size_t i = 0; i < pts.size(); ++i) {
        while (k >= 2 && cross3(hull[k - 2], hull[k - 1], pts[i]) <= 0) --k;
        hull[k++] = pts[i];
    }
    for (size_t i = pts.size() - 1, t = k + 1; i > 0; --i) {
        while (k >= t && cross3(hull[k - 2], hull[k - 1], pts[i - 1]) <= 0) --k;
        hull[k++] = pts[i - 1];
    }
    hull.resize(k - 1);
    if (signedArea(hull) < 0) std::reverse(hull.begin(), hull.end());
    return hull;
}

double pointSegmentDistance(const Pt& p, const Pt& a, const Pt& b) {
    const double dx = b.x - a.x, dy = b.y - a.y;
    const double len2 = dx * dx + dy * dy;
    if (len2 < 1e-12) return dist(p, a);
    const double t = std::clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0.0, 1.0);
    return dist(p, {a.x + t * dx, a.y + t * dy});
}

void dpChain(const std::vector<Pt>& pts, int a, int b, double eps, std::vector<char>* keep) {
    if (b - a < 2) return;
    const int n = static_cast<int>(pts.size());
    int far = -1;
    double best = eps;
    for (int i = a + 1; i < b; ++i) {
        const double d = pointSegmentDistance(pts[i % n], pts[a % n], pts[b % n]);
        if (d > best) {
            best = d;
            far = i;
        }
    }
    if (far < 0) return;
    (*keep)[far % n] = 1;
    dpChain(pts, a, far, eps, keep);
    dpChain(pts, far, b, eps, keep);
}

// Douglas-Peucker on a closed polygon.
std::vector<Pt> simplifyClosed(const std::vector<Pt>& poly, double eps) {
    const int n = static_cast<int>(poly.size());
    if (n <= 4) return poly;
    int b = 0;
    double far = -1;
    for (int i = 1; i < n; ++i) {
        const double d = dist(poly[0], poly[i]);
        if (d > far) {
            far = d;
            b = i;
        }
    }
    std::vector<char> keep(n, 0);
    keep[0] = keep[b] = 1;
    dpChain(poly, 0, b, eps, &keep);
    dpChain(poly, b, n, eps, &keep);
    std::vector<Pt> out;
    for (int i = 0; i < n; ++i)
        if (keep[i]) out.push_back(poly[i]);
    return out;
}

bool intersectLines(const Pt& p1, const Pt& p2, const Pt& p3, const Pt& p4, Pt* out, double* t1,
                    double* t2) {
    const double d1x = p2.x - p1.x, d1y = p2.y - p1.y;
    const double d2x = p4.x - p3.x, d2y = p4.y - p3.y;
    const double den = d1x * d2y - d1y * d2x;
    if (std::fabs(den) < 1e-9) return false;
    const double ex = p3.x - p1.x, ey = p3.y - p1.y;
    *t1 = (ex * d2y - ey * d2x) / den;
    *t2 = (ex * d1y - ey * d1x) / den;
    *out = {p1.x + *t1 * d1x, p1.y + *t1 * d1y};
    return true;
}

// Reduces a convex polygon to a quadrilateral that encloses it, repeatedly
// replacing the edge whose removal (by extending its neighbours until they
// meet) adds the least area. Tracks the true page edges even when corners are
// cut off or rounded.
std::vector<Pt> reduceToQuad(std::vector<Pt> poly) {
    while (poly.size() > 4) {
        const int n = static_cast<int>(poly.size());
        int best = -1;
        double bestAdd = std::numeric_limits<double>::max();
        Pt bestX;
        for (int i = 0; i < n; ++i) {
            const Pt& a = poly[(i + n - 1) % n];
            const Pt& b = poly[i];
            const Pt& c = poly[(i + 1) % n];
            const Pt& d = poly[(i + 2) % n];
            Pt x;
            double t1, t2;
            // a->b extended beyond b must meet d->c extended beyond c.
            if (!intersectLines(a, b, d, c, &x, &t1, &t2)) continue;
            if (t1 <= 1.0 || t2 <= 1.0) continue;
            const double add = std::fabs(cross3(b, x, c)) * 0.5;
            if (add < bestAdd) {
                bestAdd = add;
                best = i;
                bestX = x;
            }
        }
        if (best >= 0) {
            std::rotate(poly.begin(), poly.begin() + best, poly.end());
            poly[0] = bestX;
            poly.erase(poly.begin() + 1);
        } else {
            // No valid extension: drop the least significant vertex instead.
            int drop = 0;
            double smallest = std::numeric_limits<double>::max();
            for (int i = 0; i < n; ++i) {
                const double tri = std::fabs(cross3(poly[(i + n - 1) % n], poly[i], poly[(i + 1) % n]));
                if (tri < smallest) {
                    smallest = tri;
                    drop = i;
                }
            }
            poly.erase(poly.begin() + drop);
        }
    }
    return poly;
}

std::array<Pt, 4> orderClockwise(std::vector<Pt> q) {
    if (signedArea(q) < 0) std::reverse(q.begin(), q.end());
    int start = 0;
    for (int i = 1; i < 4; ++i)
        if (q[i].x + q[i].y < q[start].x + q[start].y) start = i;
    return {q[start], q[(start + 1) % 4], q[(start + 2) % 4], q[(start + 3) % 4]};
}

// ───────────────────────────── candidate scoring ─────────────────────────────

// Everything below works in the coordinates of the padded working frame.
struct Frame {
    int w = 0;   // unpadded working size
    int h = 0;
    int pad = 0;
};

struct Support {
    double mean = 0;
    double minSide = 0;
};

// How much of each quad side lies on a real image edge perpendicular to it.
// Samples on the frame border are ignored: the padding we add around the image
// makes a strong artificial edge there that would "support" any frame-sized quad.
Support edgeSupport(const Grad& g, const std::array<Pt, 4>& q, float strongThr, const Frame& f) {
    Support s;
    s.minSide = 1.0;
    for (int side = 0; side < 4; ++side) {
        const Pt& a = q[side];
        const Pt& b = q[(side + 1) % 4];
        const double len = dist(a, b);
        if (len < 4) return {};
        const double dx = (b.x - a.x) / len, dy = (b.y - a.y) / len;
        const double nx = dy, ny = -dx;  // outward for a clockwise polygon
        const int samples = std::clamp(static_cast<int>(len / 3), 8, 48);
        int hit = 0, total = 0;
        for (int k = 0; k < samples; ++k) {
            const double t = 0.06 + 0.88 * (k + 0.5) / samples;
            const double px = a.x + (b.x - a.x) * t, py = a.y + (b.y - a.y) * t;
            const double margin = 4.0;
            if (px < f.pad + margin || py < f.pad + margin || px > f.pad + f.w - margin ||
                py > f.pad + f.h - margin)
                continue;
            float bestMag = 0;
            for (int off = -3; off <= 3; ++off) {
                const int ix = static_cast<int>(std::lround(px + nx * off));
                const int iy = static_cast<int>(std::lround(py + ny * off));
                if (ix < 1 || iy < 1 || ix >= g.w - 1 || iy >= g.h - 1) continue;
                const size_t i = static_cast<size_t>(iy) * g.w + ix;
                const float m = g.mag[i];
                if (m <= bestMag) continue;
                const float align = std::fabs(g.gx[i] * static_cast<float>(nx) +
                                              g.gy[i] * static_cast<float>(ny)) / (m + 1e-6f);
                if (align >= 0.7f) bestMag = m;
            }
            ++total;
            if (bestMag >= strongThr) ++hit;
        }
        const double frac = total ? static_cast<double>(hit) / total : 0.0;
        s.mean += frac / 4;
        s.minSide = std::min(s.minSide, frac);
    }
    return s;
}

struct Candidate {
    std::array<Pt, 4> q;
    double score = 0;
    double areaFrac = 0;
    Support support;
};

// Moves every side of a clockwise quad outwards by d pixels and re-intersects.
std::array<Pt, 4> growQuad(const std::array<Pt, 4>& q, double d) {
    std::array<Pt, 4> lines[4];  // each: {point on shifted line, direction}
    for (int i = 0; i < 4; ++i) {
        const Pt& a = q[i];
        const Pt& b = q[(i + 1) % 4];
        const double len = std::max(1e-9, dist(a, b));
        const double nx = (b.y - a.y) / len, ny = -(b.x - a.x) / len;
        lines[i] = {Pt{a.x + nx * d, a.y + ny * d}, Pt{b.x + nx * d, b.y + ny * d}, Pt{}, Pt{}};
    }
    std::array<Pt, 4> out = q;
    for (int i = 0; i < 4; ++i) {
        const auto& l0 = lines[(i + 3) % 4];
        const auto& l1 = lines[i];
        Pt x;
        double t1, t2;
        if (intersectLines(l0[0], l0[1], l1[0], l1[1], &x, &t1, &t2)) out[i] = x;
    }
    return out;
}

std::optional<Candidate> evaluateHull(const std::vector<Pt>& hull, const Grad& grad, float strongThr,
                                      const Frame& f, double grow = 0.0) {
    if (hull.size() < 4) return std::nullopt;
    const double frameArea = static_cast<double>(f.w) * f.h;
    const double hullArea = polygonArea(hull);
    if (hullArea < 0.05 * frameArea || hullArea > 0.995 * frameArea) return std::nullopt;

    double eps = std::max(1.5, 0.008 * perimeter(hull));
    std::vector<Pt> poly = simplifyClosed(hull, eps);
    for (int guard = 0; poly.size() > 40 && guard < 8; ++guard) {
        eps *= 1.6;
        poly = simplifyClosed(hull, eps);
    }
    if (poly.size() < 4) return std::nullopt;
    std::array<Pt, 4> quad = orderClockwise(reduceToQuad(poly));
    if (grow > 0) quad = growQuad(quad, grow);

    std::vector<Pt> qv(quad.begin(), quad.end());
    const double quadArea = polygonArea(qv);
    if (quadArea < 1.0) return std::nullopt;
    const double fill = hullArea / quadArea;
    if (fill < 0.80) return std::nullopt;

    // Corners: sane interior angles, and inside (or very near) the frame.
    double maxDev = 0;
    for (int i = 0; i < 4; ++i) {
        const Pt& p0 = quad[(i + 3) % 4];
        const Pt& p1 = quad[i];
        const Pt& p2 = quad[(i + 1) % 4];
        const double ux = p0.x - p1.x, uy = p0.y - p1.y;
        const double vx = p2.x - p1.x, vy = p2.y - p1.y;
        const double lu = std::hypot(ux, uy), lv = std::hypot(vx, vy);
        if (lu < 1e-6 || lv < 1e-6) return std::nullopt;
        const double angle = std::acos(std::clamp((ux * vx + uy * vy) / (lu * lv), -1.0, 1.0)) * 180.0 / 3.14159265358979;
        if (angle < 55.0 || angle > 125.0) return std::nullopt;
        maxDev = std::max(maxDev, std::fabs(angle - 90.0));
        const double slackX = 0.03 * f.w, slackY = 0.03 * f.h;
        if (p1.x < f.pad - slackX || p1.x > f.pad + f.w + slackX || p1.y < f.pad - slackY ||
            p1.y > f.pad + f.h + slackY)
            return std::nullopt;
    }

    Candidate c;
    c.q = quad;
    c.areaFrac = quadArea / frameArea;
    if (c.areaFrac < 0.06 || c.areaFrac > 0.985) return std::nullopt;
    c.support = edgeSupport(grad, quad, strongThr, f);

    const double areaTerm = 0.3 + 0.7 * std::min(1.0, c.areaFrac / 0.45);
    const double supTerm = 0.15 + 0.85 * c.support.mean;
    const double minTerm = 0.55 + 0.45 * c.support.minSide;
    const double angTerm = 1.0 - 0.5 * std::min(1.0, maxDev / 40.0);
    const double fillTerm = 0.5 + 0.5 * std::min(1.0, (fill - 0.8) / 0.18);
    c.score = areaTerm * supTerm * minTerm * angTerm * fillTerm;
    return c;
}

// ───────────────────────────── detection passes ─────────────────────────────

struct Search {
    Frame frame;
    std::optional<Candidate> best;

    void offer(std::optional<Candidate> c) {
        if (c && (!best || c->score > best->score)) best = c;
    }
    bool good(double thr) const { return best && best->score >= thr; }
};

Plane padPlane(const Plane& in, int pad, uint8_t value) {
    Plane out(in.w + 2 * pad, in.h + 2 * pad, value);
    for (int y = 0; y < in.h; ++y)
        std::memcpy(out.px.data() + static_cast<size_t>(y + pad) * out.w + pad,
                    in.px.data() + static_cast<size_t>(y) * in.w, static_cast<size_t>(in.w));
    return out;
}

int otsuThreshold(const Plane& p) {
    std::array<double, 256> hist{};
    for (uint8_t v : p.px) hist[v]++;
    const double total = static_cast<double>(p.px.size());
    double sumAll = 0;
    for (int i = 0; i < 256; ++i) sumAll += i * hist[i];
    double wB = 0, sumB = 0, bestVar = -1;
    int best = 128;
    for (int t = 0; t < 256; ++t) {
        wB += hist[t];
        if (wB == 0) continue;
        const double wF = total - wB;
        if (wF == 0) break;
        sumB += t * hist[t];
        const double mB = sumB / wB, mF = (sumAll - sumB) / wF;
        const double var = wB * wF * (mB - mF) * (mB - mF);
        if (var > bestVar) {
            bestVar = var;
            best = t;
        }
    }
    return best;
}

void evaluateComponents(const std::vector<Component>& comps, const std::vector<int>& labels, int w,
                        size_t maxCount, double minBoxFrac, const Grad& grad, float strongThr,
                        Search* search, double grow = 0.0) {
    std::vector<const Component*> order;
    const double minBox = minBoxFrac * search->frame.w * search->frame.h;
    for (const Component& c : comps) {
        const double box = static_cast<double>(c.x1 - c.x0 + 1) * (c.y1 - c.y0 + 1);
        if (box >= minBox) order.push_back(&c);
    }
    std::sort(order.begin(), order.end(), [](const Component* a, const Component* b) {
        return (a->x1 - a->x0 + 1) * (a->y1 - a->y0 + 1) > (b->x1 - b->x0 + 1) * (b->y1 - b->y0 + 1);
    });
    if (order.size() > maxCount) order.resize(maxCount);
    for (const Component* c : order)
        search->offer(evaluateHull(componentHull(labels, w, *c), grad, strongThr, search->frame, grow));
}

// Candidates from thresholded regions: a bright (or dark) page against its
// surroundings. Robust against text and texture, unlike pure edge passes.
void regionPass(const Plane& smooth, const Grad& grad, float strongThr, bool bright, Search* search) {
    const Frame& f = search->frame;
    const int otsu = otsuThreshold(smooth);
    std::vector<int> thresholds = {otsu, static_cast<int>(otsu * 0.85), static_cast<int>(otsu * 1.15)};
    if (bright) thresholds.push_back(160);
    for (int t : thresholds) {
        t = std::clamp(t, 20, 235);
        Plane inner(smooth.w, smooth.h);
        for (size_t i = 0; i < inner.px.size(); ++i)
            inner.px[i] = (bright ? smooth.px[i] > t : smooth.px[i] < t) ? 255 : 0;
        // Variant 0: as is. Variant 1: opened, to cut thin bridges to clutter.
        for (int variant = 0; variant < 2; ++variant) {
            Plane m = inner;
            if (variant == 1) {
                Plane er = minFilter(m, 2);
                m = maxFilter(er, 2);
            }
            Plane padded = padPlane(m, f.pad, 0);
            fillHoles(&padded);
            std::vector<int> labels;
            const std::vector<Component> comps = labelComponents(padded, &labels);
            evaluateComponents(comps, labels, padded.w, 4, 0.06, grad, strongThr, search);
        }
        if (search->good(0.8)) return;
    }
}

// Candidates from Canny edges over a descending sensitivity ladder (like OSS's
// 60..10 loop). Two kinds per level:
//  * the hull of an edge component (the page outline), and
//  * the hull of the *interior* of an outline, which is what findContours'
//    RETR_TREE hands OSS: it still works when the outline is welded to clutter.
void edgePass(const Grad& grad, float strongThr, bool live, Search* search) {
    static const float kLevelsFull[] = {50.f, 30.f, 18.f, 11.f, 7.f};
    static const float kLevelsLive[] = {50.f, 25.f, 12.f};
    const float* levels = live ? kLevelsLive : kLevelsFull;
    const int count = live ? 3 : 5;
    const double growPx = 2.0;
    for (int i = 0; i < count; ++i) {
        const float hi = levels[i];
        Plane edges = cannyEdges(grad, 0.5f * hi, hi);
        Plane dil = maxFilter(edges, 1);
        {
            std::vector<int> labels;
            const std::vector<Component> comps = labelComponents(dil, &labels);
            evaluateComponents(comps, labels, dil.w, 4, 0.08, grad, strongThr, search);
        }
        // Interior: complement of the thickened edges, with the frame border sealed.
        Plane inner(dil.w, dil.h, 0);
        for (size_t k = 0; k < inner.px.size(); ++k) inner.px[k] = dil.px[k] ? 0 : 255;
        for (int x = 0; x < inner.w; ++x) inner.at(x, 0) = inner.at(x, inner.h - 1) = 0;
        for (int y = 0; y < inner.h; ++y) inner.at(0, y) = inner.at(inner.w - 1, y) = 0;
        {
            std::vector<int> labels;
            const std::vector<Component> comps = labelComponents(inner, &labels);
            evaluateComponents(comps, labels, inner.w, 4, 0.06, grad, strongThr, search, growPx);
        }
        if (search->good(0.8)) return;
    }
}

// Runs every pass on one image plane (unpadded working resolution).
void analysePlane(const Plane& base, bool allowDark, bool live, Search* search) {
    const int pad = search->frame.pad;
    const int r = live ? 2 : 3;
    Plane denoised = medianFilter(base, r);
    Plane soft = gaussianBlur(denoised, 1.2f);
    Plane crisp = gaussianBlur(denoised, 0.8f);
    Plane crispPadded = padPlane(crisp, pad, 0);
    Grad grad = sobel(crispPadded);
    const float strongThr = std::max(3.0f, 0.2f * magPercentile(grad, 0.99));

    regionPass(soft, grad, strongThr, true, search);
    if (search->good(0.8)) return;
    edgePass(grad, strongThr, live, search);
    if (allowDark && !search->good(0.45)) regionPass(soft, grad, strongThr, false, search);
}

Detection toDetection(const Search& s) {
    Detection d;
    if (!s.best || s.best->score < 0.22 || s.best->support.mean < 0.3) return d;
    const Frame& f = s.frame;
    for (int i = 0; i < 4; ++i) {
        d.quad.p[i].x = static_cast<float>(std::clamp((s.best->q[i].x - f.pad) / f.w, 0.0, 1.0));
        d.quad.p[i].y = static_cast<float>(std::clamp((s.best->q[i].y - f.pad) / f.h, 0.0, 1.0));
    }
    d.found = true;
    d.score = static_cast<float>(std::min(1.0, s.best->score));
    return d;
}

Detection runDetection(const std::vector<Plane>& planes, bool allowDark, bool live) {
    Search search;
    search.frame.w = planes[0].w;
    search.frame.h = planes[0].h;
    search.frame.pad = 6;
    for (size_t i = 0; i < planes.size(); ++i) {
        analysePlane(planes[i], allowDark, live, &search);
        if (search.good(0.7)) break;
    }
    return toDetection(search);
}

// ───────────────────────────── sub-pixel refinement ─────────────────────────────

// Samples at continuous coordinates where pixel i covers [i, i+1] (the
// convention of the box-averaged planes), i.e. its centre is at i + 0.5.
float bilinearLuma(const Plane& p, double x, double y) {
    x -= 0.5;
    y -= 0.5;
    x = std::clamp(x, 0.0, p.w - 1.0);
    y = std::clamp(y, 0.0, p.h - 1.0);
    const int x0 = static_cast<int>(x), y0 = static_cast<int>(y);
    const int x1 = std::min(x0 + 1, p.w - 1), y1 = std::min(y0 + 1, p.h - 1);
    const float fx = static_cast<float>(x - x0), fy = static_cast<float>(y - y0);
    const float a = p.at(x0, y0), b = p.at(x1, y0), c = p.at(x0, y1), d = p.at(x1, y1);
    return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy;
}

struct Line {
    Pt origin;  // a point on the line
    Pt dir;     // unit direction
};

// Fits a line through points by total least squares, trimming outliers.
bool fitLine(std::vector<Pt> pts, Line* out) {
    for (int round = 0; round < 4; ++round) {
        if (pts.size() < 6) return false;
        Pt c{0, 0};
        for (const Pt& p : pts) {
            c.x += p.x;
            c.y += p.y;
        }
        c.x /= pts.size();
        c.y /= pts.size();
        double sxx = 0, sxy = 0, syy = 0;
        for (const Pt& p : pts) {
            sxx += (p.x - c.x) * (p.x - c.x);
            sxy += (p.x - c.x) * (p.y - c.y);
            syy += (p.y - c.y) * (p.y - c.y);
        }
        const double theta = 0.5 * std::atan2(2 * sxy, sxx - syy);
        out->origin = c;
        out->dir = {std::cos(theta), std::sin(theta)};
        std::vector<double> res;
        for (const Pt& p : pts)
            res.push_back(std::fabs((p.x - c.x) * -out->dir.y + (p.y - c.y) * out->dir.x));
        std::vector<double> sorted = res;
        std::nth_element(sorted.begin(), sorted.begin() + sorted.size() / 2, sorted.end());
        const double limit = std::max(0.6, 2.5 * sorted[sorted.size() / 2]);
        std::vector<Pt> kept;
        for (size_t i = 0; i < pts.size(); ++i)
            if (res[i] <= limit) kept.push_back(pts[i]);
        if (kept.size() == pts.size()) return true;
        pts.swap(kept);
    }
    return pts.size() >= 6;
}

// Snaps each side of `q` (pixel coordinates of `luma`) to the strongest nearby
// edge along its normal, fitting a line per side, and re-intersects the lines.
// Sides without a convincing edge keep their original position.
bool refineQuadOnPlane(const Plane& luma, std::array<Pt, 4>* q, double radius) {
    Line lines[4];
    bool ok[4] = {false, false, false, false};
    int refined = 0;
    for (int side = 0; side < 4; ++side) {
        const Pt& a = (*q)[side];
        const Pt& b = (*q)[(side + 1) % 4];
        const double len = dist(a, b);
        lines[side] = {a, {(b.x - a.x) / std::max(1e-9, len), (b.y - a.y) / std::max(1e-9, len)}};
        if (len < 20) continue;
        const Pt n{lines[side].dir.y, -lines[side].dir.x};  // outward
        const int samples = std::clamp(static_cast<int>(len / 5), 12, 90);
        std::vector<Pt> found;
        const int steps = static_cast<int>(std::ceil(radius * 4)) + 1;  // half-pixel steps over [-radius, radius]
        std::vector<float> prof(steps + 2);
        for (int k = 0; k < samples; ++k) {
            const double t = 0.08 + 0.84 * (k + 0.5) / samples;
            const Pt p{a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t};
            // Profile along the normal, averaged over a few px of the tangent to
            // beat sensor noise.
            for (int i = 0; i < steps + 2; ++i) {
                const double o = -radius + (i - 0.5) * 0.5;
                float acc = 0;
                for (int j = -2; j <= 2; ++j)
                    acc += bilinearLuma(luma, p.x + n.x * o + lines[side].dir.x * j,
                                        p.y + n.y * o + lines[side].dir.y * j);
                prof[i] = acc / 5.f;
            }
            int best = -1;
            float bestD = 0;
            for (int i = 1; i < steps + 1; ++i) {
                const float d = std::fabs(prof[i + 1] - prof[i - 1]);
                if (d > bestD) {
                    bestD = d;
                    best = i;
                }
            }
            if (best < 0 || bestD < 3.0f) continue;  // < 3 levels per px: no real edge
            // Parabolic interpolation of |gradient| peak.
            const float d0 = std::fabs(prof[best] - prof[best - 2 >= 0 ? best - 2 : 0]);
            const float d2 = std::fabs(prof[best + 2 < steps + 2 ? best + 2 : steps + 1] - prof[best]);
            const float denom = d0 - 2 * bestD + d2;
            const double sub = std::fabs(denom) > 1e-6 ? 0.5 * (d0 - d2) / denom : 0.0;
            const double o = -radius + (best - 0.5) * 0.5 + std::clamp(sub, -1.0, 1.0) * 0.5;
            found.push_back({p.x + n.x * o, p.y + n.y * o});
        }
        if (found.size() < std::max<size_t>(8, samples * 2 / 5)) continue;
        Line fit;
        if (!fitLine(found, &fit)) continue;
        // Reject fits that turned the side by more than a few degrees.
        const double cosTurn = std::fabs(fit.dir.x * lines[side].dir.x + fit.dir.y * lines[side].dir.y);
        if (cosTurn < std::cos(4.0 * 3.14159265358979 / 180.0)) continue;
        if (fit.dir.x * lines[side].dir.x + fit.dir.y * lines[side].dir.y < 0) {
            fit.dir.x = -fit.dir.x;
            fit.dir.y = -fit.dir.y;
        }
        lines[side] = fit;
        ok[side] = true;
        ++refined;
    }
    if (refined == 0) return false;
    std::array<Pt, 4> out = *q;
    for (int i = 0; i < 4; ++i) {
        const Line& l0 = lines[(i + 3) % 4];
        const Line& l1 = lines[i];
        if (!ok[(i + 3) % 4] && !ok[i]) continue;
        Pt x;
        double t1, t2;
        const Pt a1{l0.origin.x + l0.dir.x, l0.origin.y + l0.dir.y};
        const Pt b1{l1.origin.x + l1.dir.x, l1.origin.y + l1.dir.y};
        if (!intersectLines(l0.origin, a1, l1.origin, b1, &x, &t1, &t2)) continue;
        if (dist(x, (*q)[i]) > radius * 2.5) continue;
        out[i] = x;
    }
    *q = out;
    return true;
}

// Runs refinement at increasing resolution on the source image. The first pass
// has a wide window because the coarse quad (median-rounded corners, 480 px
// grid) can be off by a percent or so; later passes tighten the fit.
void refineDetection(const uint8_t* rgba, int width, int height, size_t stride, Detection* det) {
    if (!det->found) return;
    struct Pass {
        int longSide;
        double radius;
    };
    const Pass passes[] = {{1000, 14.0}, {1000, 5.0}, {2000, 3.0}};
    int cachedLong = -1;
    Plane luma;
    int dw = 0, dh = 0;
    for (const Pass& pass : passes) {
        if (pass.longSide > 1000 && std::max(width, height) < 1500) break;
        if (pass.longSide != cachedLong) {
            fitSize(width, height, pass.longSide, &dw, &dh);
            Plane r = boxDownscale(rgba, width, height, stride, 4, 0, dw, dh);
            Plane g = boxDownscale(rgba, width, height, stride, 4, 1, dw, dh);
            Plane b = boxDownscale(rgba, width, height, stride, 4, 2, dw, dh);
            luma = lumaFromRgb(r, g, b);
            cachedLong = pass.longSide;
        }
        std::array<Pt, 4> q;
        for (int i = 0; i < 4; ++i) q[i] = {det->quad.p[i].x * dw, det->quad.p[i].y * dh};
        if (!refineQuadOnPlane(luma, &q, pass.radius)) continue;
        for (int i = 0; i < 4; ++i) {
            det->quad.p[i].x = static_cast<float>(std::clamp(q[i].x / dw, 0.0, 1.0));
            det->quad.p[i].y = static_cast<float>(std::clamp(q[i].y / dh, 0.0, 1.0));
        }
    }
}

// ───────────────────────────── geometry for warping ─────────────────────────────

Quad denormalize(const Quad& qn, int w, int h) {
    Quad q;
    for (int i = 0; i < 4; ++i) {
        q.p[i].x = qn.p[i].x * w;
        q.p[i].y = qn.p[i].y * h;
    }
    return q;
}

// Width/height ratio of the rectangle that produced this perspective view
// (Zhang & He, "Whiteboard scanning and image enhancement", 2007), assuming
// square pixels and the principal point at the image centre.
bool estimateAspect(const Quad& q, double u0, double v0, double* ratio) {
    struct V3 {
        double x, y, z;
    };
    auto cross = [](const V3& a, const V3& b) {
        return V3{a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
    };
    auto dot = [](const V3& a, const V3& b) { return a.x * b.x + a.y * b.y + a.z * b.z; };
    const V3 m1{q.p[0].x - u0, q.p[0].y - v0, 1};  // TL
    const V3 m2{q.p[1].x - u0, q.p[1].y - v0, 1};  // TR
    const V3 m4{q.p[2].x - u0, q.p[2].y - v0, 1};  // BR
    const V3 m3{q.p[3].x - u0, q.p[3].y - v0, 1};  // BL
    const double den2 = dot(cross(m2, m4), m3);
    const double den3 = dot(cross(m3, m4), m2);
    if (std::fabs(den2) < 1e-9 || std::fabs(den3) < 1e-9) return false;
    const double k2 = dot(cross(m1, m4), m3) / den2;
    const double k3 = dot(cross(m1, m4), m2) / den3;
    const V3 n2{k2 * m2.x - m1.x, k2 * m2.y - m1.y, k2 * m2.z - m1.z};
    const V3 n3{k3 * m3.x - m1.x, k3 * m3.y - m1.y, k3 * m3.z - m1.z};
    const double nz = n2.z * n3.z;
    if (std::fabs(nz) < 1e-9) return false;
    const double f2 = -(n2.x * n3.x + n2.y * n3.y) / nz;
    if (!(f2 > 0) || !std::isfinite(f2)) return false;
    const double r2 = (n2.x * n2.x + n2.y * n2.y + f2 * n2.z * n2.z) /
                      (n3.x * n3.x + n3.y * n3.y + f2 * n3.z * n3.z);
    if (!(r2 > 0) || !std::isfinite(r2)) return false;
    *ratio = std::sqrt(r2);
    return true;
}

// Solves H (row-major 3x3, h22 = 1) with H * dst = src for four point pairs.
bool solveHomography(const Pt dst[4], const Pt src[4], double H[9]) {
    double a[8][9];
    for (int i = 0; i < 4; ++i) {
        const double x = dst[i].x, y = dst[i].y, u = src[i].x, v = src[i].y;
        const double r0[9] = {x, y, 1, 0, 0, 0, -u * x, -u * y, u};
        const double r1[9] = {0, 0, 0, x, y, 1, -v * x, -v * y, v};
        std::memcpy(a[2 * i], r0, sizeof(r0));
        std::memcpy(a[2 * i + 1], r1, sizeof(r1));
    }
    for (int c = 0; c < 8; ++c) {
        int piv = c;
        for (int r = c + 1; r < 8; ++r)
            if (std::fabs(a[r][c]) > std::fabs(a[piv][c])) piv = r;
        if (std::fabs(a[piv][c]) < 1e-12) return false;
        if (piv != c)
            for (int k = 0; k < 9; ++k) std::swap(a[c][k], a[piv][k]);
        for (int r = 0; r < 8; ++r) {
            if (r == c) continue;
            const double fct = a[r][c] / a[c][c];
            for (int k = c; k < 9; ++k) a[r][k] -= fct * a[c][k];
        }
    }
    for (int i = 0; i < 8; ++i) H[i] = a[i][8] / a[i][i];
    H[8] = 1.0;
    return true;
}

}  // namespace

// ───────────────────────────── public API ─────────────────────────────

Detection detectFromGray(const uint8_t* gray, int width, int height, int rowStride) {
    if (!gray || width < 16 || height < 16) return {};
    int dw, dh;
    fitSize(width, height, 320, &dw, &dh);
    std::vector<Plane> planes;
    planes.push_back(boxDownscale(gray, width, height, static_cast<size_t>(rowStride), 1, 0, dw, dh));
    return runDetection(planes, /*allowDark=*/false, /*live=*/true);
}

Detection detectFromRgba(const uint8_t* rgba, int width, int height, int rowStride) {
    if (!rgba || width < 16 || height < 16) return {};
    int dw, dh;
    fitSize(width, height, 480, &dw, &dh);
    const size_t stride = rowStride > 0 ? static_cast<size_t>(rowStride) : static_cast<size_t>(width) * 4;
    Plane r = boxDownscale(rgba, width, height, stride, 4, 0, dw, dh);
    Plane g = boxDownscale(rgba, width, height, stride, 4, 1, dw, dh);
    Plane b = boxDownscale(rgba, width, height, stride, 4, 2, dw, dh);
    std::vector<Plane> planes;
    planes.push_back(lumaFromRgb(r, g, b));
    planes.push_back(std::move(b));  // OSS tries B, G, R in that order
    planes.push_back(std::move(g));
    planes.push_back(std::move(r));
    Detection det = runDetection(planes, /*allowDark=*/true, /*live=*/false);
#ifndef DOCSCAN_NO_REFINE
    refineDetection(rgba, width, height, stride, &det);
#endif
    return det;
}

PointF rotateNormalized(PointF p, int clockwiseDegrees) {
    switch (((clockwiseDegrees % 360) + 360) % 360) {
        case 90:
            return {1.f - p.y, p.x};
        case 180:
            return {1.f - p.x, 1.f - p.y};
        case 270:
            return {p.y, 1.f - p.x};
        default:
            return p;
    }
}

Quad orderCorners(const PointF pts[4]) {
    std::vector<Pt> v;
    for (int i = 0; i < 4; ++i) v.push_back({pts[i].x, pts[i].y});
    // Sort by angle around the centroid first so self-crossing input still works.
    Pt c{0, 0};
    for (const Pt& p : v) {
        c.x += p.x / 4;
        c.y += p.y / 4;
    }
    std::sort(v.begin(), v.end(), [&](const Pt& a, const Pt& b) {
        return std::atan2(a.y - c.y, a.x - c.x) < std::atan2(b.y - c.y, b.x - c.x);
    });
    const std::array<Pt, 4> o = orderClockwise(v);
    Quad q;
    for (int i = 0; i < 4; ++i) {
        q.p[i].x = static_cast<float>(o[i].x);
        q.p[i].y = static_cast<float>(o[i].y);
    }
    return q;
}

void outputSize(const Quad& quadNorm, int srcW, int srcH, int maxLongSide, int* outW, int* outH) {
    const Quad q = denormalize(quadNorm, srcW, srcH);
    auto d = [&](int a, int b) {
        return std::hypot(static_cast<double>(q.p[a].x - q.p[b].x), static_cast<double>(q.p[a].y - q.p[b].y));
    };
    const double w0 = std::max(d(0, 1), d(3, 2));
    const double h0 = std::max(d(0, 3), d(1, 2));
    double w = std::max(1.0, w0), h = std::max(1.0, h0);

    double ratio = 0;
    if (estimateAspect(q, srcW / 2.0, srcH / 2.0, &ratio) && ratio > 0.2 && ratio < 5.0) {
        const double heuristic = w0 / std::max(1.0, h0);
        if (ratio / heuristic < 1.35 && heuristic / ratio < 1.35) {
            const double longSide = std::max(w0, h0);
            if (ratio >= 1.0) {
                w = longSide;
                h = longSide / ratio;
            } else {
                h = longSide;
                w = longSide * ratio;
            }
        }
    }
    const double scale = std::max(w, h) > maxLongSide ? maxLongSide / std::max(w, h) : 1.0;
    *outW = std::max(1, static_cast<int>(std::lround(w * scale)));
    *outH = std::max(1, static_cast<int>(std::lround(h * scale)));
}

bool warpQuad(const uint8_t* src, int srcW, int srcH, int srcStride, const Quad& quadNorm,
              uint8_t* dst, int outW, int outH) {
    if (!src || !dst || srcW < 2 || srcH < 2 || outW < 1 || outH < 1) return false;
    const Quad q = denormalize(quadNorm, srcW, srcH);
    const Pt rect[4] = {{0, 0}, {outW - 1.0, 0}, {outW - 1.0, outH - 1.0}, {0, outH - 1.0}};
    const Pt quad[4] = {{q.p[0].x, q.p[0].y}, {q.p[1].x, q.p[1].y}, {q.p[2].x, q.p[2].y}, {q.p[3].x, q.p[3].y}};
    double H[9];
    if (!solveHomography(rect, quad, H)) return false;
    const size_t stride = srcStride > 0 ? static_cast<size_t>(srcStride) : static_cast<size_t>(srcW) * 4;

    for (int y = 0; y < outH; ++y) {
        uint8_t* o = dst + static_cast<size_t>(y) * outW * 4;
        for (int x = 0; x < outW; ++x, o += 4) {
            const double den = H[6] * x + H[7] * y + H[8];
            const double sx = (H[0] * x + H[1] * y + H[2]) / den;
            const double sy = (H[3] * x + H[4] * y + H[5]) / den;
            const double cx = std::clamp(sx, 0.0, srcW - 1.0);
            const double cy = std::clamp(sy, 0.0, srcH - 1.0);
            const int x0 = static_cast<int>(cx), y0 = static_cast<int>(cy);
            const int x1 = std::min(x0 + 1, srcW - 1), y1 = std::min(y0 + 1, srcH - 1);
            const float fx = static_cast<float>(cx - x0), fy = static_cast<float>(cy - y0);
            const uint8_t* p00 = src + y0 * stride + static_cast<size_t>(x0) * 4;
            const uint8_t* p10 = src + y0 * stride + static_cast<size_t>(x1) * 4;
            const uint8_t* p01 = src + y1 * stride + static_cast<size_t>(x0) * 4;
            const uint8_t* p11 = src + y1 * stride + static_cast<size_t>(x1) * 4;
            for (int c = 0; c < 3; ++c) {
                const float top = p00[c] + (p10[c] - p00[c]) * fx;
                const float bot = p01[c] + (p11[c] - p01[c]) * fx;
                o[c] = static_cast<uint8_t>(std::clamp(top + (bot - top) * fy + 0.5f, 0.f, 255.f));
            }
            o[3] = 255;
        }
    }
    return true;
}

// ───────────────────────────── filters ─────────────────────────────

namespace {

struct SmallMap {
    int w = 0;
    int h = 0;
    std::vector<float> v;
    // Bilinear sample at map coordinates (pixel centres at integers).
    float sample(float x, float y) const {
        x = std::clamp(x, 0.f, w - 1.f);
        y = std::clamp(y, 0.f, h - 1.f);
        const int x0 = static_cast<int>(x), y0 = static_cast<int>(y);
        const int x1 = std::min(x0 + 1, w - 1), y1 = std::min(y0 + 1, h - 1);
        const float fx = x - x0, fy = y - y0;
        const float a = v[static_cast<size_t>(y0) * w + x0], b = v[static_cast<size_t>(y0) * w + x1];
        const float c = v[static_cast<size_t>(y1) * w + x0], d = v[static_cast<size_t>(y1) * w + x1];
        return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy;
    }
};

// Paper-colour estimate of one channel: shrink, grow the light parts over the
// ink (max filter), smooth. Small enough to be cheap, smooth enough not to
// follow text.
SmallMap illuminationMap(const uint8_t* rgba, int w, int h, int channel) {
    int sw, sh;
    fitSize(w, h, 160, &sw, &sh);
    Plane small = boxDownscale(rgba, w, h, static_cast<size_t>(w) * 4, 4, channel, sw, sh);
    // Window wide enough to reach paper from the middle of a large photo/block.
    Plane grown = maxFilter(small, std::max(3, std::min(sw, sh) / 9));
    Plane smooth = gaussianBlur(grown, std::max(2.0f, std::min(sw, sh) / 18.f));
    SmallMap m;
    m.w = sw;
    m.h = sh;
    m.v.resize(smooth.px.size());
    for (size_t i = 0; i < m.v.size(); ++i) m.v[i] = std::max(1.f, static_cast<float>(smooth.px[i]));
    return m;
}

inline float smoothstep(float a, float b, float x) {
    const float t = std::clamp((x - a) / (b - a), 0.f, 1.f);
    return t * t * (3.f - 2.f * t);
}

}  // namespace

void applyFilter(uint8_t* rgba, int width, int height, Filter filter) {
    if (!rgba || width < 2 || height < 2 || filter == Filter::Original) return;
    const SmallMap bgR = illuminationMap(rgba, width, height, 0);
    const SmallMap bgG = illuminationMap(rgba, width, height, 1);
    const SmallMap bgB = illuminationMap(rgba, width, height, 2);
    const float mx = static_cast<float>(bgR.w - 1) / std::max(1, width - 1);
    const float my = static_cast<float>(bgR.h - 1) / std::max(1, height - 1);

    for (int y = 0; y < height; ++y) {
        uint8_t* p = rgba + static_cast<size_t>(y) * width * 4;
        for (int x = 0; x < width; ++x, p += 4) {
            const float u = x * mx, v = y * my;
            const float rr = p[0] / bgR.sample(u, v);
            const float gg = p[1] / bgG.sample(u, v);
            const float bb = p[2] / bgB.sample(u, v);
            float out[3];
            if (filter == Filter::Color) {
                out[0] = std::clamp((rr - 0.12f) / 0.76f, 0.f, 1.f);
                out[1] = std::clamp((gg - 0.12f) / 0.76f, 0.f, 1.f);
                out[2] = std::clamp((bb - 0.12f) / 0.76f, 0.f, 1.f);
            } else {
                const float l = 0.30f * rr + 0.59f * gg + 0.11f * bb;
                const float g = filter == Filter::Gray ? std::clamp((l - 0.12f) / 0.76f, 0.f, 1.f)
                                                       : smoothstep(0.55f, 0.80f, l);
                out[0] = out[1] = out[2] = g;
            }
            for (int c = 0; c < 3; ++c) p[c] = static_cast<uint8_t>(out[c] * 255.f + 0.5f);
        }
    }
}

}  // namespace docscan
