#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""VOICEVOX の音声モデル(VVM)カタログを、公式リポジトリから作り直す。

カタログは「どの styleId を使うにはどのファイルが要るか」の対応表で、
ことせかい の音声モデル取得UIはこれを見て動く。
詳細は DESIGN_VOICEVOXの音声モデル取得.md を参照。

**1.5GB をダウンロードする必要は無い。**
VVM は無圧縮の zip で、先頭に manifest.json と metas.json が平文で並んでいるため、
各ファイルの先頭 64KB だけ Range GET すれば話者情報が読める(合計 約1.6MB)。

**参照するタグは必ずコアのバージョンと同じにする。**
main は次のコア版に進んでいる事があり、その VVM は形式が変わっていて
古いコアでは開けない(0.17.0 で vvm_format_version が 1→2 になった)。

規約URLは metas.json には入っていない。公式の voicevox_resource リポジトリにある
character_info/<名前>_<UUID>/policy.md から取る。

**突き合わせは名前ではなく UUID で行う。**
ディレクトリ名は記号が落ちていて metas.json の名前と一致しない事がある
(「小夜/SAYO」→「小夜SAYO」、「ナースロボ＿タイプＴ」→「ナースロボタイプＴ」、
 「†聖騎士 紅桜†」→「聖騎士紅桜」)。UUID は metas.json にもディレクトリ名にも入っている。

なお voicevox_vvm の README にも規約の節はあるが、**雨晴はう が抜けている**
(0.16.4 でも main でも)。0.vvm に入っているキャラなので無視できない。
policy.md 側には揃っているので、そちらを正とする。

1キャラでも規約URLが引けなかったら、**エラーで止める**。
規約を提示せずに配るのは義務違反なので、黙って通してはいけない。

使い方:
    scripts/update_voicevox_catalog.py                  カタログを作り直す
    scripts/update_voicevox_catalog.py --check          差分だけ報告する(書かない)
    scripts/update_voicevox_catalog.py --gh-pages-out <path>/data/VoicevoxVoiceModelCatalog.json
"""

import argparse
import datetime
import json
import os
import re
import struct
import sys
import urllib.error
import urllib.request

# 配るVVMの一式。**形式(vvm_format_version)ごとに1つ**用意する。
#
# なぜコアのバージョンごとではなく形式ごとなのか:
#   新しいコアは古い形式も読める(0.17.0 のソースに
#   「互換性維持のために残している旧式(vvm_format_version=1)」とある)。
#   壊れるのは「古いコア × 新しい形式」の一方向だけなので、
#   互換性を決めているのは形式であってコアのバージョンではない。
#   形式はめったに変わらないが、コアのバージョンは頻繁に上がる。
#
# 古いアプリ(iOSのバージョンで更新できない端末など)も、
# 自分が読める形式の項目を使い続けられる。
# タグは凍結されるので新キャラは来ないが、**配布URLが変わった時に直せる**のが効く。
#
# (タグ名, vvm_format_version, その形式を読める最小のコアのバージョン)
VVM_VARIANTS = [
    ("0.16.4", 1, "0.16.0"),
    ("0.17.0", 2, "0.17.0"),
]

# このカタログファイル自体の形式。
CATALOG_FORMAT_VERSION = 2
# これ以上は探さない(404 で止まるはずだが、無限ループの保険)
MAX_VVM_INDEX = 200
# zip の先頭からこれだけ取れば manifest.json と metas.json が読める(実測で数KB)
HEAD_FETCH_BYTES = 64 * 1024

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(REPO_ROOT, "NovelSpeaker", "VoicevoxVoiceModelCatalog.json")


def vvm_url(tag, index):
    return f"https://raw.githubusercontent.com/VOICEVOX/voicevox_vvm/{tag}/vvms/{index}.vvm"


def terms_page_url(tag):
    """VOICEVOX 音声モデル全体の利用規約(キャラ個別の規約とは別に、常に提示する)。"""
    return f"https://github.com/VOICEVOX/voicevox_vvm/blob/{tag}/README.md"


RESOURCE_REPO = "VOICEVOX/voicevox_resource"
RESOURCE_TREE_API = f"https://api.github.com/repos/{RESOURCE_REPO}/git/trees/main?recursive=1"


def policy_url(directory):
    from urllib.parse import quote
    return (f"https://raw.githubusercontent.com/{RESOURCE_REPO}/main/"
            f"character_info/{quote(directory)}/policy.md")


def http_get(url, byte_range=None, timeout=120):
    request = urllib.request.Request(url)
    if byte_range is not None:
        request.add_header("Range", f"bytes={byte_range[0]}-{byte_range[1]}")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read(), dict(response.headers)


def http_size(url, timeout=60):
    """存在すればバイト数を、404 なら None を返す。"""
    request = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            length = response.headers.get("Content-Length")
            return int(length) if length is not None else None
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def read_zip_head_entries(data, wanted):
    """無圧縮 zip の先頭から、欲しいファイル名の中身を取り出す。

    local file header を順に辿るだけ。中央ディレクトリは末尾にあるので見ない
    (見ようとすると結局ファイル全体が要る)。
    """
    found = {}
    offset = 0
    while offset + 30 <= len(data) and data[offset:offset + 4] == b"PK\x03\x04":
        (_sig, _ver, _flag, method, _mtime, _mdate, _crc,
         compressed_size, uncompressed_size, name_len, extra_len) = struct.unpack(
            "<IHHHHHIIIHH", data[offset:offset + 30])
        name = data[offset + 30:offset + 30 + name_len].decode("utf-8", "replace")
        body = offset + 30 + name_len + extra_len
        if name in wanted:
            if method != 0:
                raise RuntimeError(f"{name} が無圧縮ではありません(method={method})。"
                                   "VVM の作り方が変わった可能性があります")
            if body + uncompressed_size > len(data):
                raise RuntimeError(f"{name} が先頭 {len(data)} バイトに収まっていません。"
                                   "HEAD_FETCH_BYTES を増やしてください")
            found[name] = data[body:body + uncompressed_size]
            if len(found) == len(wanted):
                return found
        offset = body + compressed_size
    return found


def character_directories_by_uuid():
    """voicevox_resource の character_info/ を UUID から引ける形にする。

    ディレクトリ名は "<名前>_<UUID>"。名前側は記号が落ちている事があるので、
    **UUID だけを鍵にする**。
    """
    body, _ = http_get(RESOURCE_TREE_API)
    tree = json.loads(body)
    if "tree" not in tree:
        raise RuntimeError(f"voicevox_resource の一覧を取れませんでした: {tree.get('message')}")
    result = {}
    for entry in tree["tree"]:
        match = re.fullmatch(r"character_info/([^/]+_([0-9a-f-]{36}))", entry["path"])
        if match and entry["type"] == "tree":
            result[match.group(2)] = match.group(1)
    if not result:
        raise RuntimeError("voicevox_resource に character_info/<名前>_<UUID>/ が見つかりません")
    return result


def parse_policy(markdown, speaker_name):
    """policy.md から規約URLとクレジット表記を拾う。

        雨晴はうの音声ライブラリを用いて生成した音声は、
        「VOICEVOX:雨晴はう」とクレジットを記載すれば、商用・非商用で利用可能です。

        利用規約の詳細は以下をご確認ください。
        https://amehau.com/?page_id=225
    """
    urls = re.findall(r"https?://\S+", markdown)
    if not urls:
        return None
    credit_match = re.search(r"「(VOICEVOX[:：][^」]+)」", markdown)
    return {
        "termsURL": urls[-1].rstrip("　 \t"),
        "credit": credit_match.group(1) if credit_match else f"VOICEVOX:{speaker_name}",
        # 「企業が携わる場合は事前確認が必要」等の条件が書かれている事があるので、
        # 全文をそのまま持っておいて同意画面に出せるようにする。
        "policyText": markdown.strip(),
    }


OFFICIAL_SITE = "https://voicevox.hiroshiba.jp"


def official_page_lookup(verbose=True):
    """キャラクター名 → 公式サイトの紹介ページ。

    ★サンプル音声そのものは持ってこられない。
    voicevox_resource の character_info/*/voice_samples/ にも、公式サイトの
    product ページにもサンプルの wav はあるが、どちらも
    「VOICEVOX の開発のための利用のみ許可」であって、
    ことせかい が取り込んで鳴らしてよい物ではない
    (voicevox_resource の README のライセンス節)。
    そこで、取得前に声を確かめたい人は公式サイトへ送る。

    名前とURLの対応は公式サイトのトップページから拾う。
    ページの作りが変わったら拾えなくなるが、その時は
    「サンプルへの動線が消える」だけで、取得も規約提示も影響を受けない。
    そのため、ここでは止めずに警告だけ出す。
    """
    try:
        body, _ = http_get(OFFICIAL_SITE + "/")
    except Exception as error:  # noqa: BLE001  動線が消えるだけなので握り潰す
        if verbose:
            print(f"公式サイトのキャラクター一覧を取れませんでした({error})。"
                  "サンプルへの動線は入りません")
        return lambda name: None

    html = body.decode("utf-8", "replace")
    by_name = {}
    for match in re.finditer(r'href="(/product/[^"]+)"[^>]*>(.{0,300}?)</a>', html, re.S):
        text = re.sub(r"<[^>]+>", "", match.group(2))
        text = re.sub(r"\s+", "", text)
        if text:
            by_name.setdefault(text, OFFICIAL_SITE + match.group(1))
    if verbose:
        print(f"公式サイトのキャラクター紹介ページ: {len(by_name)} 件")

    def page_for(name):
        # 「†聖騎士 紅桜†」のように、metas.json と公式サイトとで
        # 空白の入り方が違う事があるので、空白を潰して突き合わせる。
        return by_name.get(re.sub(r"\s+", "", name))

    return page_for


def make_terms_lookup(verbose=True):
    directories = character_directories_by_uuid()
    if verbose:
        print(f"voicevox_resource のキャラクター情報: {len(directories)} 件")

    terms_cache = {}

    def terms_for(uuid, name):
        if uuid in terms_cache:
            return terms_cache[uuid]
        directory = directories.get(uuid)
        if directory is None:
            terms_cache[uuid] = None
            return None
        try:
            body, _ = http_get(policy_url(directory))
        except urllib.error.HTTPError:
            terms_cache[uuid] = None
            return None
        terms_cache[uuid] = parse_policy(body.decode("utf-8"), name)
        return terms_cache[uuid]

    return terms_for


def build_variant(tag, expected_format, minimum_core_version, terms_for,
                  official_page_for, verbose=True):
    if verbose:
        print(f"タグ {tag} (形式 {expected_format}) を見ています")
    voice_models = []
    missing_terms = set()
    missing_pages = set()
    index = 0
    while index < MAX_VVM_INDEX:
        url = vvm_url(tag, index)
        size = http_size(url)
        if size is None:
            break
        head, _ = http_get(url, byte_range=(0, HEAD_FETCH_BYTES - 1))
        entries = read_zip_head_entries(head, {"manifest.json", "metas.json"})
        for required in ("manifest.json", "metas.json"):
            if required not in entries:
                raise RuntimeError(f"{index}.vvm から {required} を読めませんでした")
        manifest = json.loads(entries["manifest.json"])
        metas = json.loads(entries["metas.json"])

        format_version = manifest.get("vvm_format_version")
        if format_version != expected_format:
            raise RuntimeError(
                f"{index}.vvm の vvm_format_version が {format_version} ですが、"
                f"タグ {tag} には {expected_format} を期待しています。"
                "VVM_VARIANTS の指定を見直してください")

        speakers = []
        for meta in metas:
            name = meta["name"]
            uuid = meta.get("speaker_uuid")
            term = terms_for(uuid, name)
            if term is None:
                missing_terms.add(f"{name} ({uuid})")
                term = {"termsURL": None, "credit": None, "policyText": None}
            if official_page_for(name) is None:
                missing_pages.add(name)
            speakers.append({
                "name": name,
                "uuid": uuid,
                "version": meta.get("version"),
                "termsURL": term["termsURL"],
                "credit": term["credit"],
                "policyText": term["policyText"],
                "officialPageURL": official_page_for(name),
                "styles": [{"name": style["name"], "styleId": style["id"]}
                           for style in meta.get("styles", [])],
            })

        voice_models.append({
            "id": str(index),
            "url": url,
            "byteSize": size,
            "vvmFormatVersion": format_version,
            "speakers": speakers,
        })
        if verbose:
            names = "・".join(s["name"] for s in speakers)
            print(f"  {index}.vvm  {size / 1024 / 1024:6.1f}MB  {names}")
        index += 1

    if not voice_models:
        raise RuntimeError(f"タグ {tag} に vvms/0.vvm がありません")

    if missing_terms:
        # 規約を提示できないキャラを混ぜて配るのは義務違反なので、ここで止める。
        raise RuntimeError(
            "規約URLが引けないキャラクターがいます: " + "、".join(sorted(missing_terms)) +
            f"\n{RESOURCE_REPO} の character_info/ に、その UUID のディレクトリと"
            " policy.md があるか確認してください。"
            "\n規約を提示せずに配る事はできないので、ここは黙って通しません")

    if missing_pages and verbose:
        # 動線が消えるだけなので止めない。公式サイトの表記が変わった時に気付ける様にだけしておく。
        print("  公式サイトの紹介ページが見つからないキャラクター: "
              + "、".join(sorted(missing_pages)))

    return {
        "vvmFormatVersion": expected_format,
        "vvmTag": tag,
        "minimumCoreVersion": minimum_core_version,
        "termsPageURL": terms_page_url(tag),
        "voiceModels": voice_models,
    }


def build_catalog(verbose=True):
    terms_for = make_terms_lookup(verbose=verbose)
    official_page_for = official_page_lookup(verbose=verbose)
    variants = [build_variant(tag, fmt, core, terms_for, official_page_for, verbose=verbose)
                for tag, fmt, core in VVM_VARIANTS]
    return {
        "formatVersion": CATALOG_FORMAT_VERSION,
        "generatedAt": datetime.datetime.now(datetime.timezone.utc)
                               .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "variants": variants,
    }


def load_existing(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def comparable(catalog):
    """生成日時など、内容と関係ない差を除いた形。"""
    if catalog is None:
        return None
    copied = dict(catalog)
    copied.pop("generatedAt", None)
    return copied


def variants_by_format(catalog):
    if not catalog:
        return {}
    return {variant["vvmFormatVersion"]: variant for variant in catalog.get("variants", [])}


def describe_variant_difference(label, old, new):
    lines = []

    def by_id(variant):
        return {model["id"]: model for model in (variant or {}).get("voiceModels", [])}

    if old.get("vvmTag") != new.get("vvmTag"):
        lines.append(f"{label}: タグが変わりました {old.get('vvmTag')} → {new.get('vvmTag')}")

    old_models, new_models = by_id(old), by_id(new)
    for model_id in sorted(set(new_models) - set(old_models), key=int):
        lines.append(f"{label}: 増えました {model_id}.vvm")
    for model_id in sorted(set(old_models) - set(new_models), key=int):
        lines.append(f"{label}: 無くなりました {model_id}.vvm")
    for model_id in sorted(set(old_models) & set(new_models), key=int):
        old_model, new_model = old_models[model_id], new_models[model_id]
        if old_model.get("byteSize") != new_model.get("byteSize"):
            lines.append(f"{label}: 大きさが変わりました {model_id}.vvm "
                         f"{old_model.get('byteSize')} → {new_model.get('byteSize')}")
        if old_model.get("url") != new_model.get("url"):
            lines.append(f"{label}: 取得先が変わりました {model_id}.vvm")

        def styles_of(model):
            return {(s["name"], style["styleId"])
                    for s in model.get("speakers", []) for style in s.get("styles", [])}

        old_styles, new_styles = styles_of(old_model), styles_of(new_model)
        for name, style_id in sorted(new_styles - old_styles):
            lines.append(f"{label}: スタイルが増えました {model_id}.vvm {name} (styleId={style_id})")
        for name, style_id in sorted(old_styles - new_styles):
            lines.append(f"{label}: スタイルが無くなりました {model_id}.vvm {name} (styleId={style_id})")
    return lines


def describe_difference(old, new):
    if old is None:
        return ["手元にカタログがありません(新規作成)"]
    lines = []
    if old.get("formatVersion") != new.get("formatVersion"):
        lines.append(f"カタログの形式が変わりました: "
                     f"{old.get('formatVersion')} → {new.get('formatVersion')}")
    old_variants, new_variants = variants_by_format(old), variants_by_format(new)
    for fmt in sorted(set(new_variants) - set(old_variants)):
        lines.append(f"★VVM形式 {fmt} の一式が増えました"
                     f"(タグ {new_variants[fmt].get('vvmTag')})")
    for fmt in sorted(set(old_variants) - set(new_variants)):
        lines.append(f"★VVM形式 {fmt} の一式が無くなりました。"
                     "その形式しか読めない古いアプリが取得できなくなります")
    for fmt in sorted(set(old_variants) & set(new_variants)):
        lines.extend(describe_variant_difference(f"形式{fmt}", old_variants[fmt], new_variants[fmt]))
    return lines


def write_catalog(path, catalog):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def summarize(catalog):
    for variant in catalog["variants"]:
        speakers = {s["name"] for m in variant["voiceModels"] for s in m["speakers"]}
        styles = sum(len(s["styles"]) for m in variant["voiceModels"] for s in m["speakers"])
        total = sum(m["byteSize"] for m in variant["voiceModels"])
        print(f"  形式{variant['vvmFormatVersion']} (タグ {variant['vvmTag']} / "
              f"コア {variant['minimumCoreVersion']}以降): "
              f"{len(variant['voiceModels'])}ファイル / {len(speakers)}キャラ / "
              f"{styles}スタイル / {total / 1024 / 1024 / 1024:.2f}GB")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="書かずに差分だけ報告する")
    parser.add_argument("--out", default=DEFAULT_OUT, help="アプリ内蔵カタログの書き出し先")
    parser.add_argument("--gh-pages-out", default=None,
                        help="配布用カタログの書き出し先(gh-pages の data/ 以下)")
    args = parser.parse_args()

    try:
        catalog = build_catalog(verbose=not args.check)
    except Exception as error:  # noqa: BLE001 - 利用者に理由を見せて止まるのが目的
        print(f"エラー: {error}", file=sys.stderr)
        return 1

    summarize(catalog)

    existing = load_existing(args.out)
    if comparable(existing) == comparable(catalog):
        print("手元のカタログと同じ内容です。")
        return 0
    for line in describe_difference(existing, catalog):
        print(f"  ★ {line}")

    if args.check:
        print("--check なので書き込みません。")
        return 1

    write_catalog(args.out, catalog)
    print(f"書きました: {args.out}")
    if args.gh_pages_out:
        write_catalog(args.gh_pages_out, catalog)
        print(f"書きました: {args.gh_pages_out}")
    else:
        print("配布用は書いていません(--gh-pages-out で gh-pages の data/ 以下を指定してください)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
