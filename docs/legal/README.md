# Legal docs — bản public cho store listing

2 file văn bản pháp lý bắt buộc khi đăng store (Play Console yêu cầu URL
Privacy Policy; Terms nên có để đối chiếu khiếu nại):

- `terms-of-service.md` — Điều khoản sử dụng
- `privacy-policy.md` — Chính sách riêng tư

## Đồng bộ với in-app

Nội dung **phải khớp** với màn in-app
(`mobile/lib/feature/legal/presentation/screens/legal_docs.dart`). Khi sửa,
sửa CẢ HAI nơi + giữ cùng ngày cập nhật. (Test `legal_docs_test.dart` kiểm tra
các nội dung bắt buộc ở phía app.)

## Cách host (0đ — Cloudflare Pages)

```bash
# Cách 1 — wrangler pages (repo này):
cd docs && npx wrangler pages deploy legal --project-name appvantai-legal
#   → https://appvantai-legal.pages.dev/terms-of-service.md
#     https://appvantai-legal.pages.dev/privacy-policy.md

# Cách 2 — GitHub Pages: bật Settings → Pages trên repo, nguồn /docs.
```

URL thu được điền vào Play Console (Store listing → Privacy Policy) và dùng
cho form Data safety. Play Console hiển thị tốt hơn khi là HTML — có thể dùng
renderer bất kỳ (GitHub tự render .md; hoặc 1 trang HTML tĩnh bọc nội dung).
