# 92 — 宣稱索引（可重跑計數）

> 本檔只收錄可由倉庫內容重算的計數宣稱。機械契約固定使用 `### CLAIM-NNN` 區塊；
> `type: count` 必須附一行 `recheck:` 可執行命令，否則 `scripts/check-doc-claims.rb` R6 阻擋。
> `baseline: HEAD` 表示命令應對目前樹重算；指定 commit 則表示不可拿歷史快照外推 HEAD。

### CLAIM-001

- type: count
- sources: `docs/specs/50-logic-gap-register.md` 表 3、附錄
- original: P-2 輸入把 C-01～C-16 的 16 列都視為衝突，要求把表 3 從 25 改成 26、全簿從 313 改成 314。
- corrected: C 列雖有 16 列，但 C-16 是正面對照；15 條 C 衝突＋10 條 T 衝突＝表 3 共 25，附錄五表合計 313。
- baseline: HEAD
- recheck: `ruby -EUTF-8:UTF-8 -e 's=File.read("docs/specs/50-logic-gap-register.md"); c=s.lines.grep(/^\| C-\d{2} /); positive=c.count{|l| l.include?("三方一致正面清單")}; conflicts=c.size-positive; t=s.scan(/^\| \*\*T-\d{2}\*\* \|/).size; sums=s.lines.filter_map{|l| m=l.match(/^\| \u8868 [1-5].*?\| \*\*(\d+)\*\*/); m&&m[1].to_i}; table3=s.lines.find{|l|l.start_with?("| 表 3 ·")}.match(/\*\*(\d+)\*\*/)[1].to_i; total=s.lines.find{|l|l.start_with?("| **合計** |")}.match(/\*\*(\d+)\*\*/)[1].to_i; values=[c.size,conflicts,positive,t,sums.size,conflicts+t,table3,sums.sum,total]; abort "unexpected structure #{values.inspect}" unless values==[16,15,1,10,5,25,25,313,313]; p({c_rows:c.size,c_conflicts:conflicts,positive_controls:positive,t_conflicts:t,table_3:table3,total:total})'`
- status: corrected

### CLAIM-002

- type: count
- sources: `docs/specs/83-admin-1to1-audit-round3.md` §0、§1.1
- original: §0 寫本輪已修復 7 條 P0，但 §1.1 的逐項複驗列有 10 條。
- corrected: §1.1 有 10 列 P0 複驗紀錄；其中 8 列已修復，P0-14／P0-18 仍為部分修復。不得再用「53 的 10 條未解決」當這組的分母。
- baseline: HEAD
- recheck: `ruby -EUTF-8:UTF-8 -e 's=File.read("docs/specs/83-admin-1to1-audit-round3.md"); x=s[s.index(/^### 1\.1 /)...s.index(/^### 1\.2 /)]; rows=x.lines.filter_map{|l| m=l.match(/^\| (P0-\d+).*?\[(已修復|部分)\]/); m&&[m[1],m[2]]}; fixed=rows.select{|_,v|v=="已修復"}.map(&:first); partial=rows.select{|_,v|v=="部分"}.map(&:first); summary=s.lines.find{|l|l.start_with?("| 元件級（§6） |")}.split("|").map(&:strip); summary_ok=summary[3].scan(/P0-(?:14|18)/).empty? && summary[4].scan(/P0-(?:14|18)（部分）/)==%w[P0-14（部分） P0-18（部分）]; values=[rows.size,fixed.size,partial,summary_ok]; abort "unexpected states #{values.inspect}" unless values==[10,8,%w[P0-14 P0-18],true]; p({rows:rows.size,fixed:fixed,partial:partial,summary_synced:summary_ok})'`
- status: corrected

### CLAIM-003

- type: count
- sources: `docs/specs/84-m1-gate-triage.md` 起因、`docs/specs/71-admin-parity-sweep.md` §F
- original: 84 建檔文字把「81 條未結案」寫成無時間邊界的現值。
- corrected: 81 只保留為建檔原文的歷史引述；71 目前有 77 列狀態格含 `⬜`，其中 76 列以 `⬜` 起頭，另 1 列 71-R3-DOC1 為「✅ 考證；⬜ 選型」。77 是「仍含開放子項」口徑，不等於 71 §F 圖例表的純 `⬜` 未結案 76。
- baseline: HEAD
- recheck: `ruby -EUTF-8:UTF-8 -e 'rows=File.readlines("docs/specs/71-admin-parity-sweep.md",chomp:true).grep(/^\| 71-R/); statuses=rows.map{|l|p=l.split("|",-1);[p[1].strip,p[-2].strip]}; containing=statuses.count{|_,s|s.include?("⬜")}; leading=statuses.count{|_,s|s.start_with?("⬜")}; mixed=statuses.select{|_,s|s.include?("⬜")&&!s.start_with?("⬜")}.map(&:first); abort "unexpected unresolved status split #{[containing,leading,mixed].inspect}" unless [containing,leading,mixed]==[77,76,["71-R3-DOC1"]]; p({contains_open:containing,leading_open:leading,mixed:mixed})'`
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
- snapshot-48: `--ai-border,--art-404,--art-lg,--art-md,--art-sm,--attention-border,--border-strong,--bw-100,--bw-200,--critical-border,--ctl-24,--ctl-28,--ctl-32,--ctl-36,--ctl-40,--ctl-44,--disabled-opacity,--dur-bar-grow,--dur-shake,--dur-shimmer,--dur-toast-dwell,--ease-linear,--focus-glow,--focus-glow-critical,--focus-ring,--focus-ring-offset,--focus-ring-w,--h-topbar,--hit-min,--hit-row,--info-border,--r-000,--r-pill,--scrim,--selected-bg,--sh,--sh-modal,--sh-pop,--sh-sticky,--shake-amp,--sp-1200,--sp-800,--success-border,--surface-active,--surface-hover,--surface-inverse,--surface-sunken,--t-2xs,--t-3xl,--t-display,--text-inverse,--w-aside,--w-crumbtitle,--w-detail-max,--w-drawer,--w-index-max,--w-modal,--w-modal-lg,--w-modal-sm,--w-narrow,--w-popover-max,--w-popover-min,--w-search-shell,--w-search-shell-m,--w-settings-content,--w-settings-nav,--w-sidebar,--warning-border,--z-bulkbar,--z-content,--z-docpop,--z-drawer,--z-modal,--z-overlay,--z-popover,--z-savebar,--z-scrim,--z-settings,--z-sheet,--z-shell,--z-sticky,--z-toast`
- snapshot-23: `--ai,--ai-bg,--attention,--attention-bg,--bg,--border,--border-2,--brand,--brand-hover,--chart,--critical,--critical-bg,--focus,--grid,--info,--info-bg,--link,--r-btn,--r-card,--r-pill,--sh,--sh-modal,--sh-pop,--success,--success-bg,--surface,--surface-2,--surface-3,--text,--text-2,--text-3,--tr,--tr-big,--warning,--warning-bg`
- recheck: `ruby -EUTF-8:UTF-8 -e 's=File.read("docs/specs/92-claim-index.md"); aa=s[/^- snapshot-48: `([^`]+)`$/,1].split(","); bb=s[/^- snapshot-23: `([^`]+)`$/,1].split(","); abort "snapshot order or uniqueness changed" unless aa==aa.uniq.sort && bb==bb.uniq.sort; values=[aa.size,(aa&bb).size,aa.size-(aa&bb).size]; abort "unexpected snapshot counts #{values.inspect}" unless values==[82,4,78]; p({declarations:values[0],overlap:values[1],new_tokens:values[2]})'`
- status: corrected

### CLAIM-006

- type: count
- sources: `docs/specs/53-ui-gap-recheck.md` §0、§6、§9
- original: 162 是表 1–5 小計，卻以「合計」呈現，沒有納入同檔新增的 §6 與 §9。
- corrected: 表 1–5 小計 162、§6 回歸風險 7 列、§9 新發現 11 列；三段合計 180 個原始列次，但 §6／§9 有六組成對重述，因此 180 不代表 distinct gap 總數。
- baseline: HEAD
- recheck: `ruby -EUTF-8:UTF-8 -e 's=File.read("docs/specs/53-ui-gap-recheck.md"); line=s.lines.find{|l| l.include?("**162**") && l.start_with?("| **")}; nums=line.scan(/\*\*(\d+)\*\*/).flatten; base=nums[1].to_i; risks=s.scan(/^\| \*\*R-\d{2}\*\* \|/).size; findings=s.scan(/^\| \*\*N-\d{2}\*\* \|/).size; summary=s.lines.find{|l|l.include?("**列次口徑（未跨章去重）**")}; published=summary.scan(/\*\*(\d+)\*\*/).flatten.fetch(0).to_i; abort "unexpected counts" unless [base,risks,findings,published]==[162,7,11,180] && base+risks+findings==published; p({tables_1_to_5:base,section_6_rows:risks,section_9_rows:findings,row_occurrences:published,distinct_total:"not claimed"})'`
- status: corrected
