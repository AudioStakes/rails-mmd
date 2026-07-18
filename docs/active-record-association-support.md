# Active Record 関連機能対応マトリクス（Rails 7.2 / 8.1）

rails-mmdの対象版はRails 7.2と8.1。
状態は「対応」「条件付き」「未対応」。次は番号が最小の未完了P1を実装する。

## 優先対応

| 優先順位 | Active Record機能 | rails-mmd | 現在の不足 | 完了条件 |
|---|---|---|---|---|
| P1-01 | Rails 7.2/8.1実行互換 | 対応 | 3組のRuby/Rails境界matrixがpre-pushでPASS | 3組のRuby/Rails境界matrixをpre-pushで通す |
| P1-02 | 全関連macroの検出 | 対応 | 全reflectionを分類し、未対応macroを診断済み | 全reflectionを分類し、未対応macroを診断する |
| P1-03 | `has_many` / `has_one` | 対応 | direct関連・self join・暫定重複抑止を検証済み | direct関連とself joinの多重度を検証する |
| P1-04 | `inverse_of` | 対応 | inverse有無に依存せず物理関連をcanonical edgeへ統合済み | 同じ論理関連を1本のcanonical edgeへ統合する |
| P1-05 | `has_many :through` / `has_one :through` | 対応 | 推論sourceの1段・nested経路をsemantic edgeとして描画済み | 中間modelと到達先を重複なく描画する |
| P1-06 | polymorphic | 対応 | 選択済みinverse候補を対象別edgeへ正規化済み | 型列と対象候補を重複なく描画する |
| P1-07 | `has_and_belongs_to_many` | 対応 | hidden join tableを検証し、正規化した単一の多対多関連として描画済み | join tableを検証し、単一の多対多関連として描画する |

## 後続候補

| 優先順位 | Active Record機能 | rails-mmd | 完了条件 |
|---|---|---|---|
| P2-01 | scoped関連 | 対応 | scope procを実行せず、解決済み関連へ`metadata.scoped: true`を保持する |
| P2-02 | STI | 対応 | ERは共有tableの基底のみ、class図はloaded concrete subtypeと継承edgeを決定的に描画する |
| P2-03 | `delegated_type` | 対応 | Rails生成type whitelistを安全に検出し、委譲元から描画可能な宣言済み具象型へ具体edgeを描画する |
| P2-04 | 複合primary/foreign key、`query_constraints` | 対応 | 順序付き列組を全層で保持し、完全一致するDB制約・nullability・unique根拠を照合する。複合HABTMは対応Railsで実用不可のため診断して省略する |
| P2-05 | `primary_key` / `source` / `source_type` / `as` | 対応 | Railsが解決した物理bindingとtyped source targetを使い、custom scalar/composite keyを決定的に描画する |
| P2-06 | cross-domain / multi-DB | 対応 | domain境界とconnection-context境界を原因別warningで省略し、異context同名tableの公開ID衝突だけをfatal診断する |
| P2-07 | `dependent` / `touch` / `counter_cache` | 未対応 | 図へ載せる動作metadataを定義する |
| P3-01 | `disable_joins` / `strict_loading` / async | 未対応 | 実行特性の表示要否を決める |
| P3-02 | association extension | 未対応 | 構造と無関係な拡張を診断またはmetadata化する |

## 対応済み基盤

Rails 7.2/8.1で次を対応済み。

- 非polymorphic・unscopedのscalar/composite direct `belongs_to`、`has_many`、`has_one`
- scalar/ordered composite `foreign_key`、model-level `query_constraints`、`class_name`
- FK、nullability、unique indexによる保守的な多重度
- same-domain限定のER/Class出力
- 対応範囲内の`belongs_to`除外診断
- scalar/composite direct polymorphic `belongs_to`と`has_many` / `has_one ..., as:`候補
- hidden join tableを持つunscoped scalar `has_and_belongs_to_many`。複合HABTMは対応Railsのruntime probeに基づき診断して省略
- provenance確認済み`delegated_type`の宣言済み具象型（同一connection・同一domain）
- direct `primary_key:`、explicit through `source:`、polymorphic `source_type:`、custom `as:` binding

## 根拠

- 現行契約: [P0 contract](p0-contract.md)
- 実装: [relationship builder](../lib/rails_mmd/relationship_builder.rb)、[render plan builder](../lib/rails_mmd/render_plan_builder.rb)
- Rails仕様: [Association Basics](https://guides.rubyonrails.org/association_basics.html)、[Rails 7.2 API](https://api.rubyonrails.org/v7.2/classes/ActiveRecord/Associations/ClassMethods.html)、[Rails 8.1 API](https://api.rubyonrails.org/v8.1/classes/ActiveRecord/Associations/ClassMethods.html)
