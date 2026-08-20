# code span 不得改變 HTML comment scope negative fixture

### CLAIM-001

- type: count
- corrected: 1
- recheck: `ruby -e 'puts 1'`

正文的 `<!--` 只是字面 code span，不應開啟 comment。

### CLAIM-002

- type: count
- corrected: 2

正文的 `-->` 只是字面 code span，不應關閉 comment。
