#!/bin/bash
#
# VOICEVOX 関連の大きなバイナリ(XCFramework・Open JTalk 辞書・検証用VVM)を
# 公式の配布元から取得して NovelSpeaker/Vendor/VoicevoxCore/ に配置する。
#
# これらは git には入れていない。理由:
#   - VVM は ことせかい が再配布者になってしまうため(利用者が公式から直接取得する方針)
#   - 辞書と XCFramework は再配布可能だが、合計145MBあり GitHub の LFS 無料枠
#     (1GB/月)を圧迫するため
#
# clone した直後は VOICEVOX 関連がビルドできないので、まずこれを実行する。
#
# 使い方:
#   scripts/fetch_voicevox_vendor.sh          取得して配置する(既にある物は飛ばす)
#   scripts/fetch_voicevox_vendor.sh --check  取得はせず、手元と公式の差だけ調べる
#   scripts/fetch_voicevox_vendor.sh --force  既にあっても取り直す
#
set -uo pipefail

readonly CORE_VERSION="0.16.4"
readonly ORT_VERSION="1.17.3"
readonly DICT_VERSION="1.11"
# テスト専用。アプリ本体には同梱しない(DESIGN_VOICEVOXの音声モデル取得.md §4)
readonly TEST_VVM="0"

readonly CORE_URL="https://github.com/VOICEVOX/voicevox_core/releases/download/${CORE_VERSION}/voicevox_core-ios-xcframework-cpu-${CORE_VERSION}.zip"
readonly ORT_URL="https://github.com/VOICEVOX/onnxruntime-builder/releases/download/voicevox_onnxruntime-${ORT_VERSION}/voicevox_onnxruntime-ios-xcframework-${ORT_VERSION}.zip"
readonly DICT_URL="https://downloads.sourceforge.net/open-jtalk/open_jtalk_dic_utf_8-${DICT_VERSION}.tar.gz"
readonly VVM_URL="https://raw.githubusercontent.com/VOICEVOX/voicevox_vvm/main/vvms/${TEST_VVM}.vvm"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly VENDOR_DIR="${REPO_ROOT}/NovelSpeaker/Vendor/VoicevoxCore"
readonly HEADER_PATCH="${SCRIPT_DIR}/voicevox_core_header.patch"

MODE="fetch"
case "${1:-}" in
  --check) MODE="check" ;;
  --force) MODE="force" ;;
  "") ;;
  *) echo "使い方: $0 [--check|--force]" >&2; exit 2 ;;
esac

info()  { echo "  $*"; }
ok()    { echo "  OK   $*"; }
warn()  { echo "  ★   $*"; }
fail()  { echo "エラー: $*" >&2; exit 1; }

# 公式の Content-Length を取る(取れなければ空)
remote_size() {
    curl -sIL --max-time 60 "$1" 2>/dev/null \
      | awk 'BEGIN{IGNORECASE=1} /^content-length:/ {v=$2} END{gsub(/\r/,"",v); print v}'
}

work_dir=""
cleanup() { [ -n "${work_dir}" ] && rm -rf "${work_dir}"; }
trap cleanup EXIT

need_work_dir() {
    [ -n "${work_dir}" ] && return
    work_dir="$(mktemp -d)" || fail "作業ディレクトリを作れませんでした"
}

# --- XCFramework ------------------------------------------------------------
# zip の中身は voicevox_core.xcframework/ の形で入っているので、そのまま展開する。
fetch_xcframework() {
    local name="$1" url="$2" version="$3"
    local target="${VENDOR_DIR}/${name}.xcframework"

    if [ -d "${target}" ] && [ "${MODE}" != "force" ]; then
        ok "${name}.xcframework (${version}) は既にあります"
        return 0
    fi
    if [ "${MODE}" = "check" ]; then
        warn "${name}.xcframework (${version}) がありません"
        return 0
    fi

    need_work_dir
    info "${name}.xcframework ${version} を取得しています…"
    curl -fsSL --max-time 600 -o "${work_dir}/${name}.zip" "${url}" \
        || fail "${name} の取得に失敗しました: ${url}"
    rm -rf "${target}"
    mkdir -p "${VENDOR_DIR}"
    unzip -qo "${work_dir}/${name}.zip" -d "${VENDOR_DIR}" \
        || fail "${name} の展開に失敗しました"
    [ -d "${target}" ] || fail "${name}.xcframework が展開されませんでした(配布物の構成が変わった?)"
    ok "${name}.xcframework ${version}"
}

# --- ヘッダのパッチ ---------------------------------------------------------
# 上流のヘッダは enum を `enum X {...}; typedef int32_t X;` と宣言しているため、
# Swift からは Int32 に見えて VoicevoxResultCode 等が列挙型として扱えない。
# `typedef enum X {...} X;` に直すことで Swift 側が列挙型として取り込めるようにする。
# (この変更は commit 7e27fff で入った。VoicevoxCore.swift はこれを前提にしている)
# 適用済みかどうかは、patch コマンドではなく中身の目印で判定する。
# macOS の patch は未適用のファイルに -R を当てると
# 「Unreversed (or previously applied) patch detected! Ignore -R? [y]」と聞いた上で
# **exit 0 を返す**ため、逆当ての成否では判定できない。
readonly UNPATCHED_MARK="typedef int32_t VoicevoxResultCode;"
readonly PATCHED_MARK="} VoicevoxResultCode;"

apply_header_patch() {
    local patched=0 already=0
    for header in "${VENDOR_DIR}"/voicevox_core.xcframework/*/voicevox_core.framework/Headers/voicevox_core.h; do
        [ -f "${header}" ] || continue
        if grep -qF "${PATCHED_MARK}" "${header}"; then
            already=$((already + 1))
            continue
        fi
        if ! grep -qF "${UNPATCHED_MARK}" "${header}"; then
            fail "ヘッダが未知の形です。上流の voicevox_core.h が変わった可能性があります: ${header}"
        fi
        if [ "${MODE}" = "check" ]; then
            warn "ヘッダにパッチが当たっていません: ${header}"
            continue
        fi
        # -t: 対話しない(何があっても質問で止まらせない)
        patch -s -t -p0 "${header}" < "${HEADER_PATCH}" \
            || fail "ヘッダへのパッチに失敗しました。上流のヘッダが変わった可能性があります: ${header}"
        grep -qF "${PATCHED_MARK}" "${header}" \
            || fail "ヘッダにパッチを当てましたが、期待の形になっていません: ${header}"
        patched=$((patched + 1))
    done
    if [ "${patched}" -gt 0 ]; then
        ok "ヘッダにパッチを当てました (${patched}件)"
    elif [ "${already}" -gt 0 ]; then
        ok "ヘッダのパッチは適用済みです (${already}件)"
    fi
}

# --- onnxruntime のバンドルID -----------------------------------------------
# 配布物の CFBundleIdentifier は "jp.hiroshiba.voicevox.voicevox_onnxruntime" だが、
# バンドルIDにアンダースコアは使えないため、そのままでは Embed & Sign できない。
# ハイフンに直す(この変更は commit 2e76f67 で入った)。
readonly ORT_BUNDLE_ID_BAD="jp.hiroshiba.voicevox.voicevox_onnxruntime"
readonly ORT_BUNDLE_ID_GOOD="jp.hiroshiba.voicevox.voicevox-onnxruntime"

fix_onnxruntime_bundle_identifier() {
    local fixed=0 already=0 current
    for plist in "${VENDOR_DIR}"/voicevox_onnxruntime.xcframework/*/voicevox_onnxruntime.framework/Info.plist; do
        [ -f "${plist}" ] || continue
        current="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${plist}" 2>/dev/null)"
        if [ "${current}" = "${ORT_BUNDLE_ID_GOOD}" ]; then
            already=$((already + 1))
            continue
        fi
        if [ "${current}" != "${ORT_BUNDLE_ID_BAD}" ]; then
            fail "onnxruntime のバンドルIDが未知の値です(${current}): ${plist}"
        fi
        if [ "${MODE}" = "check" ]; then
            warn "onnxruntime のバンドルIDが直されていません: ${plist}"
            continue
        fi
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${ORT_BUNDLE_ID_GOOD}" "${plist}" \
            || fail "onnxruntime のバンドルIDを直せませんでした: ${plist}"
        fixed=$((fixed + 1))
    done
    if [ "${fixed}" -gt 0 ]; then
        ok "onnxruntime のバンドルIDを直しました (${fixed}件)"
    elif [ "${already}" -gt 0 ]; then
        ok "onnxruntime のバンドルIDは直っています (${already}件)"
    fi
}

# --- Open JTalk 辞書 --------------------------------------------------------
# リリース資産には含まれていないので SourceForge から取る。
# 1.11 が 2018-12-25 リリースで、それが最新(事実上凍結している)。
fetch_dict() {
    local target="${VENDOR_DIR}/dict/open_jtalk_dic_utf_8-${DICT_VERSION}"

    if [ -f "${target}/sys.dic" ] && [ "${MODE}" != "force" ]; then
        ok "Open JTalk 辞書 ${DICT_VERSION} は既にあります"
        return 0
    fi
    if [ "${MODE}" = "check" ]; then
        warn "Open JTalk 辞書 ${DICT_VERSION} がありません"
        return 0
    fi

    need_work_dir
    info "Open JTalk 辞書 ${DICT_VERSION} を取得しています…(約23MB)"
    curl -fsSL --max-time 600 -o "${work_dir}/dict.tar.gz" "${DICT_URL}" \
        || fail "辞書の取得に失敗しました: ${DICT_URL}"
    rm -rf "${target}"
    mkdir -p "${VENDOR_DIR}/dict"
    tar -xzf "${work_dir}/dict.tar.gz" -C "${VENDOR_DIR}/dict" \
        || fail "辞書の展開に失敗しました"
    [ -f "${target}/sys.dic" ] || fail "辞書が期待の場所に展開されませんでした: ${target}"
    ok "Open JTalk 辞書 ${DICT_VERSION}"
}

# --- テスト用の VVM ---------------------------------------------------------
# アプリ本体には同梱しない。テストターゲットからのみ参照する。
# 無ければテストは XCTSkip されるだけなので、取得できなくても致命的ではない。
fetch_test_vvm() {
    local target="${VENDOR_DIR}/vvm/${TEST_VVM}.vvm"
    local remote local_size
    remote="$(remote_size "${VVM_URL}")"

    if [ -f "${target}" ]; then
        local_size="$(wc -c < "${target}" | tr -d ' ')"
        if [ -n "${remote}" ] && [ "${local_size}" != "${remote}" ]; then
            warn "テスト用 ${TEST_VVM}.vvm が公式より古いようです (手元 ${local_size} / 公式 ${remote})"
            [ "${MODE}" != "force" ] && info "     取り直すには --force を付けてください"
        else
            ok "テスト用 ${TEST_VVM}.vvm は最新です"
        fi
        [ "${MODE}" != "force" ] && return 0
    fi
    if [ "${MODE}" = "check" ]; then
        [ -f "${target}" ] || warn "テスト用 ${TEST_VVM}.vvm がありません(VOICEVOXのテストは skip されます)"
        return 0
    fi

    need_work_dir
    info "テスト用 ${TEST_VVM}.vvm を取得しています…(約58MB)"
    if ! curl -fsSL --max-time 900 -o "${work_dir}/test.vvm" "${VVM_URL}"; then
        warn "${TEST_VVM}.vvm の取得に失敗しました。VOICEVOXのテストは skip されます"
        return 0
    fi
    # zip として開けて metas.json が読める事を確かめてから置く(壊れた物を残さない)
    if ! unzip -p "${work_dir}/test.vvm" metas.json >/dev/null 2>&1; then
        warn "取得した ${TEST_VVM}.vvm の中身を確認できませんでした。配置しません"
        return 0
    fi
    mkdir -p "${VENDOR_DIR}/vvm"
    mv "${work_dir}/test.vvm" "${target}"
    ok "テスト用 ${TEST_VVM}.vvm"
}

# ---------------------------------------------------------------------------
case "${MODE}" in
    check) echo "VOICEVOX 関連の配置を調べます (${VENDOR_DIR})" ;;
    force) echo "VOICEVOX 関連を取り直します (${VENDOR_DIR})" ;;
    *)     echo "VOICEVOX 関連を用意します (${VENDOR_DIR})" ;;
esac

fetch_xcframework "voicevox_core"        "${CORE_URL}" "${CORE_VERSION}"
fetch_xcframework "voicevox_onnxruntime" "${ORT_URL}"  "${ORT_VERSION}"
apply_header_patch
fix_onnxruntime_bundle_identifier
fetch_dict
fetch_test_vvm

echo "完了しました。"
