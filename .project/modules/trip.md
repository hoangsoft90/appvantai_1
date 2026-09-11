# modules/trip.md — Chuyến + Cargo Radar + GPS

## Làm gì

Driver khai chuyến A→B (one_way / return chiều về) bằng geocode search, quét
"radar" tìm đơn tiện đường (core value), chạy chuyến có GPS.

## API endpoints

| Endpoint | Ghi chú |
|---|---|
| `POST /trips` | driver only; `trip_type one_way\|return`; rate limit 20/h (KV); route qua provider (cache D1); lưu polyline 1e6 |
| `GET /trips`, `GET /trips/:id` | chỉ chuyến của chính driver (sai chủ → 404) |
| `POST /trips/:id/matches` | pipeline 6 bước: grid pre-filter (lọc cả block 2 chiều) → corridor ≤10km → bearing ≤135° (return: B→A) → time + feasibility (40km/h + 30') → Top-5 detour OSRM ≤15km → score /125→100 + reasons VN; persist db.batch |
| `POST /trips/:id/start` | planned → active (GPS bật) |
| `POST /trips/:id/end` | active → ended + xóa KV location |
| `POST /trips/:id/location` | **chỉ active** — planned → 400 `TRIP_NOT_ACTIVE` (plan3 Mục 3); throttle 30s, KV TTL 2h |

## Match response (contract card đọc)

`score`, `subtotal`, `detour_km` (nullable), `pickup_km`, `reasons[]`, `order{…}`
— card: "Khỏi tuyến"/"Độ lệch" nullable → "—" (không 0 giả).

## Local storage

Không. Radar/compile luôn gọi API; GPS qua `LocationService` (geolocator).

## Files

`feature/trip/…`: form (geocode + segmented chiều), `trip_matches_screen` (stats +
empty state 3 gợi ý), `trip_run_screen` + `TripRunController` (xin quyền → gửi GPS
ngay + Timer 30s; end offline-safe pending "chưa sync" + retry; `reconcile()` khi
app reopen trả ReconcileResult + banner quyền) · backend `routes/trips.ts`,
`services/trips.ts`, `matching.ts`, `gps.ts`, `route_cache.ts`, `maps/*`.

## Lỗi đáng nhớ

- Trip `ended/cancelled` → matches 400 `TRIP_NOT_ACTIVE`.
- OSRM 403 khi thiếu User-Agent (đã set trong provider).
- Local D1 có đơn `posted` cũ → poison Top-5 → matches rỗng ảo (wipe trước test).

## Spec

`openspec/specs/trip-matching/spec.md` (có Verification evidence Phase 6) ·
`trip-gps/spec.md` · `maps-geocoding/spec.md`
