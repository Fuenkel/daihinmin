# 大富豪大貧民用サーバAP

## 概要

本プログラムは`大富豪大貧民`のAIを動作させるためのプラットフォームとなっている。
ルールに基づいて作成された`AIプログラム`がゲームを行うための機能を提供する。

## 機能一覧

### 全体管理

* 参加ユーザの追加、削除 
* ゲームを実行するための場の作成
* 場とユーザの結びつけ
* ゲームの進行管理

### ゲームの管理

* 手札の配布
* 参加プレイヤーへの状況通知
* プレイヤー毎の限定情報提供用のAPI
* プレイヤーからの手の受け取り
* 場に出したカードが出すことが可能だったかどうかの判定
* ゲームごとの順位管理

### 画面

* 各種管理用画面
* ゲーム状況表示画面
* ゲーム結果表示画面
* 手動プレイ用画面

## 用語の定義

<table>
  <tr>
    <th>名前</th>
    <th>意味</th>
  </tr>
  <tr>
    <td>`User`</td>
    <td>ゲームに参加するユーザ。</td>
  </tr>
  <tr>
    <td>`Place`</td>
    <td>参加するユーザとゲームを保持する場のこと。場の中でゲームが行われる。</td>
  </tr>
  <tr>
    <td>`Player`</td>
    <td>場に参加するユーザのこと。</td>
  </tr>
  <tr>
    <td>`Game`</td>
    <td>場の中で行われるゲーム。大富豪大貧民の基本単位。</td>
  </tr>
  <tr>
    <td>`Turn`</td>
    <td>ゲームの中でのプレイヤーの一行動。</td>
  </tr>
</table>

## 採用するルール



