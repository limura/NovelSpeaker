#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""voicevox_core.h の enum 宣言を Swift から列挙型として見える形に直す。

上流のヘッダは列挙型を

    enum VoicevoxResultCode
    #ifdef __cplusplus
      : int32_t
    #endif // __cplusplus
    {
      ...
    };
    #ifndef __cplusplus
    typedef int32_t VoicevoxResultCode;
    #endif // __cplusplus

と宣言している。この形だと Swift からは単なる Int32 に見えてしまい、
VoicevoxResultCode 等を列挙型として扱えない。これを

    typedef enum VoicevoxResultCode
    #ifdef __cplusplus
      : int32_t
    #endif // __cplusplus
    {
      ...
    } VoicevoxResultCode;

に直す。VoicevoxCore.swift はこの形を前提にしている。

以前は行位置を持つ .patch を当てていたが、上流に enum が1つ増えた
(0.17.0 の VoicevoxOnExistingVoiceModelId)だけで当たらなくなったため、
「その形の宣言を探して直す」方式にしてある。enum が増減しても当たる。

何度実行しても結果は同じ(直っている物は飛ばす)。
"""

import re
import sys

# enum 宣言まるごと。名前が前後で一致している事も込みで見る。
PATTERN = re.compile(
    r"^enum (?P<name>\w+)\n"
    r"(?P<cxx>#ifdef __cplusplus\n"
    r"  : int32_t\n"
    r"#endif // __cplusplus\n)"
    r"(?P<brace>[ \t]*)\{\n"
    r"(?P<body>.*?)\n"
    r"\};\n"
    r"#ifndef __cplusplus\n"
    r"typedef int32_t (?P=name);\n"
    r"#endif // __cplusplus\n",
    re.MULTILINE | re.DOTALL,
)


def fix(source):
    """(直した後の中身, 直した数) を返す。"""
    count = 0

    def replace(match):
        nonlocal count
        count += 1
        return (f"typedef enum {match.group('name')}\n"
                f"{match.group('cxx')}"
                f"{match.group('brace')}{{\n"
                f"{match.group('body')}\n"
                f"}} {match.group('name')};\n")

    return PATTERN.sub(replace, source), count


def already_fixed(source):
    """直し済みの enum の数。struct の typedef と紛れないよう enum だけ数える。"""
    return len(re.findall(r"^typedef enum \w+$", source, re.MULTILINE))


def main(argv):
    if len(argv) < 2:
        print("使い方: voicevox_core_header_fix.py <voicevox_core.h> ...", file=sys.stderr)
        return 2

    total_fixed = 0
    total_already = 0
    for path in argv[1:]:
        with open(path, encoding="utf-8") as handle:
            source = handle.read()

        fixed_source, count = fix(source)
        if count == 0:
            already = already_fixed(source)
            if already == 0:
                # 直す物も直っている物も無い = 上流の書き方が変わった。
                # 黙って通すと Swift 側が壊れるので、ここで止める。
                print(f"エラー: 直すべき enum が見つかりません。"
                      f"上流のヘッダの書き方が変わった可能性があります: {path}",
                      file=sys.stderr)
                return 1
            total_already += already
            continue

        with open(path, "w", encoding="utf-8") as handle:
            handle.write(fixed_source)
        total_fixed += count

    if total_fixed > 0:
        print(f"fixed={total_fixed}")
    else:
        print(f"already={total_already}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
