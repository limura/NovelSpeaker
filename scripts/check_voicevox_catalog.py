#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""同梱している VOICEVOX 音声モデルカタログの点検(通信しない)。

カタログが古いまま出すと**利用者が取得できない**。
特に危ないのは「コアを上げたのにカタログを作り直していない」場合で、
アプリが読めない形式のVVMを指したまま配る事になる
(コアは VOICEVOX_RESULT_INVALID_MODEL_HEADER_ERROR で弾く)。
これはビルドが通ってしまうので、ここで気付けるようにする。

通信しないので、Xcode の Run Script から毎回呼んでも遅くならない。
公式側の更新に気付く仕組みは別(scripts/update_voicevox_catalog.py --check)。

使い方:
    scripts/check_voicevox_catalog.py            人が読む形で報告する
    scripts/check_voicevox_catalog.py --xcode    Xcode の警告/エラー形式で出す
    scripts/check_voicevox_catalog.py --strict   警告も失敗扱いにする(exit 1)
"""

import argparse
import datetime
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_PATH = os.path.join(ROOT, "NovelSpeaker", "VoicevoxVoiceModelCatalog.json")
LOADER_PATH = os.path.join(ROOT, "NovelSpeaker", "VoicevoxVoiceModelCatalog.swift")
FETCH_SCRIPT_PATH = os.path.join(ROOT, "scripts", "fetch_voicevox_vendor.sh")

# これより古いカタログは、公式の更新を取りこぼしている可能性が高い。
DEFAULT_MAX_AGE_DAYS = 120


def read_core_version():
    """アプリに入るコアのバージョン。fetch スクリプトの CORE_VERSION が正。"""
    with open(FETCH_SCRIPT_PATH, encoding="utf-8") as handle:
        match = re.search(r'^readonly\s+CORE_VERSION="([^"]+)"', handle.read(), re.M)
    return match.group(1) if match else None


def read_swift_constants():
    """アプリ側が「読める」と宣言している形式と、カタログ形式の上限。"""
    with open(LOADER_PATH, encoding="utf-8") as handle:
        source = handle.read()
    supported = re.search(r"supportedFormatVersion\s*=\s*(\d+)", source)
    readable = re.search(r"readableVvmFormatVersions:\s*Set<Int>\s*=\s*\[([^\]]*)\]", source)
    readable_set = set()
    if readable:
        readable_set = {int(x) for x in re.findall(r"\d+", readable.group(1))}
    return (int(supported.group(1)) if supported else None), readable_set


def check(max_age_days):
    """(errors, warnings) を返す。errors はリリースしてはいけない物。"""
    errors = []
    warnings = []

    if not os.path.exists(CATALOG_PATH):
        return ([f"同梱カタログがありません: {CATALOG_PATH}"], [])
    with open(CATALOG_PATH, encoding="utf-8") as handle:
        catalog = json.load(handle)

    supported, readable = read_swift_constants()
    core_version = read_core_version()

    if supported is None or not readable:
        warnings.append("VoicevoxVoiceModelCatalog.swift から定数を読めませんでした(点検を省略します)")
        return (errors, warnings)

    if catalog.get("formatVersion", 0) > supported:
        errors.append(
            f"カタログの形式({catalog.get('formatVersion')})が、"
            f"アプリが解釈できる上限({supported})を超えています")

    variants = {v["vvmFormatVersion"]: v for v in catalog.get("variants", [])}
    usable = [v for fmt, v in variants.items() if fmt in readable and v.get("voiceModels")]
    if not usable:
        errors.append(
            f"このアプリのコアが読める形式{sorted(readable)}の一式がカタログにありません。"
            " これを出すと音声モデルを1つも取得できません")
        return (errors, warnings)

    # ★コアを上げたらカタログも作り直す。ここが食い違うと、
    #   アプリが読めない形式のVVMを指したまま配る事になる。
    newest = max(usable, key=lambda v: v["vvmFormatVersion"])
    if core_version and newest.get("vvmTag") != core_version:
        errors.append(
            f"コア {core_version} に対して、使われる一式のタグが {newest.get('vvmTag')} です。"
            " scripts/update_voicevox_catalog.py で作り直してください"
            " (VVM_VARIANTS と readableVvmFormatVersions も合わせる事)")

    # 規約URLとクレジット表記が全キャラに揃っている事(提示できないまま配れない)。
    for variant in catalog.get("variants", []):
        for model in variant.get("voiceModels", []):
            for speaker in model.get("speakers", []):
                if not speaker.get("termsURL"):
                    errors.append(f"{model['id']}.vvm の {speaker.get('name')} に規約URLがありません")
                if not speaker.get("credit"):
                    errors.append(f"{model['id']}.vvm の {speaker.get('name')} にクレジット表記がありません")

    generated_at = catalog.get("generatedAt")
    if generated_at:
        try:
            stamp = datetime.datetime.fromisoformat(generated_at.replace("Z", "+00:00"))
            age = (datetime.datetime.now(datetime.timezone.utc) - stamp).days
            if age > max_age_days:
                warnings.append(
                    f"カタログを作ってから {age} 日経っています"
                    f"({generated_at})。scripts/update_voicevox_catalog.py --check で"
                    " 公式側の更新を確認してください")
        except ValueError:
            warnings.append(f"generatedAt を読めませんでした: {generated_at}")
    else:
        warnings.append("カタログに generatedAt がありません")

    return (errors, warnings)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--xcode", action="store_true", help="Xcode の警告/エラー形式で出す")
    parser.add_argument("--strict", action="store_true", help="警告も失敗扱いにする")
    parser.add_argument("--max-age-days", type=int, default=DEFAULT_MAX_AGE_DAYS)
    args = parser.parse_args()

    errors, warnings = check(args.max_age_days)

    for message in warnings:
        if args.xcode:
            print(f"{CATALOG_PATH}:1: warning: {message}")
        else:
            print(f"警告: {message}")
    for message in errors:
        if args.xcode:
            print(f"{CATALOG_PATH}:1: error: {message}")
        else:
            print(f"エラー: {message}", file=sys.stderr)

    if errors:
        return 1
    if warnings and args.strict:
        return 1
    if not args.xcode:
        print("カタログの点検: 問題ありません。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
