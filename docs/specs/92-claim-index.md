# 92 — 宣稱索引（可重跑計數）

> 本檔只收錄可由倉庫內容重算的計數宣稱。機械契約固定使用 `### CLAIM-NNN` 區塊；
> `type: count` 必須附一行 `recheck:` 可執行命令，否則 `scripts/check-doc-claims.rb` R6 阻擋。
> `baseline: HEAD` 表示命令應對目前樹重算；指定 commit 則表示不可拿歷史快照外推 HEAD。

### CLAIM-001

- type: count
- sources: `docs/specs/50-logic-gap-register.md` 表 3、附錄
- original: 表 3 把 C-01～C-16 寫成 15 條，因而寫成表 3 共 25、全簿共 313。
- corrected: C 列 16、T 列 10、表 3 共 26；附錄五表合計 314。
- baseline: HEAD
- recheck: `ruby -EUTF-8:UTF-8 -e 's=File.read("docs/specs/50-logic-gap-register.md"); c=s.scan(/^\| C-\d{2} /).size; t=s.scan(/^\| \*\*T-\d{2}\*\* \|/).size; sums=s.lines.filter_map{|l| m=l.match(/^\| \u8868 [1-5].*?\| \*\*(\d+)\*\*/); m&&m[1].to_i}; abort "unexpected structure" unless [c,t,sums.size]==[16,10,5]; p [c,t,c+t,sums.sum]'`
- status: corrected

### CLAIM-002

- type: count
- sources: `docs/specs/83-admin-1to1-audit-round3.md` §0、§1.1
- original: §0 寫本輪已修復 7 條 P0，但 §1.1 的逐項複驗列有 10 條。
- corrected: 本輪複驗為已修復的 P0 是 10 條；不得再用「53 的 10 條未解決」當這組的分母。
- baseline: HEAD
- recheck: `ruby -EUTF-8:UTF-8 -e 's=File.read("docs/specs/83-admin-1to1-audit-round3.md"); x=s[s.index(/^### 1\.1 /)...s.index(/^### 1\.2 /)]; ids=x.scan(/^\| (P0-\d+)/).flatten; abort "duplicate or wrong count" unless ids.uniq==ids && ids.size==10; p ids'`
- status: corrected

### CLAIM-003

- type: count
- sources: `docs/specs/84-m1-gate-triage.md` 起因、`docs/specs/71-admin-parity-sweep.md` §F
- original: 84 建檔文字把「81 條未結案」寫成無時間邊界的現值。
- corrected: 81 只保留為建檔原文的歷史引述；71 目前未結案列為 76。
- baseline: HEAD
- recheck: `ruby -EUTF-8:UTF-8 -e 'puts File.foreach("docs/specs/71-admin-parity-sweep.md").count{|l| l.start_with?("| 71-R") && l.split("|")[-2].to_s.strip.bytes.first(3)==[226,172,156]}'`
- status: corrected

### CLAIM-004

- type: count
- sources: `docs/specs/50-logic-gap-register.md` P1、`docs/specs/54-p1-logic-fixes.md`
- original: 50 的 P1 標題把來源列舉與下游拆分後工作項都稱為 33 條。
- corrected: 50 的來源列舉是 32 個分組；54 把 H-101／H-103 拆開後是 33 個下游工作項。
- baseline: HEAD
- recheck: `ruby -EUTF-8:UTF-8 -e 'a=File.read("docs/specs/50-logic-gap-register.md"); x=a[a.index(/^### P1/)...a.index(/^### P2/)]; rows=x.lines.select{|l| l.match?(/\A(?:\u91D1\u984D\/\u5951\u7D04\u985E|\u72C0\u614B\/\u5951\u7D04\u985E|\u898F\u5247\u985E)\uFF1A/)}; src=rows.join.scan(/(?:H|S|TW|T)-\d+(?:[\/\uFF5E](?:H|S|TW|T)-\d+)?/).size; b=File.read("docs/specs/54-p1-logic-fixes.md"); dst=b.scan(/^#### P1-\d{2}/).size; abort "unexpected counts" unless [src,dst]==[32,33]; p({source_groups:src,downstream_items:dst})'`
- status: corrected

### CLAIM-005

- type: count
- sources: `docs/specs/51-token-conformance.md` §6.2、`docs/design/48-component-contract.md` 的歷史快照
- original: 外部流傳的「48 新增 63 個 token」不是 48 自己的文字，且逐行 regex 漏算同列多宣告。
- corrected: 在指定歷史快照，§00 有 82 個不同宣告；與 23 §1 重疊 4 個，故新增 78 個。這不是 HEAD 現值。
- baseline: `e50b9120cc9b2514fde4995a5ff4f6ff15332bff`
- recheck: `ruby -EUTF-8:UTF-8 -e 'a=%x[git show e50b9120cc9b2514fde4995a5ff4f6ff15332bff:docs/design/48-component-contract.md]; b=%x[git show e50b9120cc9b2514fde4995a5ff4f6ff15332bff:docs/design/23-interaction-css-spec.md]; x=a[a.index("## §00")...a.index("## §0 ")]; aa=x.scan(/--[a-z0-9-]+\s*:/i).map{|v|v.delete_suffix(":").strip}.uniq; bb=b.scan(/--[a-z0-9-]+\s*:/i).map{|v|v.delete_suffix(":").strip}.uniq; p({declarations:aa.size,overlap:(aa&bb).size,new_tokens:aa.size-(aa&bb).size})'`
- status: corrected

### CLAIM-006

- type: count
- sources: `docs/specs/53-ui-gap-recheck.md` §0、§6、§9
- original: 162 是表 1–5 小計，卻以「合計」呈現，沒有納入同檔新增的 §6 與 §9。
- corrected: 表 1–5 小計 162、§6 回歸風險 7、§9 新發現 11；全文件口徑為 180。
- baseline: HEAD
- recheck: `ruby -EUTF-8:UTF-8 -e 's=File.read("docs/specs/53-ui-gap-recheck.md"); line=s.lines.find{|l| l.include?("**162**") && l.start_with?("| **")}; nums=line.scan(/\*\*(\d+)\*\*/).flatten; base=nums[1].to_i; risks=s.scan(/^\| \*\*R-\d{2}\*\* \|/).size; findings=s.scan(/^\| \*\*N-\d{2}\*\* \|/).size; abort "unexpected counts" unless [base,risks,findings]==[162,7,11]; p({tables_1_to_5:base,section_6:risks,section_9:findings,all:base+risks+findings})'`
- status: corrected
