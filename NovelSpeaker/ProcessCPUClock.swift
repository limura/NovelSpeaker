//
//  ProcessCPUClock.swift
//  NovelSpeaker
//
//  プロセスが使った CPU 時間を読む。
//
//  VOICEVOX の合成に入る前に「この1本を走らせたら背面のCPU上限を超えるか」を
//  見積もるために使う(VoicevoxCPUGovernor)。実時間ではなく CPU 時間なのは、
//  OS の上限判定が「全スレッド合計のCPU時間 ÷ 実時間」で行われるため。
//

import Foundation
import Darwin

/// プロセス全体の CPU 使用時間を取得するユーティリティ。
enum ProcessCPUClock {
    /// mach absolute time → 秒 への換算係数(初回に一度だけ取得)。
    private static let timebaseSecondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return 0 }
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0
    }()

    /// このプロセスが消費した CPU 時間(user+system, 全スレッドの合計)を秒で返す。
    /// OS のバックグラウンド CPU 上限も「全スレッド合計の CPU 時間 ÷ 実時間」で判定されるため、
    /// これと同じ土俵の値になる(1コアを100%使い切っている状態が 1.0)。
    static func totalCPUSeconds() -> Double? {
        var info = task_absolutetime_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_absolutetime_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_ABSOLUTETIME_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS, timebaseSecondsPerTick > 0 else { return nil }
        let ticks = Double(info.total_user) + Double(info.total_system)
        return ticks * timebaseSecondsPerTick
    }
}
