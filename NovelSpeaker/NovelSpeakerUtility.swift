//
//  NovelSpeakerUtility.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/24.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Zip

class NovelSpeakerUtility: NSObject {
    static let privacyPolicyURL = URL(string: "https://raw.githubusercontent.com/limura/NovelSpeaker/master/PrivacyPolicy.txt")
    static let privacyPolicyKey = "NovelSpeaker_ReadedPrivacyPolicy"
    static func GetReadedPrivacyPolicy() -> String {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [privacyPolicyKey : ""])
        return defaults.string(forKey: privacyPolicyKey) ?? ""
    }
    static func SetPrivacyPolicyIsReaded(readedText:String) {
        UserDefaults.standard.set(readedText, forKey: privacyPolicyKey)
    }
    
    static let defaultSpeechModSettings:[String:String] = [
        "黒剣": "コッケン"
        , "黒尽くめ": "黒づくめ"
        , "黒剣": "コッケン"
        , "鶏ガラ": "トリガラ"
        , "魚醤": "ギョショウ"
        , "魔石": "ませき"
        , "魔獣": "まじゅう"
        , "魔導": "まどう"
        , "魔人": "まじん"
        , "駄弁る": "だべる"
        , "食い千切": "くいちぎ"
        , "飛翔体": "ヒショウタイ"
        , "飛来物": "ヒライブツ"
        , "願わくば": "ねがわくば"
        , "頑な": "かたくな"
        , "静寂": "せいじゃく"
        , "霊子": "れいし"
        , "霊体": "れいたい"
        , "集音": "シュウオン"
        , "闘術": "闘じゅつ"
        , "間髪": "カンパツ"
        , "金属片": "金属ヘン"
        , "金属板": "キンゾクバン"
        , "重装備": "ジュウソウビ"
        , "重火器": "ジュウカキ"
        , "重武装": "ジュウブソウ"
        , "重機関銃": "ジュウキカンジュウ"
        , "重低音": "ジュウテイオン"
        , "遮蔽物": "シャヘイブツ"
        , "遠まわし": "とおまわし"
        , "過去形": "カコケイ"
        , "火器": "ジュウカキ"
        , "造作もな": "ゾウサもな"
        , "通信手": "ツウシンシュ"
        , "轟炎": "ゴウエン"
        , "車列": "シャレツ"
        , "身分証": "ミブンショウ"
        , "身体能力": "しんたい能力"
        , "身体": "からだ"
        , "身を粉に": "身をコに"
        , "蹴散ら": "ケチら"
        , "踵を返": "きびすを返"
        , "貴船": "キセン"
        , "貧乳": "ひんにゅう"
        , "謁見の間": "謁見のま"
        , "解毒薬": "ゲドクヤク"
        , "規格外": "キカクガイ"
        , "要確認": "ヨウ確認"
        , "要救助者": "ヨウ救助者"
        , "複数人": "複数ニン"
        , "装甲板": "装甲バン"
        , "術者": "ジュツシャ"
        , "術式": "ジュツシキ"
        , "術師": "ジュツシ"
        , "行ってらっしゃい": "いってらっしゃい"
        , "行ってきます": "いってきます"
        , "行ったり来たり": "いったりきたり"
        , "血肉": "チニク"
        , "虫唾が走": "ムシズが走"
        , "薬師": "くすし"
        , "薬室": "やくしつ"
        , "薄明り": "うすあかり"
        , "薄ら": "ウスラ"
        , "荷馬車": "ニバシャ"
        , "艶めかし": "なまめかし"
        , "艶かし": "なまめかし"
        , "艦首": "カンシュ"
        , "艦影": "カンエイ"
        , "船外": "センガイ"
        , "脳筋": "ノウキン"
        , "聖骸布": "セーガイフ"
        , "聖骸": "セーガイ"
        , "聖騎士": "セイキシ"
        , "義体": "ギタイ"
        , "美男子": "ビナンシ"
        , "美味さ": "ウマさ"
        , "美味い": "うまい"
        , "美乳": "びにゅう"
        , "縞々": "シマシマ"
        , "緊急時": "キンキュウジ"
        , "絢十": "あやと"
        , "経験値": "経験チ"
        , "素体": "そたい"
        , "純心": "ジュンシン"
        , "精神波": "セイシンハ"
        , "米粒": "コメツブ"
        , "等間隔": "トウカンカク"
        , "笑い者": "ワライモノ"
        , "竜人": "リュウジン"
        , "空賊": "クウゾク"
        , "私掠船": "シリャクセン"
        , "神獣": "シンジュウ"
        , "祖父ちゃん": "じいちゃん"
        , "知性体": "知性たい"
        , "瞬殺": "シュンサツ"
        , "着艦": "チャッカン"
        , "真っ暗": "まっくら"
        , "真っ只中": "マッタダナカ"
        , "真っ二つ": "まっぷたつ"
        , "相も変わ": "アイも変わ"
        , "直継": "ナオツグ"
        , "発艦": "ハッカン"
        , "発射管": "ハッシャカン"
        , "発射口": "ハッシャコウ"
        , "異能": "イノウ"
        , "異空間": "イクウカン"
        , "異種族": "いしゅぞく"
        , "異界": "イカイ"
        , "異獣": "いじゅう"
        , "異次元": "いじげん"
        , "異世界": "イセカイ"
        , "男性器": "ダンセイキ"
        , "甜麺醤": "テンメンジャン"
        , "甘っちょろ": "アマっちょろ"
        , "環境下": "環境か"
        , "理想形": "リソウケイ"
        , "獣道": "けものみち"
        , "獣人": "じゅうじん"
        , "牛すじ": "ギュウスジ"
        , "爆発物": "バクハツブツ"
        , "爆炎": "ばくえん"
        , "熱波": "ネッパ"
        , "照ら": "てら"
        , "煎れ": "いれ"
        , "火星": "カセイ"
        , "火器": "カキ"
        , "漢探知": "男探知"
        , "漏ら": "もら"
        , "満タン": "まんたん"
        , "淹れ": "いれ"
        , "海賊船": "海賊セン"
        , "海兵隊": "かいへいたい"
        , "浮遊物": "フユウブツ"
        , "汝ら": "なんじら"
        , "氷のう": "ヒョウノウ"
        , "水場": "水ば"
        , "気弾": "キダン"
        , "気に食": "きにく"
        , "民間船": "ミンカンセン"
        , "殺人鬼": "サツジンキ"
        , "死に体": "シニタイ"
        , "機雷原": "キライゲン"
        , "構造物": "コウゾウブツ"
        , "極悪人": "ゴクアクニン"
        , "極々": "ゴクゴク"
        , "来いよ": "こいよ"
        , "木製": "モクセイ"
        , "望み薄": "ノゾミウス"
        , "月光神": "ゲッコウシン"
        , "最上階": "さいじょうかい"
        , "星間物質": "セイカンブッシツ"
        , "星系": "セイケイ"
        , "星域": "セイイキ"
        , "敵船": "テキセン"
        , "敵性体": "敵性たい"
        , "敵わない": "かなわない"
        , "数週間": "スウシュウカン"
        , "支配下": "シハイカ"
        , "擲弾": "てきだん"
        , "操船中": "ソウセンチュウ"
        , "操船": "そうせん"
        , "接敵": "セッテキ"
        , "排泄物": "ハイセツブツ"
        , "掌砲長": "ショウホウチョウ"
        , "掌砲手": "ショウホウシュ"
        , "掌打": "しょうだ"
        , "掌帆長": "ショウハンチョウ"
        , "指揮車": "シキシャ"
        , "拙い": "マズイ"
        , "技術者": "ギジュツシャ"
        , "手練れ": "テダレ"
        , "所狭し": "トコロセマシ"
        , "成程": "なるほど"
        , "慌ただし": "あわただし"
        , "愛国心": "アイコクシン"
        , "愛おし": "いとおし"
        , "悪趣味": "あくしゅみ"
        , "悪戯": "いたずら"
        , "急ごしらえ": "キュウゴシラエ"
        , "念話": "ネンワ"
        , "忠誠心": "忠誠シン"
        , "忌み子": "イミコ"
        , "心配性": "シンパイショウ"
        , "心拍": "シンパク"
        , "徹甲弾": "テッコウダン"
        , "微乳": "びにゅう"
        , "後がない": "アトがない"
        , "彷徨う": "さまよう"
        , "影響下": "エイキョウカ"
        , "弾着": "ダンチャク"
        , "弾倉": "だんそう"
        , "強張る": "こわばる"
        , "引きこもり": "ひきこもり"
        , "幻獣": "ゲンジュウ"
        , "幸か不幸": "コウかフコウ"
        , "年単位": "ネンタンイ"
        , "平常心": "ヘイジョウシン"
        , "席替え": "セキガエ"
        , "巨乳": "きょにゅう"
        , "小柄": "こがら"
        , "小型船": "コガタセン"
        , "小一時間": "コ1時間"
        , "対戦車": "たいせんしゃ"
        , "寝顔": "ネガオ"
        , "害獣": "ガイジュウ"
        , "安酒": "ヤスザケ"
        , "宇宙船乗り": "ウチュウセンノリ"
        , "宇宙暦": "ウチュウレキ"
        , "宇宙人": "ウチュウジン"
        , "孫子": "ソンシ"
        , "姫君": "ヒメギミ"
        , "姉上": "アネウエ"
        , "姉ぇ": "ネエ"
        , "妖艶": "ようえん"
        , "妖獣": "ヨウジュウ"
        , "妖人": "ようじん"
        , "奴ら": "ヤツら"
        , "女性器": "ジョセイキ"
        , "女子力": "女子りょく"
        , "太陽神": "タイヨウシン"
        , "太もも": "フトモモ"
        , "天晴れ": "アッパレ"
        , "大馬鹿": "オオバカ"
        , "大賢者": "だいけんじゃ"
        , "大津波": "オオツナミ"
        , "大泣き": "オオナキ"
        , "大所帯": "オオジョタイ"
        , "大慌て": "おおあわて"
        , "大怪我": "オオ怪我"
        , "大地人": "だいちじん"
        , "大嘘": "オオウソ"
        , "大人": "おとな"
        , "大っぴら": "おおっぴら"
        , "外殻": "ガイカク"
        , "外惑星": "ガイワクセイ"
        , "壊れ難": "壊れにく"
        , "墓所": "ボショ"
        , "地球外": "チキュウガイ"
        , "地底人": "ちていじん"
        , "回頭": "カイトウ"
        , "喰う": "くう"
        , "喜声": "キセイ"
        , "問題外": "モンダイガイ"
        , "問題児": "問題じ"
        , "商根たくまし": "ショウコンたくまし"
        , "呻り声": "唸り声"
        , "同じ様": "同じヨウ"
        , "可笑し": "おかし"
        , "召喚術": "ショウカンジュツ"
        , "召喚獣": "ショウカンジュウ"
        , "友軍艦": "ユウグンカン"
        , "去り際": "サリギワ"
        , "厨二": "チュウニ"
        , "厄介者": "ヤッカイモノ"
        , "南部": "なんぶ"
        , "千載一遇": "センザイイチグウ"
        , "千切れ": "ちぎれ"
        , "勝負所": "勝負ドコロ"
        , "力場": "りきば"
        , "創造神": "ソウゾウシン"
        , "剣鬼": "ケンキ"
        , "剣聖": "ケンセイ"
        , "剣神": "ケンシン"
        , "初見": "しょけん"
        , "初弾": "ショダン"
        , "分身": "ぶんしん"
        , "分は悪": "ブは悪"
        , "分が悪": "ブが悪"
        , "再戦": "サイセン"
        , "円筒形": "円筒ケイ"
        , "内容物": "ナイヨウブツ"
        , "入出口": "ニュウシュツコウ"
        , "兎に角": "とにかく"
        , "光秒": "コウビョウ"
        , "光時": "コウジ"
        , "光分": "コウフン"
        , "兄ちゃん": "ニイチャン"
        , "兄ぃ": "にい"
        , "健康体": "健康タイ"
        , "偏光": "ヘンコウ"
        , "俺達": "おれたち"
        , "何時の間": "いつのま"
        , "何？": "なに？"
        , "体育祭": "タイイクサイ"
        , "体当たり": "たいあたり"
        , "以ての外": "モッテノホカ"
        , "他ならぬ": "ほかならぬ"
        , "仔牛": "コウシ"
        , "今作戦": "コン作戦"
        , "人肉": "じんにく"
        , "人的資源": "ジンテキシゲン"
        , "人狼": "じんろう"
        , "人数分": "ニンズウブン"
        , "人工物": "ジンコウブツ"
        , "予定表": "ヨテイヒョウ"
        , "乱高下": "ランコオゲ"
        , "主機": "シュキ"
        , "主兵装": "シュヘイソウ"
        , "中破": "チュウハ"
        , "中年": "ちゅうねん"
        , "中の中": "チュウのチュウ"
        , "中の下": "チュウのゲ"
        , "中の上": "チュウのジョウ"
        , "世界樹": "せかいじゅ"
        , "不届き者": "不届きモノ"
        , "不味い": "まずい"
        , "下ネタ": "シモネタ"
        , "下の中": "ゲのチュウ"
        , "下の下": "ゲのゲ"
        , "下の上": "ゲのジョウ"
        , "上腕二頭筋": "ジョウワンニトウキン"
        , "上方修正": "じょうほう修正"
        , "上の中": "ジョウのチュウ"
        , "上の下": "ジョウのゲ"
        , "上の上": "ジョウのジョウ"
        , "三日三晩": "ミッカミバン"
        , "三国": "サンゴク"
        , "三々五々": "さんさんごご"
        , "万人": "マンニン"
        , "一級品": "イッキュウヒン"
        , "一目置": "イチモク置"
        , "一目惚れ": "ヒトメボレ"
        , "一派": "イッパ"
        , "一日の長": "イチジツノチョウ"
        , "一品物": "イッピンモノ"
        , "一分の隙": "いちぶの隙"
        , "ボクっ娘": "ボクっ子"
        , "ペルセウス腕": "ペルセウスワン"
        , "ペイント弾": "ペイントダン"
        , "ドジっ娘": "ドジっ子"
        , "シュミレー": "シミュレー"
        , "カレー粉": "カレーコ"
        , "カズ彦": "カズヒコ"
        , "よそ者": "ヨソモノ"
        , "ひと言": "ヒトコト"
        , "の宴": "のうたげ"
        , "にゃん太": "ニャンタ"
        , "そこら中": "ソコラジュウ"
        , "この上ない": "このうえない"
        , "お米": "おこめ"
        , "お祖父": "おじい"
        , "お姉": "オネエ"
        , "お兄様": "おにいさま"
        , "お兄さま": "おにいさま"
        , "お付き": "おつき"
        , "いつの間に": "いつのまに"
        , "ある種": "あるしゅ"
        , "あっという間": "あっというま"
        
        // 2016/07/29 added.
        , "～": "ー"
        , "麻婆豆腐": "マーボードーフ"
        , "麻婆": "マーボー"
        , "豆板醤": "トーバンジャン"
        , "言葉少な": "言葉すくな"
        , "聖印": "セイイン"
        , "籠城": "ロウジョウ"
        , "禁術": "キンジュツ"
        , "神兵": "シンペイ"
        , "着ぐるみ": "キグルミ"
        , "白狼": "ハクロウ"
        , "町人": "チョウニン"
        , "恐怖心": "キョウフシン"
        , "幼生体": "幼生タイ"
        , "天神": "テンジン"
        , "大皿": "オオザラ"
        , "大喧嘩": "オオゲンカ"
        , "味方": "ミカタ"
        , "吐瀉物": "トシャブツ"
        , "古井戸": "フル井戸"
        , "兄様": "ニイサマ"
        , "使用人": "シヨウニン"
        , "体術": "タイジュツ"
        , "住人": "ジュウニン"
        , "亜人": "アジン"
        , "二つ名": "ふたつナ"
        , "三角コーナー": "サンカクコーナー"
        , "メイド頭": "メイドガシラ"
        , "トン汁": "トンジル"
        , "カツ丼": "カツドン"
        , "お祖母": "おばあ"
        
        // 2016/09/19 added.
        , "魔光弾": "マコーダン"
        , "雄たけび": "おたけび"
        , "跳弾": "チョウダン"
        , "貴国": "キコク"
        , "豚の角煮": "豚のカクニ"
        , "血飛沫": "血シブキ"
        , "船速": "センソク"
        , "空対空": "クウタイクウ"
        , "秘密裏": "秘密リ"
        , "砲口": "ホーコー"
        , "異民族": "イミンゾク"
        , "理論上": "理論ジョー"
        , "滑腔砲": "カッコウホウ"
        , "洋ゲー": "ヨウゲー"
        , "武術家": "ブジュツカ"
        , "敵機影": "敵キエイ"
        , "敵機": "テッキ"
        , "拗らせ": "こじらせ"
        , "打撃力": "ダゲキリョク"
        , "心技体": "シン、ギ、タイ"
        , "後退翼": "コウタイヨク"
        , "弾薬": "ダンヤク"
        , "弾帯": "ダンタイ"
        , "小悪党": "コアクトウ"
        , "導力": "ドウリョク"
        , "安月給": "ヤスゲッキュウ"
        , "女王様": "ジョオウサマ"
        , "多脚": "タキャク"
        
        // 2015/09/27 added.
        //, "あ、": "あぁ、"
        
        // 2018/07/25 added.
        , "お守り": "おまもり"
        
        // 2018/09/16 added.
        // 注："❗" 等の「元の文字のある絵文字」については、筆者による意図的なものの場合を考えて標準には入れない事にします
        //, "❗": "！"
        //, "❓": "？"
        
        , "〜": "ー"
        
        , "α": "アルファ"
        , "Α": "アルファ"
        , "β": "ベータ"
        , "Β": "ベータ"
        , "γ": "ガンマ"
        , "Γ": "ガンマ"
        , "δ": "デルタ"
        , "Δ": "デルタ"
        , "ε": "イプシロン"
        , "Ε": "イプシロン"
        , "ζ": "ゼータ"
        , "Ζ": "ゼータ"
        , "η": "エータ"
        , "θ": "シータ"
        , "Θ": "シータ"
        , "ι": "イオタ"
        , "κ": "カッパ"
        , "λ": "ラムダ"
        , "μ": "ミュー"
        , "ν": "ニュー"
        , "ο": "オミクロン"
        , "π": "パイ"
        , "Π": "パイ"
        , "ρ": "ロー"
        , "σ": "シグマ"
        , "Σ": "シグマ"
        , "τ": "タウ"
        , "υ": "ユプシロン"
        , "φ": "ファイ"
        , "Φ": "ファイ"
        , "χ": "カイ"
        , "ψ": "プサイ"
        , "ω": "オメガ"
        , "Ω": "オメガ"
        
        , "Ⅰ": "1"
        , "Ⅱ": "2"
        , "Ⅲ": "3"
        , "Ⅳ": "4"
        , "Ⅴ": "5"
        , "Ⅵ": "6"
        , "Ⅶ": "7"
        , "Ⅷ": "8"
        , "Ⅸ": "9"
        , "Ⅹ": "10"
        , "ⅰ": "1"
        , "ⅱ": "2"
        , "ⅲ": "3"
        , "ⅳ": "4"
        , "ⅴ": "5"
        , "ⅵ": "6"
        , "ⅶ": "7"
        , "ⅷ": "8"
        , "ⅸ": "9"
        , "ⅹ": "10"
        
        , "※": " "
        
        , "Plant hwyaden": "プラント・フロウデン"
        , "Ｐｌａｎｔ　ｈｗｙａｄｅｎ": "プラント・フロウデン"
        , "VRMMORPG": "VR MMORPG"
        , "ＢＩＳＨＯＰ": "ビショップ"
        , "ＡＩ": "エエアイ"
    ]
    static let defaultRegexpSpeechModSettings:[String:String] = [
        "([0-9０-９零壱弐参肆伍陸漆捌玖拾什陌佰阡仟萬〇一二三四五六七八九十百千万億兆]+)\\s*[〜]\\s*([0-9０-９零壱弐参肆伍陸漆捌玖拾什陌佰阡仟萬〇一二三四五六七八九十百千万億兆]+)": "$1から$2", // 100〜200 → 100から200
        "([0-9０-９零壱弐参肆伍陸漆捌玖拾什陌佰阡仟萬〇一二三四五六七八九十百千万億兆]+)\\s*話": "$1は"
    ]

    // 標準の読み替え辞書を上書き登録します。
    static func OverrideDefaultSpeechModSettings() {
        RealmUtil.Write { (realm) in
            for (before, after) in defaultSpeechModSettings {
                let speechModSetting = RealmSpeechModSetting()
                speechModSetting.before = before
                speechModSetting.after = after
                speechModSetting.isUseRegularExpression = false
                realm.add(speechModSetting, update: true)
            }
            for (before, after) in defaultRegexpSpeechModSettings {
                let speechModSetting = RealmSpeechModSetting()
                speechModSetting.before = before
                speechModSetting.after = after
                speechModSetting.isUseRegularExpression = true
                realm.add(speechModSetting, update: true)
            }
        }
    }

    // 保存されている読み替え辞書の中から、標準の読み替え辞書を全て削除します
    static func RemoveAllDefaultSpeechModSettings() {
        guard let allSpeechModSettings = RealmSpeechModSetting.GetAllObjects() else { return }
        var removeTargetArray:[RealmSpeechModSetting] = []
        for targetSpeechModSetting in allSpeechModSettings {
            var hit = false
            for (before, after) in defaultSpeechModSettings {
                if targetSpeechModSetting.before == before && targetSpeechModSetting.after == after && targetSpeechModSetting.isUseRegularExpression != true {
                    removeTargetArray.append(targetSpeechModSetting)
                    hit = true
                    break
                }
            }
            if hit { continue }
            for (before, after) in defaultRegexpSpeechModSettings {
                if targetSpeechModSetting.before == before && targetSpeechModSetting.after == after && targetSpeechModSetting.isUseRegularExpression == true {
                    removeTargetArray.append(targetSpeechModSetting)
                    break
                }
            }
        }
        RealmUtil.Write { (realm) in
            for targetSpeechModSetting in removeTargetArray {
                targetSpeechModSetting.delete(realm: realm)
            }
        }
    }
    
    // 保存されている全ての読み替え辞書を削除します
    static func RemoveAllSpeechModSettings() {
        guard let allSpeechModSettings = RealmSpeechModSetting.GetAllObjects() else { return }
        RealmUtil.Write { (realm) in
            for targetSpeechModSetting in allSpeechModSettings {
                targetSpeechModSetting.delete(realm: realm)
            }
        }
    }
    
    fileprivate static func CreateBackupDataDictionary_Story(novelID:String, contentWriteTo:URL?) -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let storyArray = RealmStory.GetAllObjects()?.filter("novelID = %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true) else { return result }
        for story in storyArray {
            if let contentWriteTo = contentWriteTo {
                do {
                    let filePath = contentWriteTo.appendingPathComponent("\(story.chapterNumber)")
                    try story.contentZiped.write(to: filePath)
                }catch{
                    print("\(story.novelID) chapter: \(story.chapterNumber) content write failed.")
                }
            }
            result.append([
                //"id": story.id,
                "novelID": story.novelID,
                "chapterNumber": story.chapterNumber,
                //"contentZiped": story.contentZiped,
                "readLocation": story.readLocation,
                "url": story.url,
                "lastReadDate": NiftyUtilitySwift.Date2ISO8601String(date: story.lastReadDate),
                "downloadDate": NiftyUtilitySwift.Date2ISO8601String(date: story.downloadDate),
                "subtitle": story.subtitle
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_Bookshelf(withAllStoryContent:Bool, contentWriteTo:URL, progress:((_ description:String)->Void)?) -> ([[String:Any]], [URL]) {
        var result:[[String:Any]] = []
        var fileArray:[URL] = []
        guard let novelArray = RealmNovel.GetAllObjects() else { return (result, []) }
        var novelCount = 1
        let novelArrayCount = novelArray.count
        for novel in novelArray {
            if let progress = progress {
                progress(NSLocalizedString("NovelSpeakerUtility_ExportingNovelData", comment: "小説を抽出中") + " (\(novelCount)/\(novelArrayCount))")
            }
            var novelData:[String:Any] = [
                "novelID": novel.novelID,
                "type": novel._type,
                "writer": novel.writer,
                "title": novel.title,
                "url": novel.url,
                "secret": NiftyUtility.stringEncrypt(novel._urlSecret, key: novel.novelID) ?? "",
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: novel.createdDate),
                "likeLevel": novel.likeLevel,
                "isNeedSpeechAfterDelete": novel.isNeedSpeechAfterDelete,
                "contentDirectory": "\(novelCount)"
            ]
            let contentDirectory = NiftyUtilitySwift.CreateDirectoryFor(path: contentWriteTo, directoryName: "\(novelCount)")
            switch novel.type {
            case .URL:
                if !withAllStoryContent {
                    novelData["storys"] = CreateBackupDataDictionary_Story(novelID: novel.novelID, contentWriteTo: nil)
                    break
                }
                fallthrough
            case .UserCreated:
                novelData["storys"] = CreateBackupDataDictionary_Story(novelID: novel.novelID, contentWriteTo: contentDirectory)
                if let contentDirectory = contentDirectory {
                    fileArray.append(contentDirectory)
                }
            }
            result.append(novelData)
            novelCount += 1
        }
        return (result, fileArray)
    }
    fileprivate static func CreateBackupDataDictionary_SpeechModSetting() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmSpeechModSetting.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
                "before": setting.before,
                "after": setting.after,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                "isUseRegularExpression": setting.isUseRegularExpression,
                "targetNovelIDArray": Array(setting.targetNovelIDArray)
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_SpeechWaitConfig() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmSpeechWaitConfig.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
                "delayTimeInSec": setting.delayTimeInSec,
                "targetText": setting.targetText,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate)
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_SpeakerSetting() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmSpeakerSetting.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
                "name": setting.name,
                "pitch": setting.pitch,
                "rate": setting.rate,
                "lmd": setting.lmd,
                "acc": setting.acc,
                "base": setting.base,
                "volume": setting.volume,
                "type": setting.type,
                "voiceIdentifier": setting.voiceIdentifier,
                "locale": setting.locale,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate)
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_SpeechSectionConfig() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmSpeechSectionConfig.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
                "startText": setting.startText,
                "endText": setting.endText,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                "speakerID": setting.speakerID,
                "targetNovelIDArray": Array(setting.targetNovelIDArray)
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_GlobalState() -> [String:Any] {
        guard let globalState = RealmGlobalState.GetInstance() else { return [:] }
        return [
            "maxSpeechTimeInSec": globalState.maxSpeechTimeInSec,
            "webImportBookmarkArray": Array(globalState.webImportBookmarkArray),
            "readedPrivacyPolicy": globalState.readedPrivacyPolicy,
            "isOpenRecentNovelInStartTime": globalState.isOpenRecentNovelInStartTime,
            "isLicenseReaded": globalState.isLicenseReaded,
            "isDuckOthersEnabled": globalState.isDuckOthersEnabled,
            "isMixWithOthersEnabled": globalState.isMixWithOthersEnabled,
            "isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled": globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled,
            "isDarkThemeEnabled": globalState.isDarkThemeEnabled,
            "isPlaybackDurationEnabled": globalState.isPlaybackDurationEnabled,
            "isShortSkipEnabled": globalState.isShortSkipEnabled,
            "isReadingProgressDisplayEnabled": globalState.isReadingProgressDisplayEnabled,
            "isForceSiteInfoReloadIsEnabled": globalState.isForceSiteInfoReloadIsEnabled,
            "isMenuItemIsAddSpeechModSettingOnly": globalState.isMenuItemIsAddSpeechModSettingOnly,
            //"isBackgroundNovelFetchEnabled": globalState.isBackgroundNovelFetchEnabled,
            "isPageTurningSoundEnabled": globalState.isPageTurningSoundEnabled,
            "bookSelfSortType": globalState._bookSelfSortType,

            "defaultDisplaySettingID": globalState.defaultDisplaySettingID,
            "defaultSpeakerID": globalState.defaultSpeakerID,
            "defaultSpeechOverrideSettingID": globalState.defaultSpeechOverrideSettingID
        ]
    }
    fileprivate static func CreateBackupDataDictionary_DisplaySetting() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmDisplaySetting.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
                "textSizeValue": setting.textSizeValue,
                "fontID": setting.fontID,
                "name": setting.name,
                "isVertical": setting.isVertical,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                "targetNovelIDArray": Array(setting.targetNovelIDArray)
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_NovelTag() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmNovelTag.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "name": setting.name,
                "type": setting.type,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                "targetNovelIDArray": Array(setting.targetNovelIDArray)
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_SpeechOverrideSetting() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmSpeechOverrideSetting.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
                "name": setting.name,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                "repeatSpeechType": setting._repeatSpeechType,
                "isOverrideRubyIsEnabled": setting.isOverrideRubyIsEnabled,
                "notRubyCharactorStringArray": setting.notRubyCharactorStringArray,
                "isIgnoreURIStringSpeechEnabled": setting.isIgnoreURIStringSpeechEnabled,
                "targetNovelIDArray": Array(setting.targetNovelIDArray)
            ])
        }
        return result
    }

    static func CreateBackupData(withAllStoryContent:Bool, progress:((_ description:String)->Void)?) -> Data? {
        let directoryName = "NovelSpeakerBackup"
        // 一旦対象のディレクトリを作って、中身を全部消します。
        if let outputPath = NiftyUtilitySwift.CreateTemporaryDirectory(directoryName: directoryName) {
            NiftyUtilitySwift.RemoveDirectory(directoryPath: outputPath)
        }
        // 改めてディレクトリを作り直します。
        guard let outputPath = NiftyUtilitySwift.CreateTemporaryDirectory(directoryName: directoryName) else {
            return nil
        }
        let bookshelfResult = CreateBackupDataDictionary_Bookshelf(withAllStoryContent: withAllStoryContent, contentWriteTo: outputPath, progress: progress)
        if let progress = progress {
            progress(NSLocalizedString("NovelSpeakerUtility_ExportOtherSettings", comment: "設定情報の抽出中"))
        }
        let jsonDictionary:[String:Any] = [
            "data_version": "2.0.0",
            "bookshelf": bookshelfResult.0,
            "word_replacement_dictionary": CreateBackupDataDictionary_SpeechModSetting(),
            "speech_wait_config": CreateBackupDataDictionary_SpeechWaitConfig(),
            "speaker_setting": CreateBackupDataDictionary_SpeakerSetting(),
            "speech_section_config": CreateBackupDataDictionary_SpeechSectionConfig(),
            "misc_settings": CreateBackupDataDictionary_GlobalState(),
            "display_setting": CreateBackupDataDictionary_DisplaySetting(),
            "novel_tag": CreateBackupDataDictionary_NovelTag(),
            "speech_override_setting": CreateBackupDataDictionary_SpeechOverrideSetting(),
        ]
        defer { NiftyUtilitySwift.RemoveDirectory(directoryPath: outputPath) }
        var ziptargetFiles:[URL] = bookshelfResult.1
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonDictionary, options: [.prettyPrinted])
            let backupDataPath = outputPath.appendingPathComponent("backup_data.json")
            try jsonData.write(to: backupDataPath)
            ziptargetFiles.append(backupDataPath)
        }catch{
            print("JSONSerizization.data() failed. or jsonData.write() failed.")
            return nil
        }
        if let progress = progress {
            progress(NSLocalizedString("NovelSpeakerBackup_CompressingBackupDataProgress", comment: "バックアップデータを圧縮中"))
        }
        let zipFilePath = NiftyUtilitySwift.GetTemporaryFilePath(fileName: NiftyUtilitySwift.Date2ISO8601String(date: Date()) + ".zip")
        do {
            try Zip.zipFiles(paths: ziptargetFiles, zipFilePath: zipFilePath, password: nil, compression: .BestCompression, progress: { (progressPercent) in
                let description = NSLocalizedString("NovelSpeakerBackup_CompressingBackupDataProgress", comment: "バックアップデータを圧縮中") + " (\(Int(progressPercent * 100))%)"
                if let progress = progress {
                    progress(description)
                }
            })
        }catch let err{
            print("zip file create error", zipFilePath.absoluteString, err)
            return nil
        }
        let zipData:Data
        do {
            zipData = try Data(contentsOf: zipFilePath, options: .dataReadingMapped)
        }catch let err{
            print("zip file read error", err)
            return nil
        }
        return zipData
    }
    
    static let LicenseReadKey = "NovelSpeaker_IsLicenseReaded"
    static func IsLicenseReaded() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [LicenseReadKey : false])
        return defaults.bool(forKey: LicenseReadKey)
    }
    static func SetLicenseReaded(isRead:Bool) {
        UserDefaults.standard.set(isRead, forKey: LicenseReadKey)
    }
}
