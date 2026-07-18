# Active Record 関連機能対応マトリクス（Rails 7.2 / 8.1）

rails-mmdの対象版はRails 7.2と8.1。
状態は「対応」「条件付き」「未対応」。次は番号が最小の未完了P1を実装する。

## 優先対応

| 優先順位 | Active Record機能 | rails-mmd | 現在の不足 | 完了条件 |
|---|---|---|---|---|
| P1-01 | Rails 7.2/8.1実行互換 | 対応 | 3組のRuby/Rails境界matrixがpre-pushでPASS | 3組のRuby/Rails境界matrixをpre-pushで通す |
| P1-02 | 全関連macroの検出 | 対応 | 全reflectionを分類し、未対応macroを診断済み | 全reflectionを分類し、未対応macroを診断する |
| P1-03 | `has_many` / `has_one` | 未対応 | 描画しない | direct関連とself joinの多重度を検証する |
| P1-04 | `inverse_of` | 未対応 | 逆関連を照合しない | 同じ論理関連を1本のcanonical edgeへ統合する |
| P1-05 | `has_many :through` / `has_one :through` | 未対応 | through経路を展開しない | 中間modelと到達先を重複なく描画する |
| P1-06 | polymorphic | 未対応 | 診断して省略 | 型列と対象候補を重複なく描画する |
| P1-07 | `has_and_belongs_to_many` | 未対応 | 無言で省略 | join tableを検証し、単一の多対多関連として描画する |

## 後続候補

| 優先順位 | Active Record機能 | rails-mmd | 完了条件 |
|---|---|---|---|
| P2-01 | scoped関連 | 未対応 | scopeの存在をmetadataとして保持する |
| P2-02 | STI | 未対応 | 基底・派生classの表示規則を定める |
| P2-03 | `delegated_type` | 未対応 | 委譲元と具象型を描画する |
| P2-04 | 複合primary/foreign key、`query_constraints` | 未対応 | 対応する列組を保持・照合する |
| P2-05 | `primary_key` / `source` / `source_type` / `as` | 未対応 | option別に対象とkeyを解決する |
| P2-06 | cross-domain / multi-DB | 未対応 | 境界を外部nodeまたは診断で表現する |
| P2-07 | `dependent` / `touch` / `counter_cache` | 未対応 | 図へ載せる動作metadataを定義する |
| P3-01 | `disable_joins` / `strict_loading` / async | 未対応 | 実行特性の表示要否を決める |
| P3-02 | association extension | 未対応 | 構造と無関係な拡張を診断またはmetadata化する |

## 対応済み基盤

Rails 7.2/8.1で次を対応済み。

- 非polymorphic・unscoped・scalar direct `belongs_to`
- scalar `foreign_key`と`class_name`
- FK、nullability、unique indexによる保守的な多重度
- same-domain限定のER/Class出力
- 対応範囲内の`belongs_to`除外診断

## 根拠

- 現行契約: [P0 contract](p0-contract.md)
- 実装: [relationship builder](../lib/rails_mmd/relationship_builder.rb)、[render plan builder](../lib/rails_mmd/render_plan_builder.rb)
- Rails仕様: [Association Basics](https://guides.rubyonrails.org/association_basics.html)、[Rails 7.2 API](https://api.rubyonrails.org/v7.2/classes/ActiveRecord/Associations/ClassMethods.html)、[Rails 8.1 API](https://api.rubyonrails.org/v8.1/classes/ActiveRecord/Associations/ClassMethods.html)
