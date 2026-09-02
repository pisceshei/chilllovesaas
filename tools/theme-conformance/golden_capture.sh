#!/usr/bin/env bash
# 真店金標本抓取：hoko.vip（pnrjnw-sy）目前已發布主題的全頁 HTML
# 用法：bash golden_capture.sh <label> [base_url]
set -u
LABEL="$1"; BASE="${2:-https://hoko.vip}"
OUT="$(dirname "$0")/golden/$LABEL"; mkdir -p "$OUT"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128 Safari/537.36"
fetch() { # name path
  local name="$1" path="$2"
  curl -sS -L --compressed -A "$UA" -D "$OUT/$name.headers" -o "$OUT/$name.html" "$BASE$path" \
    -w "%{http_code} %{size_download} $path\n"
}
echo "== capture $LABEL @ $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
fetch index "/"
fetch collections "/collections"
fetch collection-all "/collections/all"
fetch cart "/cart"
fetch search "/search?q=a"
fetch notfound "/nope-404-probe"
fetch products-json "/products.json?limit=5"
fetch collections-json "/collections.json?limit=10"
fetch cart-js "/cart.js"
fetch localization "/localization"
# 第二輪：由 JSON 發現的 handle（商品／系列）＋首頁連結裡的 pages/blogs
PY=python
PRODUCT_HANDLES=$($PY -c "import json,sys;print(' '.join(p['handle'] for p in json.load(open('$OUT/products-json.html',encoding='utf-8')).get('products',[])[:3]))" 2>/dev/null)
COLLECTION_HANDLES=$($PY -c "import json,sys;print(' '.join(c['handle'] for c in json.load(open('$OUT/collections-json.html',encoding='utf-8')).get('collections',[])[:3]))" 2>/dev/null)
LINKS=$($PY -c "
import re,io
s=io.open('$OUT/index.html',encoding='utf-8',errors='replace').read()
hs=set(re.findall(r'href=\"(/(?:pages|blogs)/[a-z0-9\-]+(?:/[a-z0-9\-]+)?)\"',s))
print(' '.join(sorted(hs)[:8]))" 2>/dev/null)
for h in $PRODUCT_HANDLES; do fetch "product-$h" "/products/$h"; done
for h in $COLLECTION_HANDLES; do fetch "collection-$h" "/collections/$h"; done
for l in $LINKS; do n=$(echo "$l" | tr '/' '_' | sed 's/^_//'); fetch "$n" "$l"; done
echo "== Shopify.theme =="
grep -o 'Shopify.theme = {[^}]*}' "$OUT/index.html" | head -1
grep -o '"name":"[^"]*","id":[0-9]*' "$OUT/index.html" | head -1
echo "== section count (index) =="; grep -o 'id="shopify-section-[^"]*"' "$OUT/index.html" | wc -l
ls -la "$OUT" | awk '{print $5, $9}' | grep html
